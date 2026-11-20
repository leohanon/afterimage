import Foundation

enum CamConfig {
    static let deviceName = "Afterimage"
    static let manufacturer = "Afterimage"
    /// Stable identifiers so Zoom remembers the camera across launches.
    static let deviceUID = "990D2C54-3D00-43A6-BD09-D3E975AB6030"
    static let sourceStreamUID = "990D2C54-3D00-43A6-BD09-D3E975AB6031"
    static let sinkStreamUID = "990D2C54-3D00-43A6-BD09-D3E975AB6032"

    static let width: Int32 = 1280
    static let height: Int32 = 720
    static let fps: Int32 = 30

    static let extensionBundleID = "com.leohanon.Afterimage.Extension"

    /// Custom CMIO property the extension exposes: "1" while some app (e.g. Zoom)
    /// is streaming from the camera, "0" otherwise. Lets the app keep the real
    /// webcam off when nobody is watching.
    static let activePropertyName = "4cc_actv_glob_0000"
    static let activePropertySelector: UInt32 = fourCC("actv")
}

func fourCC(_ s: String) -> UInt32 {
    s.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
}
