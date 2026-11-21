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
            kCVPixelBufferWidthKey as String: CamConfig.width,
            kCVPixelBufferHeightKey as String: CamConfig.height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var p: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &p)
        pool = p!
    }

    func normalize(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        if CVPixelBufferGetWidth(src) == Int(CamConfig.width),
           CVPixelBufferGetHeight(src) == Int(CamConfig.height),
           CVPixelBufferGetPixelFormatType(src) == kCVPixelFormatType_32BGRA {
            return src
        }
        cropToOutputAspect(src)
        var dst: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &dst)
        guard let dst, VTPixelTransferSessionTransferImage(session, from: src, to: dst) == noErr else { return nil }
        return dst
    }

    /// Marks a centered 16:9 region of the source as its clean aperture, so the
    /// transfer (which crops to the clean aperture) fills the frame without
    /// stretching a 4:3 or otherwise non-widescreen picture.
    private func cropToOutputAspect(_ src: CVPixelBuffer) {
        let w = Double(CVPixelBufferGetWidth(src)), h = Double(CVPixelBufferGetHeight(src))
        let target = Double(CamConfig.width) / Double(CamConfig.height)
        var cw = w, ch = h
        if w / h > target { cw = (h * target).rounded() } else { ch = (w / target).rounded() }
        let aperture: [CFString: Any] = [
            kCVImageBufferCleanApertureWidthKey: cw,
            kCVImageBufferCleanApertureHeightKey: ch,
            kCVImageBufferCleanApertureHorizontalOffsetKey: 0,
            kCVImageBufferCleanApertureVerticalOffsetKey: 0,
        ]
        CVBufferSetAttachment(src, kCVImageBufferCleanApertureKey, aperture as CFDictionary, .shouldPropagate)
    }
}
