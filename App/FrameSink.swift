import CoreMediaIO
import CoreVideo
import Foundation

/// Talks to the LoopCam camera extension through the CoreMediaIO C API:
/// finds the virtual device, reads whether anyone is watching, and pushes
/// frames into its sink stream.
final class FrameSink {
    private var deviceID: CMIOObjectID = 0
    private var sinkStreamID: CMIOStreamID = 0
    private var queue: CMSimpleQueue?
    private(set) var isStarted = false

    /// Finds the LoopCam device. Returns false if the extension isn't installed yet.
    @discardableResult
    func connect() -> Bool {
        if deviceID != 0 { return true }
        for dev in Self.allDevices() where Self.string(dev, selector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID)) == LoopCam.deviceUID {
            let streams: [CMIOStreamID] = Self.array(dev, selector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams))
            // Direction 1 = input to the device, i.e. our sink.
            let sink = streams.first { Self.uint32(CMIOObjectID($0), selector: CMIOObjectPropertySelector(kCMIOStreamPropertyDirection)) == 1 }
            guard let sink = sink ?? streams.last else { continue }
            deviceID = dev
            sinkStreamID = sink
            return true
        }
        return false
    }

    /// True while some other app (Zoom, etc.) is streaming from LoopCam.
    func isCameraInUse() -> Bool {
        guard connect() else { return false }
        return Self.string(deviceID, selector: LoopCam.activePropertySelector) == "1"
    }

    func start() {
        guard !isStarted, connect() else { return }
        var unmanaged: Unmanaged<CMSimpleQueue>?
        let err = CMIOStreamCopyBufferQueue(sinkStreamID, { _, _, _ in }, nil, &unmanaged)
        guard err == noErr, let q = unmanaged?.takeRetainedValue() else {
            NSLog("LoopCam: CMIOStreamCopyBufferQueue failed \(err)")
            reset()
            return
        }
        queue = q
        let startErr = CMIODeviceStartStream(deviceID, sinkStreamID)
        guard startErr == noErr else {
            NSLog("LoopCam: CMIODeviceStartStream failed \(startErr)")
            reset()
            return
        }
        isStarted = true
    }

    func stop() {
        guard isStarted else { return }
        CMIODeviceStopStream(deviceID, sinkStreamID)
        queue = nil
        isStarted = false
    }

    /// If the extension was reinstalled, the cached IDs go stale; forget them.
    private func reset() {
        queue = nil
        deviceID = 0
        sinkStreamID = 0
        isStarted = false
    }

    func enqueue(_ pixelBuffer: CVPixelBuffer) {
        guard isStarted, let queue else { return }
        if CMSimpleQueueGetCount(queue) >= CMSimpleQueueGetCapacity(queue) { return }

        var fd: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &fd)
        guard let fd else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: LoopCam.fps),
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sbuf: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                 formatDescription: fd, sampleTiming: &timing, sampleBufferOut: &sbuf)
        guard let sbuf else { return }
        CMSimpleQueueEnqueue(queue, element: Unmanaged.passRetained(sbuf).toOpaque())
    }

    // MARK: CMIO property helpers

    private static func address(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector,
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func allDevices() -> [CMIOObjectID] {
        array(CMIOObjectID(kCMIOObjectSystemObject), selector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
    }

    private static func array<T: FixedWidthInteger>(_ obj: CMIOObjectID, selector: CMIOObjectPropertySelector) -> [T] {
        var addr = address(selector)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(obj, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var items = [T](repeating: 0, count: Int(size) / MemoryLayout<T>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(obj, &addr, 0, nil, size, &used, &items) == noErr else { return [] }
        return items
    }

    private static func uint32(_ obj: CMIOObjectID, selector: CMIOObjectPropertySelector) -> UInt32? {
        var addr = address(selector)
        var value: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(obj, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr else { return nil }
        return value
    }

    private static func string(_ obj: CMIOObjectID, selector: CMIOObjectPropertySelector) -> String? {
        var addr = address(selector)
        guard CMIOObjectHasProperty(obj, &addr) else { return nil }
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let err = CMIOObjectGetPropertyData(obj, &addr, 0, nil, UInt32(MemoryLayout<Unmanaged<CFString>?>.size), &used, &value)
        guard err == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
