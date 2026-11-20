import AppKit
import IOKit.audio
import CoreMediaIO
import CoreVideo
import Foundation
import os.log

private let log = Logger(subsystem: LoopCam.extensionBundleID, category: "ext")

// MARK: - Device

/// The virtual camera. It has two streams:
///  - a *source* stream that apps like Zoom read from, and
///  - a *sink* stream that the LoopCam menu-bar app writes frames into.
/// Frames arriving on the sink are forwarded straight to the source. When no
/// frames arrive (app not running), a placeholder frame is shown instead.
final class DeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private var sourceStream: StreamSource!
    private var sinkStream: SinkSource!

    let formatDescription: CMFormatDescription
    private let bufferPool: CVPixelBufferPool
    private let poolAttrs: NSDictionary

    private var sourceClients = 0
    private let queue = DispatchQueue(label: "loopcam.device")
    private var idleTimer: DispatchSourceTimer?
    private var lastSinkFrame: UInt64 = 0
    private var placeholder: CVPixelBuffer?

    init(localizedName: String) {
        var fd: CMFormatDescription?
        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                       codecType: kCVPixelFormatType_32BGRA,
                                       width: LoopCam.width, height: LoopCam.height,
                                       extensions: nil, formatDescriptionOut: &fd)
        formatDescription = fd!

        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: LoopCam.width,
            kCVPixelBufferHeightKey as String: LoopCam.height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
        bufferPool = pool!
        poolAttrs = [kCVPixelBufferPoolAllocationThresholdKey: 8]

        super.init()

        device = CMIOExtensionDevice(localizedName: localizedName,
                                     deviceID: UUID(uuidString: LoopCam.deviceUID)!,
                                     legacyDeviceID: LoopCam.deviceUID,
                                     source: self)

        let format = CMIOExtensionStreamFormat(formatDescription: formatDescription,
                                               maxFrameDuration: CMTime(value: 1, timescale: LoopCam.fps),
                                               minFrameDuration: CMTime(value: 1, timescale: LoopCam.fps),
                                               validFrameDurations: nil)

        sourceStream = StreamSource(device: self, format: format)
        sourceStream.stream = CMIOExtensionStream(localizedName: "LoopCam.Video",
                                                  streamID: UUID(uuidString: LoopCam.sourceStreamUID)!,
                                                  direction: .source, clockType: .hostTime,
                                                  source: sourceStream)
        sinkStream = SinkSource(device: self, format: format)
        sinkStream.stream = CMIOExtensionStream(localizedName: "LoopCam.Sink",
                                                streamID: UUID(uuidString: LoopCam.sinkStreamUID)!,
                                                direction: .sink, clockType: .hostTime,
                                                source: sinkStream)
        do {
            try device.addStream(sourceStream.stream)
            try device.addStream(sinkStream.stream)
        } catch {
            fatalError("Failed to add streams: \(error)")
        }
    }

    // MARK: Device properties

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel, CMIOExtensionProperty(rawValue: LoopCam.activePropertyName)]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let props = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            props.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            props.model = LoopCam.deviceName
        }
        let active = CMIOExtensionProperty(rawValue: LoopCam.activePropertyName)
        if properties.contains(active) {
            let value = queue.sync { sourceClients > 0 ? "1" : "0" }
            props.setPropertyState(CMIOExtensionPropertyState(value: value as NSString), forProperty: active)
        }
        return props
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    // MARK: Source (Zoom side)

    func sourceStarted() {
        queue.sync {
            sourceClients += 1
            if sourceClients == 1 { startIdleTimer() }
        }
        notifyActiveChanged()
    }

    func sourceStopped() {
        queue.sync {
            sourceClients = max(0, sourceClients - 1)
            if sourceClients == 0 { idleTimer?.cancel(); idleTimer = nil }
        }
        notifyActiveChanged()
    }

    private func notifyActiveChanged() {
        let active = CMIOExtensionProperty(rawValue: LoopCam.activePropertyName)
        let value = queue.sync { sourceClients > 0 ? "1" : "0" }
        let props = CMIOExtensionDeviceProperties(dictionary: [:])
        props.setPropertyState(CMIOExtensionPropertyState(value: value as NSString), forProperty: active)
        device.notifyPropertiesChanged(props.propertiesDictionary)
    }

    /// While someone watches but the app isn't feeding frames, show a placeholder.
    private func startIdleTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 1.0 / Double(LoopCam.fps))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let now = mach_absolute_time()
            if self.lastSinkFrame != 0, nanos(now - self.lastSinkFrame) < 500_000_000 { return }
            if let pb = self.placeholderBuffer() { self.emit(pb) }
        }
        t.resume()
        idleTimer = t
    }

    // MARK: Sink (LoopCam app side)

    func received(_ sbuf: CMSampleBuffer) {
        guard let pb = CMSampleBufferGetImageBuffer(sbuf) else { return }
        queue.async {
            self.lastSinkFrame = mach_absolute_time()
            guard self.sourceClients > 0 else { return }
            self.emit(pb)
        }
    }

    private func emit(_ pixelBuffer: CVPixelBuffer) {
        let hostNanos = nanos(mach_absolute_time())
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: LoopCam.fps),
                                        presentationTimeStamp: CMTime(value: CMTimeValue(hostNanos), timescale: 1_000_000_000),
                                        decodeTimeStamp: .invalid)
        var fd: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &fd)
        guard let fd else { return }
        var sbuf: CMSampleBuffer?
        let err = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                           formatDescription: fd, sampleTiming: &timing,
                                                           sampleBufferOut: &sbuf)
        if err == noErr, let sbuf {
            sourceStream.stream.send(sbuf, discontinuity: [], hostTimeInNanoseconds: hostNanos)
        }
    }

    /// Dark gray frame with "LoopCam" in the middle, drawn once and reused.
    private func placeholderBuffer() -> CVPixelBuffer? {
        if let placeholder { return placeholder }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, bufferPool, poolAttrs, &pb)
        guard let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        let text = NSAttributedString(string: "LoopCam", attributes: [
            .font: NSFont.systemFont(ofSize: 56, weight: .semibold),
            .foregroundColor: NSColor(white: 0.55, alpha: 1),
        ])
        let size = text.size()
        text.draw(at: CGPoint(x: (CGFloat(w) - size.width) / 2, y: (CGFloat(h) - size.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        placeholder = pb
        return pb
    }
}

private func nanos(_ machTime: UInt64) -> UInt64 {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return machTime * UInt64(info.numer) / UInt64(info.denom)
}

// MARK: - Source stream (read by Zoom)

final class StreamSource: NSObject, CMIOExtensionStreamSource {
    var stream: CMIOExtensionStream!
    private unowned let device: DeviceSource
    private let format: CMIOExtensionStreamFormat

    init(device: DeviceSource, format: CMIOExtensionStreamFormat) {
        self.device = device
        self.format = format
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }
    var availableProperties: Set<CMIOExtensionProperty> { [.streamActiveFormatIndex, .streamFrameDuration] }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { props.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) {
            props.frameDuration = CMTime(value: 1, timescale: LoopCam.fps)
        }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}
    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { true }
    func startStream() throws { device.sourceStarted() }
    func stopStream() throws { device.sourceStopped() }
}

// MARK: - Sink stream (written by the LoopCam app)

final class SinkSource: NSObject, CMIOExtensionStreamSource {
    var stream: CMIOExtensionStream!
    private unowned let device: DeviceSource
    private let format: CMIOExtensionStreamFormat
    private var client: CMIOExtensionClient?
    private var running = false

    init(device: DeviceSource, format: CMIOExtensionStreamFormat) {
        self.device = device
        self.format = format
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }
    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration, .streamSinkBufferQueueSize,
         .streamSinkBuffersRequiredForStartup, .streamSinkBufferUnderrunCount, .streamSinkEndOfData]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { props.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) {
            props.frameDuration = CMTime(value: 1, timescale: LoopCam.fps)
        }
        if properties.contains(.streamSinkBufferQueueSize) { props.sinkBufferQueueSize = 4 }
        if properties.contains(.streamSinkBuffersRequiredForStartup) { props.sinkBuffersRequiredForStartup = 1 }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        self.client = client
        return true
    }

    func startStream() throws {
        guard let client else { throw NSError(domain: "LoopCam", code: 1) }
        running = true
        consume(from: client)
    }

    func stopStream() throws {
        running = false
    }

    private func consume(from client: CMIOExtensionClient) {
        stream.consumeSampleBuffer(from: client) { [weak self] sbuf, seq, _, _, err in
            guard let self, self.running else { return }
            if let sbuf {
                self.device.received(sbuf)
                let output = CMIOExtensionScheduledOutput(sequenceNumber: seq,
                                                          hostTimeInNanoseconds: nanos(mach_absolute_time()))
                self.stream.notifyScheduledOutputChanged(output)
            } else if let err {
                log.debug("sink consume error: \(err.localizedDescription)")
            }
            // Keep pulling, with a tiny backoff when nothing was available.
            DispatchQueue.global().asyncAfter(deadline: .now() + (sbuf == nil ? 0.005 : 0)) {
                if self.running { self.consume(from: client) }
            }
        }
    }
}

// MARK: - Provider

final class ProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: DeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = DeviceSource(localizedName: LoopCam.deviceName)
        do { try provider.addDevice(deviceSource.device) } catch { fatalError("addDevice failed: \(error)") }
    }

    func connect(to client: CMIOExtensionClient) throws {}
    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> { [.providerManufacturer] }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let props = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) { props.manufacturer = LoopCam.manufacturer }
        return props
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}
