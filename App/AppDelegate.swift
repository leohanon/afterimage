import AppKit
import AVFoundation
import Carbon

enum Mode: String { case live, loop }

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    private let camera = Camera()
    private let player = LoopPlayer()
    private let sink = FrameSink()
    private let installer = ExtensionInstaller()
    private var hotKey: HotKey?

    private let pumpQueue = DispatchQueue(label: "loopcam.pump")
    private var pumpTimer: DispatchSourceTimer?
    private var pollTimer: Timer?

    private var inUse = false
    private var recordingCountdown: Int?
    private var processing = false
    private var installStatus = ""

    private var mode: Mode = Mode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .live {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "mode")
            applyState()
        }
    }

    static let recordSeconds = 10.0

    static var supportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LoopCam", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var loopURL: URL { supportDir.appendingPathComponent("loop.mp4") }
    static var rawURL: URL { supportDir.appendingPathComponent("raw.mov") }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        statusItem.menu = menu

        installer.onStatus = { [weak self] msg in
            self?.installStatus = msg
            self?.updateIcon()
        }
        installer.activate()

        AVCaptureDevice.requestAccess(for: .video) { _ in }

        if FileManager.default.fileExists(atPath: Self.loopURL.path) { player.load(Self.loopURL) }

        // ⌃⌥⌘L toggles Live / Loop from anywhere.
        hotKey = HotKey(keyCode: kVK_ANSI_L, modifiers: controlKey | optionKey | cmdKey) { [weak self] in
            self?.toggleMode()
        }

        startPump()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        poll()
        updateIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sink.stop()
    }

    // MARK: State

    /// Checks whether Zoom (or anything) is watching LoopCam and starts or
    /// stops the real webcam accordingly, so its light is only on during calls.
    private func poll() {
        let nowInUse = sink.isCameraInUse()
        if nowInUse != inUse {
            inUse = nowInUse
            applyState()
        }
    }

    private func applyState() {
        if inUse {
            pumpQueue.async { self.sink.start() }
            switch mode {
            case .live:
                camera.start()
                player.pause()
            case .loop:
                player.play()
                if recordingCountdown == nil { camera.stop() }
            }
        } else {
            pumpQueue.async { self.sink.stop() }
            player.pause()
            if recordingCountdown == nil { camera.stop() }
        }
        updateIcon()
    }

    /// Feeds the virtual camera at a steady 30 fps.
    private func startPump() {
        let t = DispatchSource.makeTimerSource(queue: pumpQueue)
        t.schedule(deadline: .now(), repeating: 1.0 / Double(LoopCam.fps), leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in
            guard let self, self.sink.isStarted else { return }
            let frame = self.currentModeIsLoop ? self.player.currentFrame() : self.camera.latestFrame
            if let frame { self.sink.enqueue(frame) }
        }
        t.resume()
        pumpTimer = t
    }

    private var currentModeIsLoop: Bool {
        // Read from the pump queue; UserDefaults is thread-safe.
        UserDefaults.standard.string(forKey: "mode") == Mode.loop.rawValue
    }

    @objc private func toggleMode() {
        mode = (mode == .live) ? .loop : .live
    }

    @objc private func setLive() { mode = .live }
    @objc private func setLoop() { mode = .loop }

    // MARK: Recording

    @objc private func recordLoop() {
        guard recordingCountdown == nil, !processing else { return }
        recordingCountdown = Int(Self.recordSeconds)
        updateIcon()
        let tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, let c = self.recordingCountdown, c > 1 else { timer.invalidate(); return }
            self.recordingCountdown = c - 1
            self.updateIcon()
        }
        // Small delay so you can settle in after clicking the menu.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.camera.record(seconds: Self.recordSeconds, to: Self.rawURL) { [weak self] result in
                tick.invalidate()
                guard let self else { return }
                self.recordingCountdown = nil
                switch result {
                case .success(let raw):
                    self.processing = true
                    self.applyState()
                    Task {
                        do {
                            try await LoopMaker.makePingPong(from: raw, to: Self.loopURL)
                            try? FileManager.default.removeItem(at: raw)
                            await MainActor.run {
                                self.processing = false
                                self.player.load(Self.loopURL)
                                if self.inUse, self.mode == .loop { self.player.play() }
                                self.updateIcon()
                            }
                        } catch {
                            await MainActor.run {
                                self.processing = false
                                self.showError(error)
                                self.updateIcon()
                            }
                        }
                    }
                case .failure(let error):
                    self.applyState()
                    self.showError(error)
                }
            }
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "LoopCam"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func revealLoop() {
        NSWorkspace.shared.activateFileViewerSelecting([Self.loopURL])
    }

    @objc private func reinstallExtension() { installer.activate() }

    @objc private func chooseWebcam(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        camera.select(deviceID: id)
    }

    // MARK: UI

    private var loopDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: Self.loopURL.path))?[.modificationDate] as? Date
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        if let c = recordingCountdown {
            button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
            button.title = " \(c)"
            return
        }
        button.title = processing ? " …" : ""
        let symbol: String
        switch mode {
        case .live: symbol = inUse ? "video.fill" : "video"
        case .loop: symbol = inUse ? "repeat.circle.fill" : "repeat.circle"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "LoopCam")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = inUse ? "In use — showing \(mode == .live ? "live webcam" : "loop")" : "Not in use"
        menu.addItem(withTitle: header, action: nil, keyEquivalent: "").isEnabled = false
        if !installStatus.isEmpty {
            menu.addItem(withTitle: installStatus, action: nil, keyEquivalent: "").isEnabled = false
        }
        menu.addItem(.separator())

        let live = menu.addItem(withTitle: "Live", action: #selector(setLive), keyEquivalent: "")
        live.state = mode == .live ? .on : .off
        let loop = menu.addItem(withTitle: "Loop", action: #selector(setLoop), keyEquivalent: "")
        loop.state = mode == .loop ? .on : .off
        let toggle = menu.addItem(withTitle: "Toggle", action: #selector(toggleMode), keyEquivalent: "l")
        toggle.keyEquivalentModifierMask = [.control, .option, .command]
        menu.addItem(.separator())

        let rec = menu.addItem(withTitle: recordingCountdown != nil ? "Recording…" : processing ? "Making loop…" : "Record Today's Loop (\(Int(Self.recordSeconds)) s)",
                               action: #selector(recordLoop), keyEquivalent: "")
        rec.isEnabled = recordingCountdown == nil && !processing
        menu.addItem(withTitle: loopDescription(), action: nil, keyEquivalent: "").isEnabled = false
        if loopDate != nil {
            menu.addItem(withTitle: "Show Loop in Finder", action: #selector(revealLoop), keyEquivalent: "")
        }
        menu.addItem(.separator())
        let webcamItem = menu.addItem(withTitle: "Webcam", action: nil, keyEquivalent: "")
        let webcams = NSMenu()
        let current = camera.currentDeviceID
        for d in Camera.availableDevices() {
            let item = webcams.addItem(withTitle: d.localizedName, action: #selector(chooseWebcam(_:)), keyEquivalent: "")
            item.representedObject = d.uniqueID
            item.state = d.uniqueID == current ? .on : .off
            item.target = self
        }
        webcamItem.submenu = webcams
        menu.addItem(withTitle: "Reinstall Camera Extension", action: #selector(reinstallExtension), keyEquivalent: "")
        menu.addItem(withTitle: "Quit LoopCam", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        for item in menu.items where item.action != nil && item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
    }

    private func loopDescription() -> String {
        guard let date = loopDate else { return "No loop recorded yet" }
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Loop recorded today at \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "⚠︎ Loop is from yesterday at \(time)" }
        return "⚠︎ Loop is from \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}
