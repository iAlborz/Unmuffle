import Foundation

enum ToolError: LocalizedError {
    case ffmpegMissing
    case failed(String)
    case noAudio

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing: return "ffmpeg was not found. Install it in Terminal with:  brew install ffmpeg"
        case .failed(let s): return s
        case .noAudio: return "This video has no audio track."
        }
    }
}

enum Tools {
    static func find(_ name: String) -> String? {
        var candidates: [String] = []
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent(name).path) }
        candidates += ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/opt/local/bin/\(name)"]
        if let p = ProcessInfo.processInfo.environment["PATH"] {
            for d in p.split(separator: ":") { candidates.append("\(d)/\(name)") }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static var ffmpeg: String? { find("ffmpeg") }
    static var ffprobe: String? { find("ffprobe") }
}

struct ProcessResult {
    let status: Int32
    let stdout: Data
    let stderr: String
}

/// Runs one external process. Streams lines from stdout/stderr and collects all output.
final class FFProcess: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        if process.isRunning { process.terminate() }
    }

    var wasCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func run(_ path: String, _ args: [String],
             onStdoutLine: ((String) -> Void)? = nil,
             onStderrLine: ((String) -> Void)? = nil) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let r = try self.runSync(path, args, onStdoutLine: onStdoutLine, onStderrLine: onStderrLine)
                    cont.resume(returning: r)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func runSync(_ path: String, _ args: [String],
                         onStdoutLine: ((String) -> Void)?,
                         onStderrLine: ((String) -> Void)?) throws -> ProcessResult {
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        let group = DispatchGroup()
        var outData = Data(), errData = Data()
        group.enter()
        pump(out.fileHandleForReading, onLine: onStdoutLine) { outData = $0; group.leave() }
        group.enter()
        pump(err.fileHandleForReading, onLine: onStderrLine) { errData = $0; group.leave() }

        do {
            try process.run()
        } catch {
            try? out.fileHandleForWriting.close()
            try? err.fileHandleForWriting.close()
            throw ToolError.failed("Could not start \(path): \(error.localizedDescription)")
        }
        process.waitUntilExit()
        group.wait()
        return ProcessResult(status: process.terminationStatus, stdout: outData,
                             stderr: String(decoding: errData, as: UTF8.self))
    }

    private func pump(_ fh: FileHandle, onLine: ((String) -> Void)?, done: @escaping (Data) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var all = Data()
            var lineBuf = Data()
            while true {
                let chunk = fh.availableData
                if chunk.isEmpty { break }
                all.append(chunk)
                guard let onLine else { continue }
                lineBuf.append(chunk)
                while let idx = lineBuf.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                    let line = String(decoding: lineBuf[lineBuf.startIndex..<idx], as: UTF8.self)
                    lineBuf.removeSubrange(lineBuf.startIndex...idx)
                    if !line.isEmpty { onLine(line) }
                }
            }
            done(all)
        }
    }
}

struct MediaInfo {
    var duration: Double = 0
    var videoCodec = ""
    var width = 0
    var height = 0
    var fps: Double = 0
    var videoBitrate = 0        // bits per second
    var pixFmt: String?
    var hasAudio = false
    var audioCodec = ""
    var audioBitrate = 0
    var sampleRate = 48000
    var channels = 2
    var formatBitrate = 0

    static func probe(_ url: URL) async throws -> MediaInfo {
        guard let fp = Tools.ffprobe else { throw ToolError.ffmpegMissing }
        let r = try await FFProcess().run(fp, ["-v", "error", "-print_format", "json",
                                               "-show_format", "-show_streams", url.path])
        guard r.status == 0,
              let json = try? JSONSerialization.jsonObject(with: r.stdout) as? [String: Any] else {
            throw ToolError.failed("Could not read this file.\n\(r.stderr.suffix(500))")
        }
        var info = MediaInfo()
        let fmt = json["format"] as? [String: Any] ?? [:]
        info.duration = Double(fmt["duration"] as? String ?? "") ?? 0
        info.formatBitrate = Int(fmt["bit_rate"] as? String ?? "") ?? 0

        var sawVideo = false
        for s in json["streams"] as? [[String: Any]] ?? [] {
            let type = s["codec_type"] as? String ?? ""
            let disposition = s["disposition"] as? [String: Any] ?? [:]
            let attachedPic = (disposition["attached_pic"] as? Int ?? 0) == 1
            if type == "video" && !sawVideo && !attachedPic {
                sawVideo = true
                info.videoCodec = s["codec_name"] as? String ?? ""
                info.width = s["width"] as? Int ?? 0
                info.height = s["height"] as? Int ?? 0
                info.pixFmt = s["pix_fmt"] as? String
                info.videoBitrate = Int(s["bit_rate"] as? String ?? "") ?? 0
                if let fr = s["r_frame_rate"] as? String {
                    let parts = fr.split(separator: "/").compactMap { Double($0) }
                    if parts.count == 2, parts[1] > 0 { info.fps = parts[0] / parts[1] }
                }
                if info.duration == 0 { info.duration = Double(s["duration"] as? String ?? "") ?? 0 }
            } else if type == "audio" && !info.hasAudio {
                info.hasAudio = true
                info.audioCodec = s["codec_name"] as? String ?? ""
                info.audioBitrate = Int(s["bit_rate"] as? String ?? "") ?? 0
                info.sampleRate = Int(s["sample_rate"] as? String ?? "") ?? 48000
                info.channels = s["channels"] as? Int ?? 2
            }
        }
        if info.videoBitrate == 0 && info.formatBitrate > 0 {
            info.videoBitrate = max(0, info.formatBitrate - info.audioBitrate)
        }
        return info
    }
}

func fmt(_ v: Double) -> String { String(format: "%.3f", v) }

func timeString(_ t: Double) -> String {
    let t = max(0, t)
    let m = Int(t) / 60
    let s = Int(t) % 60
    let tenths = Int((t - floor(t)) * 10)
    return String(format: "%02d:%02d.%d", m, s, tenths)
}
