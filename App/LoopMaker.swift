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
        while let sbuf = output.copyNextSampleBuffer() {
            if let pb = CMSampleBufferGetImageBuffer(sbuf) { frames.append(pb) }
        }
        guard reader.status == .completed, frames.count > 2 else { throw LoopError.emptyRecording }

        // Forward, then backward without repeating the two end frames.
        let sequence = frames + frames[1..<(frames.count - 1)].reversed()

        let tmp = destination.deletingLastPathComponent().appendingPathComponent("loop-building.mp4")
        try? FileManager.default.removeItem(at: tmp)
        let writer = try AVAssetWriter(outputURL: tmp, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings())
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        guard writer.startWriting() else { throw LoopError.writerFailed(writer.error?.localizedDescription ?? "start") }
        writer.startSession(atSourceTime: .zero)

        for (i, pb) in sequence.enumerated() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: LoopCam.fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw LoopError.writerFailed(writer.error?.localizedDescription ?? "finish") }

        _ = try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmp, to: destination)
    }
}
