import Foundation
import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

struct SilenceSegment: Identifiable, Equatable {
    let id: UUID
    var start: Double
    var end: Double
    var remove: Bool
}

@MainActor
final class ProjectModel: ObservableObject {
    @Published var url: URL?
    @Published var info = MediaInfo()
    @Published var peaks: [Float] = []       // one value per analysis window, 0..1
    @Published var rmsDB: [Float] = []       // one value per analysis window, dBFS
    let window: Double = 0.05                // seconds per analysis window

    @Published var trimStart: Double = 0 { didSet { scheduleLiveRestart() } }
    @Published var trimEnd: Double = 0 { didSet { scheduleLiveRestart() } }
    @Published var settings = AudioSettings() {
        didSet {
            scheduleLiveRestart()
            scheduleProcessedWaveform()
            if settings.denoiseAuto && !oldValue.denoiseAuto { autoDenoiseIfNeeded() }
        }
    }
    /// Peaks of the audio after the current filter chain, for the timeline. Empty when neutral or not yet computed.
    @Published var processedPeaks: [Float] = []
    private var processedWaveTask: Task<Void, Never>?
    private var processedWaveJob: FFProcess?

    @Published var removeSilence = false { didSet { scheduleLiveRestart() } }
    @Published var silenceThreshold: Double = -40 { didSet { detectSilences() } }
    @Published var silenceMinDuration: Double = 0.7 { didSet { detectSilences() } }
    /// Margin left on each side of a cut so words are not clipped. Fixed; not exposed in the UI.
    let silencePadding: Double = 0.12
    @Published var silences: [SilenceSegment] = [] { didSet { scheduleLiveRestart(); autoDenoiseIfNeeded() } }

    @Published var simpleMode: Bool = UserDefaults.standard.object(forKey: "simpleMode") as? Bool ?? true {
        didSet { UserDefaults.standard.set(simpleMode, forKey: "simpleMode") }
    }
    @Published var simpleChoices = SimpleChoices()
    /// Start playing as soon as a video is opened.
    @Published var autoplay: Bool = UserDefaults.standard.object(forKey: "autoplay") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoplay, forKey: "autoplay") }
    }

    /// Applies the Simple-mode choices to the effect chain and switches the player to the result.
    /// With `andPlay`, also starts playing.
    func applySimpleChoices(andPlay: Bool = true) {
        settings = simpleChoices.settings(noiseFloor: measureNoiseFloor(), speechLevel: detectedSpeechLevel)
        removeSilence = false
        setSource(processed: true)
        if andPlay && !isPlaying { play() }
    }

    @Published var losslessTrim = false

    @Published var isBusy = false
    @Published var busyLabel = ""
    @Published var progress: Double = -1
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var lastOutput: URL?

    @Published var detectedNoiseFloor: Double?
    @Published var detectedSpeechLevel: Double?

    // Playback
    let player = AVPlayer()
    let live = LivePreview()
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    @Published var showingProcessed = false
    @Published var volume: Float = 1 {
        didSet { player.volume = volume; live.volume = volume }
    }
    private var liveKeep: [(Double, Double)] = []
    private var restartTask: Task<Void, Never>?
    private var seekInFlight = false
    private var timeObserver: Any?
    private var currentJob: FFProcess?

    var duration: Double { info.duration }
    var toolsAvailable: Bool { Tools.ffmpeg != nil && Tools.ffprobe != nil }

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.04, preferredTimescale: 600), queue: .main
        ) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(playerTime: t.seconds) }
        }
        live.onFinished = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pause()
                self.currentTime = self.trimEnd
                self.player.seek(to: CMTime(seconds: self.trimEnd, preferredTimescale: 600),
                                 toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
    }

    private func tick(playerTime: Double) {
        if showingProcessed {
            guard isPlaying, live.isRunning, let e = live.elapsed else { return }
            let expected = originalTime(fromProcessed: e, segments: liveKeep)
            currentTime = expected
            // The video follows the audio clock. Re-align when it drifts or when a cut is skipped.
            if !seekInFlight && abs(playerTime - expected) > 0.12 {
                seekInFlight = true
                player.seek(to: CMTime(seconds: expected, preferredTimescale: 600),
                            toleranceBefore: CMTime(seconds: 0.03, preferredTimescale: 600),
                            toleranceAfter: CMTime(seconds: 0.03, preferredTimescale: 600)) { [weak self] _ in
                    MainActor.assumeIsolated { self?.seekInFlight = false }
                }
            }
        } else {
            currentTime = playerTime
            isPlaying = player.rate != 0
            if isPlaying && trimEnd > 0 && playerTime >= trimEnd { player.pause(); isPlaying = false; return }
            // Skip removed quiet parts in Original mode too, so the cuts can be previewed.
            if isPlaying && !seekInFlight,
               let cut = activeCuts.first(where: { $0.start <= playerTime && playerTime < $0.end - 0.05 }) {
                let target = min(cut.end, trimEnd)
                seekInFlight = true
                player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 0.05, preferredTimescale: 600)) { [weak self] _ in
                    MainActor.assumeIsolated { self?.seekInFlight = false }
                }
            }
        }
    }

    // MARK: Loading

    func openPanel() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url {
            Task { await load(u) }
        }
    }

    func reset() {
        restartTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        url = nil
        info = MediaInfo()
        peaks = []; rmsDB = []; processedPeaks = []
        processedWaveTask?.cancel(); processedWaveJob?.cancel()
        silences = []
        trimStart = 0; trimEnd = 0
        currentTime = 0
        lastOutput = nil
        statusMessage = ""
        detectedNoiseFloor = nil; detectedSpeechLevel = nil
        live.stop()
        isPlaying = false
    }

    func load(_ newURL: URL) async {
        guard toolsAvailable else { errorMessage = ToolError.ffmpegMissing.errorDescription; return }
        guard !isBusy else { return }
        reset()
        isBusy = true; busyLabel = String(localized: "Reading video…"); progress = -1
        do {
            let i = try await MediaInfo.probe(newURL)
            guard i.hasAudio else { throw ToolError.noAudio }
            info = i
            url = newURL
            trimStart = 0
            trimEnd = i.duration
            player.replaceCurrentItem(with: AVPlayerItem(url: newURL))
            player.isMuted = showingProcessed
            player.volume = volume
            busyLabel = String(localized: "Analyzing audio…")
            try await analyzeAudio()
        } catch {
            errorMessage = error.localizedDescription
            reset()
        }
        isBusy = false
        guard url != nil else { return }
        // Simple mode: the cards apply to every new video, so Export works without touching them.
        if simpleMode { applySimpleChoices(andPlay: autoplay) }
        else if autoplay { play() }
    }

    // MARK: Analysis

    private func analyzeAudio() async throws {
        guard let u = url, let ff = Tools.ffmpeg else { return }
        let job = FFProcess()
        currentJob = job
        let r = try await job.run(ff, ["-v", "error", "-nostdin", "-i", u.path, "-map", "0:a:0",
                                       "-ac", "1", "-ar", "8000", "-f", "s16le", "-"])
        currentJob = nil
        guard r.status == 0 else { throw ToolError.failed("Audio analysis failed:\n\(r.stderr.suffix(600))") }
        let data = r.stdout
        let windowSamples = Int(8000 * window)
        let (p, rms) = await Task.detached(priority: .userInitiated) {
            Self.computeWaveform(data, windowSamples: windowSamples)
        }.value
        peaks = p
        rmsDB = rms
        processedPeaks = []
        scheduleProcessedWaveform()
        let sorted = rms.filter { $0 > -95 }.sorted()
        if sorted.count > 20 {
            detectedNoiseFloor = Double(sorted[Int(Double(sorted.count) * 0.10)])
            detectedSpeechLevel = Double(sorted[Int(Double(sorted.count) * 0.90)])
        }
        detectSilences()
        autoDenoiseIfNeeded()
    }

    nonisolated static func computeWaveform(_ data: Data, windowSamples: Int) -> ([Float], [Float]) {
        let count = data.count / 2
        var samples = [Int16](repeating: 0, count: count)
        _ = samples.withUnsafeMutableBytes { data.copyBytes(to: $0, count: count * 2) }
        var peaks: [Float] = [], rms: [Float] = []
        peaks.reserveCapacity(count / max(windowSamples, 1) + 1)
        rms.reserveCapacity(count / max(windowSamples, 1) + 1)
        var i = 0
        while i < count {
            let end = min(i + windowSamples, count)
            var peak: Float = 0
            var sum: Double = 0
            for j in i..<end {
                let v = Float(samples[j]) / 32768
                peak = max(peak, abs(v))
                sum += Double(v * v)
            }
            let r = sqrt(sum / Double(max(end - i, 1)))
            rms.append(r > 0 ? Float(20 * log10(r)) : -100)
            peaks.append(peak)
            i = end
        }
        return (peaks, rms)
    }

    /// Uses the measured noise floor and speech level to set noise reduction and silence threshold.
    /// Recomputes the processed waveform a moment after the last settings change.
    private func scheduleProcessedWaveform() {
        processedWaveTask?.cancel()
        processedWaveJob?.cancel()
        guard let u = url, let ff = Tools.ffmpeg, !peaks.isEmpty else { return }
        let af = settings.filterString()
        if af == "anull" { processedPeaks = []; return }
        let windowSamples = Int(8000 * window)
        processedWaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self else { return }
            let job = FFProcess()
            self.processedWaveJob = job
            guard let r = try? await job.run(ff, ["-v", "error", "-nostdin", "-i", u.path, "-map", "0:a:0",
                                                  "-af", af, "-ac", "1", "-ar", "8000", "-f", "s16le", "-"]),
                  r.status == 0, !job.wasCancelled, !Task.isCancelled else { return }
            let data = r.stdout
            let (p, _) = await Task.detached(priority: .utility) {
                Self.computeWaveform(data, windowSamples: windowSamples)
            }.value
            guard !Task.isCancelled, self.settings.filterString() == af else { return }
            self.processedPeaks = p
        }
    }

    /// Measured noise floor: the median level of the quiet parts found on the timeline,
    /// or the quietest 10% of the audio when no quiet parts were found.
    func measureNoiseFloor() -> Double? {
        guard !rmsDB.isEmpty else { return nil }
        var quiet: [Float] = []
        for seg in silences {
            let a = max(0, Int(seg.start / window)), b = min(rmsDB.count, Int(seg.end / window))
            if b > a { quiet.append(contentsOf: rmsDB[a..<b]) }
        }
        quiet = quiet.filter { $0 > -95 }.sorted()
        if quiet.count >= 20 { return Double(quiet[quiet.count / 2]) }
        return detectedNoiseFloor
    }

    /// Sets the denoise floor and amount from the measured noise. In manual mode (the button)
    /// it also sets the quiet-part threshold.
    func applyDetectedNoise(adjustSilenceThreshold: Bool = true) {
        guard let sp = detectedSpeechLevel, let nf = measureNoiseFloor() else { return }
        detectedNoiseFloor = nf
        var s = settings
        s.noiseFloor = min(-20, max(-80, nf + 2))
        s.denoiseAmount = min(30, max(6, (sp - nf) * 0.4))
        if s != settings { settings = s }
        if adjustSilenceThreshold { silenceThreshold = min(sp - 6, nf + 8) }
    }

    /// Auto denoise: follow the measured noise whenever the analysis or the quiet parts change.
    private func autoDenoiseIfNeeded() {
        guard settings.denoiseAuto else { return }
        applyDetectedNoise(adjustSilenceThreshold: false)
    }

    func detectSilences() {
        guard !rmsDB.isEmpty else { silences = []; return }
        let disabled = silences.filter { !$0.remove }
        var out: [SilenceSegment] = []
        var runStart: Int?
        func close(_ s: Int, _ e: Int) {
            let start = Double(s) * window + silencePadding
            let end = Double(e) * window - silencePadding
            guard end - start >= silenceMinDuration else { return }
            let wasDisabled = disabled.contains { $0.start < end && $0.end > start }
            out.append(SilenceSegment(id: UUID(), start: start, end: end, remove: !wasDisabled))
        }
        for (i, v) in rmsDB.enumerated() {
            if Double(v) < silenceThreshold {
                if runStart == nil { runStart = i }
            } else if let s = runStart {
                close(s, i)
                runStart = nil
            }
        }
        if let s = runStart { close(s, rmsDB.count) }
        silences = out
    }

    func toggleSilence(at t: Double) {
        if let i = silences.firstIndex(where: { $0.start <= t && t <= $0.end }) {
            silences[i].remove.toggle()
        }
    }

    func setAllSilences(remove: Bool) {
        for i in silences.indices { silences[i].remove = remove }
    }

    // MARK: Segments

    var activeCuts: [SilenceSegment] {
        guard removeSilence else { return [] }
        return silences.filter { $0.remove && $0.end > trimStart && $0.start < trimEnd }
    }

    func keepSegments() -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        var t = trimStart
        for c in activeCuts.sorted(by: { $0.start < $1.start }) {
            let cs = max(c.start, t), ce = min(c.end, trimEnd)
            if cs > t + 0.02 { out.append((t, cs)) }
            t = max(t, ce)
        }
        if trimEnd > t + 0.02 { out.append((t, trimEnd)) }
        return out
    }

    var needsCut: Bool {
        let k = keepSegments()
        return !(k.count == 1 && k[0].0 <= 0.001 && k[0].1 >= duration - 0.001)
    }

    var outputDuration: Double { keepSegments().reduce(0) { $0 + $1.1 - $1.0 } }
    var removedSilenceDuration: Double { activeCuts.reduce(0) { $0 + min($1.end, trimEnd) - max($1.start, trimStart) } }

    /// True when the saved file will contain the original video stream byte for byte.
    var videoWillBeCopied: Bool { !needsCut || (losslessTrim && keepSegments().count == 1) }

    func originalTime(fromProcessed p: Double, segments: [(Double, Double)]) -> Double {
        var acc = 0.0
        for (s, e) in segments {
            let d = e - s
            if p <= acc + d { return s + (p - acc) }
            acc += d
        }
        return segments.last?.1 ?? p
    }

    func processedTime(fromOriginal o: Double, segments: [(Double, Double)]) -> Double {
        var acc = 0.0
        for (s, e) in segments {
            if o < s { return acc }
            if o <= e { return acc + (o - s) }
            acc += e - s
        }
        return acc
    }

    // MARK: Playback

    func seek(to t: Double) {
        let clamped = min(max(0, t), duration)
        currentTime = clamped
        if showingProcessed && isPlaying {
            live.stop()
            player.pause()
            scheduleLiveRestart(force: true)
        }
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard url != nil else { return }
        if currentTime >= trimEnd - 0.05 || currentTime < trimStart { currentTime = trimStart }
        isPlaying = true
        if showingProcessed {
            Task { await startLive(at: currentTime) }
        } else {
            player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
        }
    }

    func pause() {
        restartTask?.cancel()
        live.stop()
        player.pause()
        isPlaying = false
    }

    func setSource(processed: Bool) {
        guard processed != showingProcessed else { return }
        let t = currentTime
        let wasPlaying = isPlaying
        pause()
        showingProcessed = processed
        player.isMuted = processed
        currentTime = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        if wasPlaying { play() }
    }

    /// Restarts the processed stream a moment after the last edit, so the sound follows the settings.
    private func scheduleLiveRestart(force: Bool = false) {
        guard showingProcessed, isPlaying else { return }
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self, self.showingProcessed, self.isPlaying else { return }
            await self.startLive(at: self.currentTime)
        }
    }

    private func startLive(at t: Double) async {
        guard url != nil, let ff = Tools.ffmpeg else { return }
        let keep = keepSegments().filter { $0.1 > t + 0.01 }.map { (max($0.0, t), $0.1) }
        guard let first = keep.first else { pause(); return }
        liveKeep = keep
        player.pause()
        player.isMuted = true
        currentTime = first.0
        await player.seek(to: CMTime(seconds: first.0, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        guard isPlaying, showingProcessed else { return }
        do {
            try await live.start(ffmpeg: ff, args: liveArgs(start: first.0, keep: keep))
        } catch {
            errorMessage = error.localizedDescription
            pause()
            return
        }
        guard isPlaying, showingProcessed else { live.stop(); return }
        player.play()
    }

    /// ffmpeg arguments that stream processed audio from `start`, skipping removed parts.
    private func liveArgs(start: Double, keep: [(Double, Double)]) -> [String] {
        guard let u = url else { return [] }
        var args = ["-v", "error", "-nostdin", "-ss", fmt(start), "-i", u.path]
        let af = settings.filterString()
        let wholeTail = keep.count == 1 && keep[0].1 >= duration - 0.001
        if wholeTail {
            args += ["-map", "0:a:0", "-af", af]
        } else {
            var fc = ""
            for (i, seg) in keep.enumerated() {
                fc += "[0:a:0]atrim=start=\(fmt(seg.0 - start)):end=\(fmt(seg.1 - start)),asetpts=PTS-STARTPTS[a\(i)];"
            }
            fc += keep.indices.map { "[a\($0)]" }.joined() + "concat=n=\(keep.count):v=0:a=1[ac];[ac]\(af)[aout]"
            args += ["-filter_complex", fc, "-map", "[aout]"]
        }
        args += ["-f", "f32le", "-ac", "2", "-ar", "48000", "-"]
        return args
    }

    // MARK: Rendering

    /// Re-encodes with Apple's hardware encoder at the source bitrate. The bundled ffmpeg is
    /// LGPL-only, so the GPL software encoders (x264, x265) are not available.
    private var finalVideoArgs: [String] {
        let hevc = info.videoCodec == "hevc"
        let br = info.videoBitrate > 0 ? info.videoBitrate : 8_000_000
        var a = ["-c:v", hevc ? "hevc_videotoolbox" : "h264_videotoolbox", "-b:v", "\(br)", "-allow_sw", "1"]
        if info.pixFmt == "yuv420p" { a += ["-pix_fmt", "yuv420p"] }
        if hevc { a += ["-tag:v", "hvc1"] }
        return a
    }

    func buildArgs(input: URL, output: URL) -> [String] {
        var args = ["-y", "-hide_banner", "-nostdin", "-loglevel", "error", "-progress", "pipe:1", "-nostats"]
        let af = settings.filterString()
        let keep = keepSegments()
        let cut = needsCut
        let losslessKeyframe = cut && losslessTrim && keep.count == 1
        let transcode = cut && !losslessKeyframe

        if losslessKeyframe, let seg = keep.first {
            args += ["-ss", fmt(seg.0), "-to", fmt(seg.1)]
        }
        args += ["-i", input.path]

        if !transcode {
            // Stream copy: the video bytes are untouched.
            args += ["-map", "0:v:0", "-map", "0:a:0", "-c:v", "copy", "-af", af]
        } else {
            var fc = ""
            for (i, seg) in keep.enumerated() {
                fc += "[0:v:0]trim=start=\(fmt(seg.0)):end=\(fmt(seg.1)),setpts=PTS-STARTPTS[v\(i)];"
                fc += "[0:a:0]atrim=start=\(fmt(seg.0)):end=\(fmt(seg.1)),asetpts=PTS-STARTPTS[a\(i)];"
            }
            fc += keep.indices.map { "[v\($0)][a\($0)]" }.joined()
            fc += "concat=n=\(keep.count):v=1:a=1[vc][ac];"
            fc += "[ac]\(af)[aout];"
            fc += "[vc]copy[vout]"
            args += ["-filter_complex", fc, "-map", "[vout]", "-map", "[aout]"]
            args += finalVideoArgs
        }

        let ab = info.audioBitrate > 0 ? max(96_000, info.audioBitrate) : 192_000
        args += ["-c:a", "aac", "-b:a", "\(ab)", "-ar", "\(info.sampleRate)"]
        if ["mp4", "mov", "m4v"].contains(output.pathExtension.lowercased()) {
            args += ["-movflags", "+faststart"]
        }
        args.append(output.path)
        return args
    }

    var commandPreview: String {
        guard let u = url else { return "" }
        let out = Self.nextOutputURL(for: u)
        return "ffmpeg " + buildArgs(input: u, output: out)
            .map { $0.contains(" ") || $0.contains("[") || $0.contains(";") ? "'\($0)'" : $0 }
            .joined(separator: " ")
    }

    nonisolated static func nextOutputURL(for input: URL) -> URL {
        let dir = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let ext = input.pathExtension
        var n = 1
        while true {
            let u = dir.appendingPathComponent("\(base)-\(n).\(ext)")
            if !FileManager.default.fileExists(atPath: u.path) { return u }
            n += 1
        }
    }

    func export() async {
        guard let u = url, !isBusy else { return }
        guard !keepSegments().isEmpty else { errorMessage = "Nothing is left to save. Check the trim range."; return }
        // Ask where to save, suggesting name-1 next to the original. The sandbox only allows
        // writing where the user chooses.
        let suggested = Self.nextOutputURL(for: u)
        let panel = NSSavePanel()
        panel.directoryURL = suggested.deletingLastPathComponent()
        panel.nameFieldStringValue = suggested.lastPathComponent
        if let type = UTType(filenameExtension: u.pathExtension) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let out = panel.url else { return }
        let args = buildArgs(input: u, output: out)
        let copied = videoWillBeCopied
        pause()
        await runFFmpeg(args: args, label: String(localized: "Saving \(out.lastPathComponent)…"), totalDuration: outputDuration) { [self] in
            lastOutput = out
            statusMessage = copied
                ? String(localized: "Saved \(out.lastPathComponent). Video stream copied unchanged.")
                : String(localized: "Saved \(out.lastPathComponent). Video re-encoded at the source bitrate because of cuts.")
        }
    }

    private func runFFmpeg(args: [String], label: String, totalDuration: Double, onSuccess: @MainActor () -> Void) async {
        guard let ff = Tools.ffmpeg else { errorMessage = ToolError.ffmpegMissing.errorDescription; return }
        isBusy = true; busyLabel = label; progress = 0
        let job = FFProcess()
        currentJob = job
        do {
            let r = try await job.run(ff, args, onStdoutLine: { line in
                guard line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms=") else { return }
                if let v = Double(line.split(separator: "=").last ?? "") {
                    let p = min(1, (v / 1_000_000) / max(totalDuration, 0.01))
                    Task { @MainActor in self.progress = p }
                }
            })
            if job.wasCancelled {
                statusMessage = String(localized: "Cancelled.")
                if let outPath = args.last { try? FileManager.default.removeItem(atPath: outPath) }
            } else if r.status == 0 {
                onSuccess()
            } else {
                errorMessage = "ffmpeg failed:\n" + String(r.stderr.suffix(1200))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        currentJob = nil
        isBusy = false
        progress = -1
    }

    func cancel() { currentJob?.cancel() }
}
