import Foundation
import SystemExtensions

/// Asks macOS to install (or update) the bundled camera extension.
final class ExtensionInstaller: NSObject, OSSystemExtensionRequestDelegate {
    var onStatus: ((String) -> Void)?

    func activate() {
        let req = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: CamConfig.extensionBundleID, queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    /// True while macOS is waiting for the user to switch the camera on in System Settings.
    private(set) var needsApproval = false

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        needsApproval = true
        onStatus?("Camera needs your approval")
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        needsApproval = false
        onStatus?(result == .willCompleteAfterReboot ? "Camera installed; restart your Mac to finish." : "")
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let ns = error as NSError
        var msg = "Camera install failed: \(error.localizedDescription)"
        if ns.domain == OSSystemExtensionErrorDomain, ns.code == OSSystemExtensionError.unsupportedParentBundleLocation.rawValue {
            msg = "Move Afterimage.app to /Applications, then reopen it."
        }
        onStatus?(msg)
    }
}
