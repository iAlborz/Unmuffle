import Foundation

struct AudioSettings: Equatable {
    static let eqBands: [Double] = [60, 150, 400, 1000, 2500, 5000, 8000, 12000]

    var volumeEnabled = true
    var eqEnabled = true
    var mute = false

    var highpass: Double = 80        // Hz, 0 = off
    var lowpass: Double = 0          // Hz, 0 = off
    var eqGains: [Double] = Array(repeating: 0, count: 8)

    var denoise = true
    var denoiseAuto = true
    var denoiseAmount: Double = 12   // dB of reduction
    var noiseFloor: Double = -50     // dB

    var gate = false
    var gateThreshold: Double = -45  // dB

    var compressor = true
    var compThreshold: Double = -18  // dB
    var compRatio: Double = 3

    var gain: Double = 0             // dB
    var loudnorm = false

    private func lin(_ db: Double) -> String { String(format: "%.6f", pow(10, db / 20)) }
    private func n(_ v: Double) -> String { String(format: "%.2f", v) }

    /// ffmpeg audio filter chain, in processing order.
    func filterString() -> String {
        if mute { return "volume=0" }
        var f: [String] = []
        if eqEnabled && highpass > 0 { f.append("highpass=f=\(Int(highpass))") }
        if eqEnabled && lowpass > 0 { f.append("lowpass=f=\(Int(lowpass))") }
        if denoise {
            let nr = min(97, max(0.01, denoiseAmount))
            let nf = min(-20, max(-80, noiseFloor))
            f.append("afftdn=nr=\(n(nr)):nf=\(n(nf)):tn=1")
        }
        if gate {
            f.append("agate=threshold=\(lin(gateThreshold)):ratio=4:attack=10:release=150:knee=4")
        }
        for (i, g) in eqGains.enumerated() where eqEnabled && abs(g) >= 0.1 {
            f.append("equalizer=f=\(Int(Self.eqBands[i])):t=o:w=1:g=\(n(g))")
        }
        if compressor {
            f.append("acompressor=threshold=\(lin(compThreshold)):ratio=\(n(compRatio)):attack=15:release=200")
        }
        if volumeEnabled {
            // Auto (loudness normalization) replaces the manual gain; they are not combined.
            if loudnorm { f.append("loudnorm=I=-16:TP=-1.5:LRA=11") }
            else if abs(gain) >= 0.1 { f.append("volume=\(n(gain))dB") }
        }
        return f.isEmpty ? "anull" : f.joined(separator: ",")
    }

    // MARK: Presets
    static let flatEQ: [Double] = Array(repeating: 0, count: 8)
    static let clarityEQ: [Double] = [-6, -2, 0, 1, 3, 2.5, 1.5, 0]
    static let warmEQ: [Double] = [-3, 2, 2, 0, -1, 0, 0, -2]
    static let podcastEQ: [Double] = [-8, 0, -1, 1, 2, 3, 1, -1]

    static let eqPresets: [(name: String, gains: [Double])] = [
        ("Flat", flatEQ), ("Voice Clarity", clarityEQ), ("Warm", warmEQ), ("Podcast", podcastEQ),
    ]

    /// Name of the preset that matches the current gains, or "Manual".
    var eqPresetName: String {
        Self.eqPresets.first { preset in
            zip(preset.gains, eqGains).allSatisfy { abs($0 - $1) < 0.01 }
        }?.name ?? "Manual"
    }
}
