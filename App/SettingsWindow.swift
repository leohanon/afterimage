import AppKit
import SwiftUI

/// What the settings window shows. AppDelegate keeps it current and handles the actions.
final class SettingsModel: ObservableObject {
    struct Webcam: Identifiable, Hashable { let id: String; let name: String }

    enum CameraStatus { case checking, ready, needsApproval, turnedOff, problem(String) }

    @Published var cameraStatus: CameraStatus = .checking
    @Published var webcamDenied = false
    @Published var loopText = ""
    @Published var hasLoop = false
    @Published var recordTitle = "Record Loop"
    @Published var canRecord = true
    @Published var openAtLogin = false
    @Published var webcams: [Webcam] = []
    @Published var selectedWebcam = ""

    var onRecord: () -> Void = {}
    var onApprove: () -> Void = {}
    var onAllowWebcam: () -> Void = {}
    var onRevealLoop: () -> Void = {}
    var onSelectWebcam: (String) -> Void = { _ in }
    var onSetOpenAtLogin: (Bool) -> Void = { _ in }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Afterimage").font(.title2.bold())
                    Text("Look present on video calls when you need a moment away.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("How it works").font(.headline)
                step(1, "Record a 10-second loop of yourself.")
                step(2, "In Zoom, Meet, or any video app, choose **Afterimage** as your camera.")
                step(3, "Switch between **Live** and **Loop** from the menu bar icon.")
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                cameraRow
                if model.webcamDenied {
                    row("Webcam") {
                        Button("Allow Access…", action: model.onAllowWebcam)
                    }
                }
                row("Loop") {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack {
                            if model.hasLoop { Button("Show in Finder", action: model.onRevealLoop) }
                            Button(model.recordTitle, action: model.onRecord).disabled(!model.canRecord)
                        }
                        Text(model.loopText).font(.caption).foregroundStyle(.secondary)
                    }
                }
                row("Webcam") {
                    Picker("", selection: Binding(get: { model.selectedWebcam },
                                                  set: { model.selectedWebcam = $0; model.onSelectWebcam($0) })) {
                        ForEach(model.webcams) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden().fixedSize()  // size to the name so it sits flush right
                }
                row("Open at login") {
                    Toggle("", isOn: Binding(get: { model.openAtLogin },
                                             set: { model.onSetOpenAtLogin($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    @ViewBuilder private var cameraRow: some View {
        row("Camera") {
            switch model.cameraStatus {
            case .checking:
                Text("Checking…").foregroundStyle(.secondary)
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .needsApproval:
                VStack(alignment: .trailing, spacing: 4) {
                    Button("Approve in System Settings…", action: model.onApprove)
                    Text("Click ⓘ next to Camera Extensions, then turn on Afterimage.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .turnedOff:
                VStack(alignment: .trailing, spacing: 4) {
                    Button("Turn On in System Settings…", action: model.onApprove)
                    Text("Click ⓘ next to Camera Extensions, then turn on Afterimage.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .problem(let msg):
                Text(msg).foregroundStyle(.orange).multilineTextAlignment(.trailing)
            }
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.callout.bold()).foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(red: 0.847, green: 0.353, blue: 0.188)))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            content()
        }
    }
}

final class SettingsWindowController {
    private var window: NSWindow?

    func show(model: SettingsModel) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "Afterimage"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
