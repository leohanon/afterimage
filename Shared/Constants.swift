import Foundation

enum LoopCam {
    static let deviceName = "LoopCam"
    static let manufacturer = "LoopCam"
    /// Stable identifiers so Zoom remembers the camera across launches.
    static let deviceUID = "6B2F8E57-3A51-4C7B-9D0B-5D1A3E2F7C10"
    static let sourceStreamUID = "6B2F8E57-3A51-4C7B-9D0B-5D1A3E2F7C11"
    static let sinkStreamUID = "6B2F8E57-3A51-4C7B-9D0B-5D1A3E2F7C12"

    static let width: Int32 = 1280
    static let height: Int32 = 720
    static let fps: Int32 = 30

    static let extensionBundleID = "com.leohanon.LoopCam.Extension"

    /// Custom CMIO property the extension exposes: "1" while some app (e.g. Zoom)
    /// is streaming from the camera, "0" otherwise. Lets the app keep the real
    /// webcam off when nobody is watching.
    static let activePropertyName = "4cc_actv_glob_0000"
    static let activePropertySelector: UInt32 = fourCC("actv")
}

func fourCC(_ s: String) -> UInt32 {
    s.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
}
