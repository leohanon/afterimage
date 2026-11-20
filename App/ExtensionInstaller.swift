import Foundation
import SystemExtensions

/// Asks macOS to install (or update) the bundled camera extension.
final class ExtensionInstaller: NSObject, OSSystemExtensionRequestDelegate {
    var onStatus: ((String) -> Void)?

    func activate() {
        let req = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: LoopCam.extensionBundleID, queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        onStatus?("Approve LoopCam in System Settings → General → Login Items & Extensions → Camera Extensions.")
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        onStatus?(result == .willCompleteAfterReboot ? "Camera installed; restart your Mac to finish." : "")
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let ns = error as NSError
        var msg = "Camera install failed: \(error.localizedDescription)"
        if ns.domain == OSSystemExtensionErrorDomain, ns.code == OSSystemExtensionError.unsupportedParentBundleLocation.rawValue {
            msg = "Move LoopCam.app to /Applications, then reopen it."
        }
        onStatus?(msg)
    }
}
