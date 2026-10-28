import AVFoundation
import Foundation

/// Streams processed audio from ffmpeg (as raw float PCM) into an AVAudioEngine while it plays.
/// This is the "processed" listening mode: the same ffmpeg filter chain that Save uses,
/// applied on the fly from the current playhead.
final class LivePreview: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    private let lock = NSLock()

    private var process: Process?
    private var generation = 0
    private var scheduledFrames: Int64 = 0
    private var pendingBuffers = 0
    private var streamEnded = false
    private var running = false

    /// Called on the main thread when all scheduled audio has played and the stream has ended.
    var onFinished: (() -> Void)?

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    /// Seconds of processed audio played since start(), or nil when not running.
    var elapsed: Double? {
        guard isRunning, let nt = node.lastRenderTime, let pt = node.playerTime(forNodeTime: nt) else { return nil }
        return max(0, Double(pt.sampleTime) / pt.sampleRate)
    }

    private var aheadSeconds: Double {
        lock.lock(); let frames = scheduledFrames; lock.unlock()
        return Double(frames) / 48000 - (elapsed ?? 0)
    }

    func stop() {
        lock.lock()
        generation += 1
        running = false
        let p = process
        process = nil
        scheduledFrames = 0
        pendingBuffers = 0
        streamEnded = false
        lock.unlock()
        node.stop()
        if let p, p.isRunning { p.terminate() }
    }

    /// Starts ffmpeg with `args` (must output f32le, 2 ch, 48 kHz on stdout) and begins playback
    /// once the first chunk has arrived, so video and audio can be started together.
    func start(ffmpeg: String, args: [String]) async throws {
        stop()
        if !engine.isRunning { try engine.start() }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        try p.run()

        let gen: Int = lock.withLock {
            generation += 1
            process = p
            return generation
        }

        let fh = out.fileHandleForReading
        let first: Data = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { cont.resume(returning: fh.availableData) }
        }
        guard isCurrent(gen) else { return }
        guard !first.isEmpty else {
            p.terminate()
            throw ToolError.failed(String(localized: "Couldn't play the cleaned-up sound."))
        }

        var leftover = Data()
        schedule(first, leftover: &leftover, gen: gen)
        node.play()
        lock.withLock { running = true }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var leftover = leftover
            while let self, self.isCurrent(gen) {
                while self.isCurrent(gen) && self.aheadSeconds > 20 { Thread.sleep(forTimeInterval: 0.1) }
                let chunk = fh.availableData
                if chunk.isEmpty { break }
                self.schedule(chunk, leftover: &leftover, gen: gen)
            }
            guard let self, self.isCurrent(gen) else { return }
            self.lock.lock()
            self.streamEnded = true
            let done = self.pendingBuffers == 0
            self.lock.unlock()
            if done { DispatchQueue.main.async { self.onFinished?() } }
        }
    }

    private func isCurrent(_ gen: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return gen == generation }

    private func schedule(_ chunk: Data, leftover: inout Data, gen: Int) {
        var data = leftover + chunk
        let frameBytes = 8   // 2 channels × Float32
        let frames = data.count / frameBytes
        let usable = frames * frameBytes
        leftover = data.subdata(in: usable..<data.count)
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        buf.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeMutableBytes { raw in
            let src = raw.bindMemory(to: Float.self)
            let l = buf.floatChannelData![0], r = buf.floatChannelData![1]
            for i in 0..<frames { l[i] = src[i * 2]; r[i] = src[i * 2 + 1] }
        }
        lock.lock()
        guard gen == generation else { lock.unlock(); return }
        scheduledFrames += Int64(frames)
        pendingBuffers += 1
        lock.unlock()
        node.scheduleBuffer(buf, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self, self.isCurrent(gen) else { return }
            self.lock.lock()
            self.pendingBuffers -= 1
            let done = self.streamEnded && self.pendingBuffers == 0
            self.lock.unlock()
            if done { DispatchQueue.main.async { self.onFinished?() } }
        }
    }
}
