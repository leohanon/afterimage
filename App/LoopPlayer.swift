import AVFoundation
import QuartzCore

/// Plays the loop file forever and hands out the current frame on demand.
final class LoopPlayer {
    private let player = AVPlayer()
    private var output: AVPlayerItemVideoOutput?
    private let normalizer = Normalizer()
    private var lastFrame: CVPixelBuffer?
    private var endObserver: NSObjectProtocol?
    private let lock = NSLock()

    init() {
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.preventsDisplaySleepDuringVideoPlayback = false
    }

    func load(_ url: URL) {
        let item = AVPlayerItem(url: url)
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(out)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        lock.lock(); output = out; lastFrame = nil; lock.unlock()
        player.replaceCurrentItem(with: item)
    }

    func play() { player.play() }
    func pause() { player.pause() }
    var hasItem: Bool { player.currentItem != nil }

    func currentFrame() -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        guard let output else { return nil }
        let t = output.itemTime(forHostTime: CACurrentMediaTime())
        if output.hasNewPixelBuffer(forItemTime: t),
           let pb = output.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil),
           let frame = normalizer.normalize(pb) {
            lastFrame = frame
        }
        return lastFrame
    }
}
