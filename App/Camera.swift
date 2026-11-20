import AVFoundation
import CoreVideo

/// Captures the real webcam. Keeps the latest frame for the live feed and,
/// while recording, also writes frames to a movie file.
final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "afterimage.camera")
    private let normalizer = Normalizer()
    private let lock = NSLock()
    private var _latest: CVPixelBuffer?
    private var configured = false

    private var recorder: Recorder?

    var latestFrame: CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return _latest
    }

    var isRunning: Bool { session.isRunning }

    /// Every real camera (never Afterimage itself).
    static func availableDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices.filter { $0.localizedName != CamConfig.deviceName && $0.uniqueID != CamConfig.deviceUID }
    }

    /// The camera chosen in the menu, else a USB webcam, else the built-in one.
    static func pickDevice() -> AVCaptureDevice? {
        let devices = availableDevices()
        if let id = UserDefaults.standard.string(forKey: "webcamID"), let d = devices.first(where: { $0.uniqueID == id }) {
            return d
        }
        return devices.first { $0.deviceType == .external }
            ?? devices.first { $0.deviceType == .builtInWideAngleCamera }
            ?? devices.first
    }

    var currentDeviceID: String? {
        (session.inputs.first as? AVCaptureDeviceInput)?.device.uniqueID ?? Self.pickDevice()?.uniqueID
    }

    /// Switches to another webcam (takes effect immediately if running).
    func select(deviceID: String) {
        UserDefaults.standard.set(deviceID, forKey: "webcamID")
        queue.async {
            guard self.configured, let device = Self.pickDevice(),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            if self.session.canAddInput(input) { self.session.addInput(input) }
            self.session.commitConfiguration()
        }
    }

    private func configure() -> Bool {
        if configured { return true }
        guard let device = Self.pickDevice(), let input = try? AVCaptureDeviceInput(device: device) else {
            NSLog("Afterimage: no webcam found")
            return false
        }
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        configured = true
        return true
    }

    func start() {
        queue.async {
            guard self.configure(), !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async {
            guard self.session.isRunning, self.recorder == nil else { return }
            self.session.stopRunning()
            self.lock.lock(); self._latest = nil; self.lock.unlock()
        }
    }

    /// Records `seconds` of webcam footage to `url`, then calls `completion` on the main queue.
    func record(seconds: Double, to url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async {
            guard self.configure() else {
                DispatchQueue.main.async { completion(.failure(LoopError.noCamera)) }
                return
            }
            if !self.session.isRunning { self.session.startRunning() }
            do {
                self.recorder = try Recorder(url: url, seconds: seconds) { [weak self] result in
                    self?.queue.async { self?.recorder = nil }
                    DispatchQueue.main.async { completion(result) }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer), let frame = normalizer.normalize(pb) else { return }
        lock.lock(); _latest = frame; lock.unlock()
        recorder?.append(frame, at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}

enum LoopError: LocalizedError {
    case noCamera, writerFailed(String), emptyRecording

    var errorDescription: String? {
        switch self {
        case .noCamera: "No webcam found."
        case .writerFailed(let s): "Couldn't write the video: \(s)"
        case .emptyRecording: "The recording had no frames."
        }
    }
}

/// Writes 1280x720 frames to an H.264 file for a fixed duration.
final class Recorder {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let seconds: Double
    private var startTime: CMTime?
    private var finished = false
    private let completion: (Result<URL, Error>) -> Void

    init(url: URL, seconds: Double, completion: @escaping (Result<URL, Error>) -> Void) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings())
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        self.seconds = seconds
        self.completion = completion
    }

    func append(_ frame: CVPixelBuffer, at time: CMTime) {
        guard !finished else { return }
        if startTime == nil {
            guard writer.startWriting() else { return fail() }
            writer.startSession(atSourceTime: time)
            startTime = time
        }
        if CMTimeGetSeconds(CMTimeSubtract(time, startTime!)) >= seconds {
            finished = true
            input.markAsFinished()
            writer.finishWriting { [writer, completion] in
                if writer.status == .completed { completion(.success(writer.outputURL)) }
                else { completion(.failure(LoopError.writerFailed(writer.error?.localizedDescription ?? "unknown"))) }
            }
            return
        }
        if input.isReadyForMoreMediaData { adaptor.append(frame, withPresentationTime: time) }
    }

    private func fail() {
        finished = true
        completion(.failure(LoopError.writerFailed(writer.error?.localizedDescription ?? "unknown")))
    }
}

func videoSettings() -> [String: Any] {
    [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: CamConfig.width,
        AVVideoHeightKey: CamConfig.height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
    ]
}
