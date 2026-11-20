import AVFoundation

/// Turns a raw recording into a seamless "ping-pong" loop: the clip plays
/// forward, then backward, so the last frame flows straight into the first.
enum LoopMaker {
    static func makePingPong(from source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw LoopError.emptyRecording }

        // Decode every frame. 420v at 720p is ~1.4 MB/frame, so a 10 s clip is ~400 MB briefly.
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        reader.add(output)
        reader.startReading()
        var frames: [CVPixelBuffer] = []
        var times: [CMTime] = []
        while let sbuf = output.copyNextSampleBuffer() {
            if let pb = CMSampleBufferGetImageBuffer(sbuf) {
                frames.append(pb)
                times.append(CMSampleBufferGetPresentationTimeStamp(sbuf))
            }
        }
        guard reader.status == .completed, frames.count > 2 else { throw LoopError.emptyRecording }

        // Forward, then backward without repeating the two end frames. Keep each
        // frame's real timing (webcams often deliver fewer than 30 fps), mirroring
        // it for the backward half so motion plays at true speed both ways.
        let n = frames.count
        let t0 = times[0], tEnd = times[n - 1]
        let forwardSpan = CMTimeSubtract(tEnd, t0)
        var sequence: [(CVPixelBuffer, CMTime)] = (0..<n).map { (frames[$0], CMTimeSubtract(times[$0], t0)) }
        for j in stride(from: n - 2, through: 1, by: -1) {
            sequence.append((frames[j], CMTimeAdd(forwardSpan, CMTimeSubtract(tEnd, times[j]))))
        }

        let tmp = destination.deletingLastPathComponent().appendingPathComponent("loop-building.mp4")
        try? FileManager.default.removeItem(at: tmp)
        let writer = try AVAssetWriter(outputURL: tmp, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings())
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        guard writer.startWriting() else { throw LoopError.writerFailed(writer.error?.localizedDescription ?? "start") }
        writer.startSession(atSourceTime: .zero)

        for (pb, time) in sequence {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            adaptor.append(pb, withPresentationTime: time)
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw LoopError.writerFailed(writer.error?.localizedDescription ?? "finish") }

        _ = try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmp, to: destination)
    }
}
