import CoreVideo
import VideoToolbox

/// Scales/converts any frame to the camera's fixed 1280x720 BGRA format.
final class Normalizer {
    private let session: VTPixelTransferSession
    private let pool: CVPixelBufferPool

    init() {
        var s: VTPixelTransferSession?
        VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &s)
        session = s!
        // Fill the frame, cropping edges if the aspect ratio differs (no black bars).
        VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_ScalingMode, value: kVTScalingMode_CropSourceToCleanAperture)

        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: LoopCam.width,
            kCVPixelBufferHeightKey as String: LoopCam.height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var p: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &p)
        pool = p!
    }

    func normalize(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        if CVPixelBufferGetWidth(src) == Int(LoopCam.width),
           CVPixelBufferGetHeight(src) == Int(LoopCam.height),
           CVPixelBufferGetPixelFormatType(src) == kCVPixelFormatType_32BGRA {
            return src
        }
        var dst: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &dst)
        guard let dst, VTPixelTransferSessionTransferImage(session, from: src, to: dst) == noErr else { return nil }
        return dst
    }
}
