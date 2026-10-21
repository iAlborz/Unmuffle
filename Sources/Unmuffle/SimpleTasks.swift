import Foundation

/// Simple mode: three independent choices that combine into one effect chain.
enum SimpleAudio: String, CaseIterable, Identifiable {
    case normal = "Normal", enhance = "Enhance Audio", mute = "Mute Audio"
    var id: String { rawValue }
    var description: String {
        switch self {
        case .normal: return "Volume and dynamics are left as recorded."
        case .enhance: return "Evens out loud moments and brings the whole recording to a standard loudness."
        case .mute: return "Replaces the sound with silence. The video is kept exactly as it is."
        }
    }
}

enum SimpleVoice: String, CaseIterable, Identifiable {
    case normal = "Normal", boost = "Boost Voice", podcast = "Podcast"
    var id: String { rawValue }
    var description: String {
        switch self {
        case .normal: return "No tone changes."
        case .boost: return "Lifts the range where speech is clearest and removes low rumble, so the voice cuts through."
        case .podcast: return "A fuller spoken-word tone: warmer body, crisp consonants, tighter level control."
        }
    }
}

enum SimpleNoise: String, CaseIterable, Identifiable {
    case off = "Off", remove = "Remove Noise", aggressive = "Aggressively Remove"
    var id: String { rawValue }
    var description: String {
        switch self {
        case .off: return "Background noise is left alone."
        case .remove: return "Takes out hiss, hum, and room noise based on the quiet parts of the recording."
        case .aggressive: return "Removes much more noise and mutes the gaps between words. Can make the voice sound thinner."
        }
    }
}

struct SimpleChoices: Equatable {
    var audio: SimpleAudio = .enhance
    var voice: SimpleVoice = .normal
    var noise: SimpleNoise = .remove

    /// Builds the effect chain. `noiseFloor`/`speechLevel` come from the file analysis.
    func settings(noiseFloor: Double?, speechLevel: Double?) -> AudioSettings {
        var s = AudioSettings()
        s.eqGains = AudioSettings.flatEQ
        s.highpass = 0
        s.lowpass = 0
        s.gate = false

        switch audio {
        case .normal: s.volumeEnabled = false; s.compressor = false; s.mute = false
        case .enhance: s.volumeEnabled = true; s.loudnorm = true; s.compressor = true; s.compThreshold = -18; s.compRatio = 3; s.mute = false
        case .mute: s.mute = true
        }

        switch voice {
        case .normal: s.eqEnabled = false
        case .boost: s.eqEnabled = true; s.eqGains = AudioSettings.clarityEQ; s.highpass = 100
        case .podcast: s.eqEnabled = true; s.eqGains = AudioSettings.podcastEQ; s.highpass = 90
            if s.compressor { s.compRatio = 4 }
        }

        let autoAmount: Double = {
            guard let nf = noiseFloor, let sp = speechLevel else { return 12 }
            return min(30, max(6, (sp - nf) * 0.4))
        }()
        let autoFloor: Double = min(-20, max(-80, (noiseFloor ?? -52) + 2))
        switch noise {
        case .off: s.denoise = false
        case .remove: s.denoise = true; s.denoiseAuto = true; s.denoiseAmount = autoAmount; s.noiseFloor = autoFloor
        case .aggressive:
            s.denoise = true; s.denoiseAuto = false
            s.denoiseAmount = min(40, max(18, autoAmount * 1.8))
            s.noiseFloor = min(-20, autoFloor + 6)
            s.gate = true; s.gateThreshold = min(-25, autoFloor + 12)
        }
        return s
    }
}
