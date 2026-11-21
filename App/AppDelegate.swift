import AppKit
import AVFoundation
import ServiceManagement

enum Mode: String { case live, loop }

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    private let camera = Camera()
    private let player = LoopPlayer()
    private let sink = FrameSink()
    private let installer = ExtensionInstaller()
    private let settings = SettingsModel()
    private let settingsWindow = SettingsWindowController()
    private let hotKey = HotKey()
    private var shortcutMonitor: Any?

    private let pumpQueue = DispatchQueue(label: "afterimage.pump")
    private var pumpTimer: DispatchSourceTimer?
    private var lastSent: CVPixelBuffer?  // only touched on pumpQueue
    private var pollTimer: Timer?

    private var inUse = false
    private var cameraPresent = false
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
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Inside the app's sandbox container.
        let dir = base.appendingPathComponent("Afterimage", isDirectory: true)
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
            guard let self else { return }
            self.installStatus = msg
            // Take the user straight to the switch they need to flip.
            if self.installer.needsApproval { self.openExtensionSettings() }
            self.updateIcon()
        }
        installer.activate()
        wireSettings()
        hotKey.onPress = { [weak self] in self?.toggleMode() }

        // Open at login by default, once; after that the menu toggle decides.
        if !UserDefaults.standard.bool(forKey: "didSetUpLoginItem") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didSetUpLoginItem")
        }

        AVCaptureDevice.requestAccess(for: .video) { _ in }

        if FileManager.default.fileExists(atPath: Self.loopURL.path) { player.load(Self.loopURL) }

        startPump()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        poll()
        updateIcon()

        // First launch: explain how it works.
        if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            showSettings()
        }
    }

    /// Opening the app again (Finder, Launchpad, Spotlight) shows the settings window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        sink.stop()
    }

    // MARK: State

    /// Checks whether Zoom (or anything) is watching Afterimage and starts or
    /// stops the real webcam accordingly, so its light is only on during calls.
    private func poll() {
        let present = FrameSink.isDevicePresent()
        if present != cameraPresent {
            cameraPresent = present
            // The camera came back with new IDs: reconnect instead of
            // sending frames to the old one.
            pumpQueue.sync { sink.stop(); sink.reset() }
            inUse = false  // re-checked just below, which restarts the feed if needed
            updateIcon()
        }
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
        t.schedule(deadline: .now(), repeating: 1.0 / Double(CamConfig.fps), leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.sink.isStarted else { self.lastSent = nil; return }
            // While the new source warms up after a switch (webcam start-up,
            // first decoded loop frame), keep showing the last frame we sent
            // so the camera never falls back to its placeholder.
            let fresh = self.currentModeIsLoop ? self.player.currentFrame() : self.camera.latestFrame
            if let frame = fresh ?? self.lastSent {
                self.lastSent = frame
                self.sink.enqueue(frame)
            }
        }
        t.resume()
        pumpTimer = t
    }

    private var currentModeIsLoop: Bool {
        // Read from the pump queue; UserDefaults is thread-safe.
        UserDefaults.standard.string(forKey: "mode") == Mode.loop.rawValue
    }

    @objc private func setLive() { mode = .live }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openExtensionSettings() {
        NSWorkspace.shared.open(ExtensionInstaller.settingsURL)
    }

    @objc private func openCameraPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }
    @objc private func setLoop() { mode = .loop }
    private func toggleMode() { mode = mode == .live ? .loop : .live }

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
        alert.messageText = "Afterimage"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func revealLoop() {
        NSWorkspace.shared.activateFileViewerSelecting([Self.loopURL])
    }

    @objc private func toggleLoginItem() {
        setOpenAtLogin(SMAppService.mainApp.status != .enabled)
    }

    private func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            showError(error)
        }
        syncSettings()
    }

    // MARK: Settings window

    @objc private func showSettings() {
        settings.webcams = Camera.availableDevices().map { .init(id: $0.uniqueID, name: $0.localizedName) }
        syncSettings()
        settingsWindow.show(model: settings)
    }

    private func wireSettings() {
        settings.onRecord = { [weak self] in self?.recordLoop() }
        settings.onApprove = { [weak self] in self?.openExtensionSettings() }
        settings.onAllowWebcam = { [weak self] in self?.openCameraPrivacy() }
        settings.onRevealLoop = { [weak self] in self?.revealLoop() }
        settings.onSelectWebcam = { [weak self] id in self?.camera.select(deviceID: id) }
        settings.onSetOpenAtLogin = { [weak self] on in self?.setOpenAtLogin(on) }
        settings.onRecordShortcut = { [weak self] in self?.startRecordingShortcut() }
        settings.onClearShortcut = { [weak self] in self?.hotKey.set(nil); self?.syncSettings() }
    }

    /// Captures the next key press in the settings window as the Live/Loop shortcut.
    private func startRecordingShortcut() {
        if shortcutMonitor != nil { stopRecordingShortcut(); return }  // clicking again cancels
        hotKey.suspend()
        settings.recordingShortcut = true
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {  // Esc
                self.stopRecordingShortcut()
            } else if let combo = HotKey.combo(from: event) {
                self.hotKey.set(combo)
                self.stopRecordingShortcut()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stopRecordingShortcut() {
        if let m = shortcutMonitor { NSEvent.removeMonitor(m) }
        shortcutMonitor = nil
        settings.recordingShortcut = false
        hotKey.resume()
        syncSettings()
    }

    private func syncSettings() {
        if installer.needsApproval {
            settings.cameraStatus = .needsApproval
        } else if cameraPresent {
            settings.cameraStatus = .ready
        } else if installer.isReady {
            // Installed, but switched off in System Settings.
            settings.cameraStatus = .turnedOff
        } else if !installStatus.isEmpty {
            settings.cameraStatus = .problem(installStatus)
        } else {
            settings.cameraStatus = .checking
        }
        let auth = AVCaptureDevice.authorizationStatus(for: .video)
        settings.webcamDenied = auth == .denied || auth == .restricted
        settings.hasLoop = loopDate != nil
        settings.loopText = loopDescription()
        settings.recordTitle = recordingCountdown.map { "Recording… \($0)" } ?? (processing ? "Making loop…" : "Record Loop")
        settings.canRecord = recordingCountdown == nil && !processing
        settings.openAtLogin = SMAppService.mainApp.status == .enabled
        settings.selectedWebcam = camera.currentDeviceID ?? ""
        settings.shortcut = hotKey.combo?.display
    }

    @objc private func chooseWebcam(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        camera.select(deviceID: id)
    }

    // MARK: UI

    private var loopDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: Self.loopURL.path))?[.modificationDate] as? Date
    }

    private func updateIcon() {
        syncSettings()
        guard let button = statusItem?.button else { return }
        button.imagePosition = .imageLeading
        if let c = recordingCountdown {
            button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
            button.title = " \(c)"
            return
        }
        // Three states you can tell apart at a glance:
        //   nothing watching → normal glyph
        //   showing live     → white glyph on green
        //   showing the loop → white glyph on orange
        button.title = processing ? " …" : ""
        switch (inUse, mode) {
        case (false, _):
            button.image = MenuIcon.image(mode == .live ? .liveIdle : .loopIdle)
            button.toolTip = "Afterimage: no app is using the camera (\(mode == .live ? "Live" : "Loop") is selected)"
        case (true, .live):
            button.image = MenuIcon.highlighted(.liveActive, color: MenuIcon.liveColor)
            button.toolTip = "Afterimage: showing your live webcam"
        case (true, .loop):
            button.image = MenuIcon.highlighted(.loopActive, color: MenuIcon.loopColor)
            button.toolTip = "Afterimage: showing your loop"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = inUse ? "In use — showing \(mode == .live ? "live webcam" : "loop")" : "Not in use"
        menu.addItem(withTitle: header, action: nil, keyEquivalent: "").isEnabled = false
        if installer.needsApproval {
            menu.addItem(withTitle: "Approve Camera in System Settings…", action: #selector(openExtensionSettings), keyEquivalent: "")
        } else if installer.isReady && !cameraPresent {
            menu.addItem(withTitle: "Turn On Camera in System Settings…", action: #selector(openExtensionSettings), keyEquivalent: "")
        } else if !installStatus.isEmpty {
            menu.addItem(withTitle: installStatus, action: nil, keyEquivalent: "").isEnabled = false
        }
        let camAuth = AVCaptureDevice.authorizationStatus(for: .video)
        if camAuth == .denied || camAuth == .restricted {
            menu.addItem(withTitle: "Allow Webcam Access in System Settings…", action: #selector(openCameraPrivacy), keyEquivalent: "")
        }
        menu.addItem(.separator())

        let live = menu.addItem(withTitle: "Live", action: #selector(setLive), keyEquivalent: "")
        live.state = mode == .live ? .on : .off
        let loop = menu.addItem(withTitle: "Loop", action: #selector(setLoop), keyEquivalent: "")
        loop.state = mode == .loop ? .on : .off
        menu.addItem(.separator())

        let rec = menu.addItem(withTitle: recordingCountdown != nil ? "Recording…" : processing ? "Making loop…" : "Record Loop",
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
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        // Own selector rather than NSApplication.terminate(_:), which macOS 26
        // recognizes as a standard action and decorates with an icon.
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Quit Afterimage", action: #selector(quit), keyEquivalent: "q")

        for item in menu.items where item.action != nil {
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
