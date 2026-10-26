import SwiftUI
import AppKit

struct SettingsPanel: View {
    @EnvironmentObject var m: ProjectModel
    @State private var collapsed: Set<String> = []
    @State private var infoShown: String?
    @State private var infoDismissedAt = Date.distantPast

    /// Plain-language help for every card, shown from the ⓘ button.
    private static let help: [String: [(String, String)]] = [
        "Normalize Volume": [
            (String(localized: "Auto"), String(localized: "Levels the whole recording to -16 LUFS, the loudness standard for podcasts and online video. Quiet passages come up, loud ones come down.")),
            (String(localized: "Manual"), String(localized: "Shows the Volume slider. Raises or lowers the whole recording by a fixed amount in decibels. +6 dB is about twice as loud.")),
            (String(localized: "Mute"), String(localized: "Replaces the sound with silence. The video is untouched.")),
        ],
        "Denoise": [
            (String(localized: "Auto"), String(localized: "Measures the background noise in the quiet parts of the timeline and removes that much. Re-measures when the quiet parts change.")),
            (String(localized: "Manual"), String(localized: "Lets you set the values yourself. Detect Noise fills them in from the measurement as a starting point.")),
            (String(localized: "Amount"), String(localized: "How many decibels of noise to remove. Higher is cleaner but can make the voice sound thin or watery.")),
            (String(localized: "Noise floor"), String(localized: "The level below which sound is treated as noise. Set it a little above the measured floor.")),
        ],
        "Equalizer": [
            (String(localized: "Preset"), String(localized: "Starting shapes for the curve. Voice Clarity lifts 2–5 kHz where consonants live. Warm adds body around 150–400 Hz. Podcast is a general spoken-word curve. Shows Manual once you move a point.")),
            (String(localized: "Graph"), String(localized: "Eight bands from 60 Hz to 12 kHz. Drag a point up to boost or down to cut that band, ±12 dB. Double-click a point to reset it.")),
            (String(localized: "Orange tabs"), String(localized: "The left tab is the rumble cut: everything below it is removed (desk thumps, air conditioning). 80–100 Hz is safe for voice. The right tab is the hiss cut: everything above it is removed. Keep it above 8 kHz or speech loses crispness. Drag a tab to the edge to turn that cut off. The shaded areas show what is cropped.")),
        ],
        "Even Out Loud Parts": [
            (String(localized: "What it does"), String(localized: "Listens for moments that are much louder than the rest, such as a laugh or a raised voice, and quiets them down. Normal speech is left alone.")),
            (String(localized: "Threshold"), String(localized: "The loudness where it starts to act. Anything above this level is reduced. Lower values catch more of the recording.")),
            (String(localized: "Ratio"), String(localized: "How strongly loud parts are reduced. 2:1 is gentle, 4:1 is firm, 10:1 flattens almost every peak.")),
        ],
        "Trim Quiet Parts": [
            (String(localized: "Quiet below"), String(localized: "Anything under this level counts as quiet. Raise it to catch more pauses, lower it to keep soft speech.")),
            (String(localized: "Min length"), String(localized: "A pause has to be at least this long to be removed. Short gaps between words are kept. A small margin is always left on both sides of a cut so words are not clipped.")),
            (String(localized: "Red blocks"), String(localized: "Each red block on the timeline is a cut. Click one to keep it. All and None toggle every block.")),
            (String(localized: "Noise gate"), String(localized: "Different from the cuts: it keeps the timeline as it is but mutes the audio in the short gaps between words when the level falls under the gate threshold. Good against constant hiss. Set too high, it clips the start of words.")),
        ],
        "Advanced Export Options": [
            (String(localized: "Lossless trim"), String(localized: "Cuts the video at the nearest keyframes without re-encoding it. The picture is untouched but the cut may land a few frames off.")),
            (String(localized: "Re-encoding"), String(localized: "Only happens when the timeline has cuts. The Mac's hardware video encoder re-encodes the picture with the same codec and bitrate as the source.")),
        ],
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                volumeSection
                noiseSection
                eqSection
                dynamicsSection
                silenceSection
                outputSection
                ExportButton().padding(.top, 6)
            }
            .padding(12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Volume

    private var volumeSection: some View {
        card("Normalize Volume", isOn: $m.settings.volumeEnabled) {
            Picker("", selection: Binding(
                get: { m.settings.mute ? 2 : (m.settings.loudnorm ? 0 : 1) },
                set: { m.settings.mute = $0 == 2; if $0 != 2 { m.settings.loudnorm = $0 == 0 } })) {
                Text("Auto").tag(0)
                Text("Manual").tag(1)
                Text("Mute").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if m.settings.mute {
                Text("The sound is replaced with silence. Other effects are skipped.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if m.settings.loudnorm {
                Text("Levels the voice to -16 LUFS, the podcast standard.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                slider("Volume", value: $m.settings.gain, in: -12...12, unit: "dB", digits: 1, step: 0.5)
            }
        }
    }

    // MARK: Denoise

    private var noiseSection: some View {
        card("Denoise", isOn: $m.settings.denoise) {
            Picker("", selection: $m.settings.denoiseAuto) {
                Text("Auto").tag(true)
                Text("Manual").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if m.settings.denoiseAuto {
                if let nf = m.detectedNoiseFloor, let sp = m.detectedSpeechLevel {
                    Text("Measured from the quiet parts: noise floor \(Int(nf)) dB, voice \(Int(sp)) dB. Reducing by \(Int(m.settings.denoiseAmount)) dB.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack {
                    Button("Detect Noise") { m.applyDetectedNoise() }
                        .disabled(m.detectedNoiseFloor == nil)
                    if let nf = m.detectedNoiseFloor, let sp = m.detectedSpeechLevel {
                        Text("floor \(Int(nf)) dB · voice \(Int(sp)) dB")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                slider("Amount", value: $m.settings.denoiseAmount, in: 0...40, unit: "dB", digits: 0)
                slider("Noise floor", value: $m.settings.noiseFloor, in: -80...(-20), unit: "dB", digits: 0)
            }
        }
    }

    // MARK: Equalizer

    private var eqSection: some View {
        card("Equalizer", isOn: $m.settings.eqEnabled) {
            HStack {
                Text("Preset")
                Spacer()
                Picker("", selection: Binding(
                    get: { m.settings.eqPresetName },
                    set: { name in
                        if let p = AudioSettings.eqPresets.first(where: { $0.name == name }) {
                            m.settings.eqGains = p.gains
                        }
                    })) {
                    ForEach(AudioSettings.eqPresets, id: \.name) { Text(LocalizedStringKey($0.name)).tag($0.name) }
                    if m.settings.eqPresetName == "Manual" { Text("Manual").tag("Manual") }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            EQGraphView(gains: $m.settings.eqGains, highpass: $m.settings.highpass, lowpass: $m.settings.lowpass)
            Text(cutSummary).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var cutSummary: String {
        let lo = m.settings.highpass > 0
            ? String(localized: "Rumble cut below \(Int(m.settings.highpass)) Hz") : String(localized: "No rumble cut")
        let hi = m.settings.lowpass > 0
            ? String(localized: "hiss cut above \(String(format: "%.1f", m.settings.lowpass / 1000)) kHz")
            : String(localized: "no hiss cut")
        return String(localized: "\(lo) · \(hi). Drag the orange tabs to change.")
    }

    // MARK: Compressor

    private var dynamicsSection: some View {
        card("Even Out Loud Parts", isOn: $m.settings.compressor) {
            Text("Quiets the moments that are much louder than the rest, so the whole recording sits at a steady level.")
                .font(.caption).foregroundStyle(.secondary)
            slider("Threshold", value: $m.settings.compThreshold, in: -40...0, unit: "dB", digits: 0)
            slider("Ratio", value: $m.settings.compRatio, in: 1...10, unit: ":1", digits: 1, step: 0.5)
        }
    }

    // MARK: Quiet parts

    private var silenceSection: some View {
        card("Trim Quiet Parts", isOn: $m.removeSilence) {
            Text("Playback skips the red blocks so you can hear the result.")
                .font(.caption).foregroundStyle(.secondary)
            slider("Quiet below", value: $m.silenceThreshold, in: -80...(-10), unit: "dB", digits: 0)
            slider("Min length", value: $m.silenceMinDuration, in: 0.2...5, unit: "s", digits: 1, step: 0.1)
            HStack {
                Text("\(m.silences.count) quiet parts · \(timeString(m.removedSilenceDuration)) removed")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("All") { m.setAllSilences(remove: true) }.controlSize(.small)
                Button("None") { m.setAllSilences(remove: false) }.controlSize(.small)
            }
            Divider()
            Toggle("Noise gate: silence the short gaps between words", isOn: $m.settings.gate)
            if m.settings.gate {
                slider("Gate threshold", value: $m.settings.gateThreshold, in: -70...(-20), unit: "dB", digits: 0)
            }
        }
    }

    // MARK: Output

    private var hasTrim: Bool { m.trimStart > 0.001 || m.trimEnd < m.duration - 0.001 }
    private var hasCuts: Bool { !m.activeCuts.isEmpty }
    private var showLossless: Bool { hasTrim && !hasCuts }
    private var showReencode: Bool { hasCuts || (hasTrim && !m.losslessTrim) }

    @ViewBuilder
    private var outputSection: some View {
        if showLossless || showReencode {
            card("Advanced Export Options", isOn: nil) {
                if showLossless {
                    Toggle("Lossless trim (cut at keyframes, may be off by a few frames)", isOn: $m.losslessTrim)
                }
                if showReencode {
                    Text("Cuts change the timeline, so the video is re-encoded with the same codec and bitrate as the source.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Helpers

    /// A card with its title inside. The chevron and title row expand or collapse the content.
    /// The switch on the right turns the effect on or off without changing the collapsed state.
    private func card<Content: View>(_ title: String, isOn: Binding<Bool>?,
                                     @ViewBuilder content: () -> Content) -> some View {
        let expanded = !collapsed.contains(title)
        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 12)
                    Text(LocalizedStringKey(title)).font(.headline)
                    Button {
                        // A click outside the popover dismisses it first; if that click was on the
                        // button itself, treat it as "close", not "reopen".
                        if Date().timeIntervalSince(infoDismissedAt) < 0.35 { return }
                        infoShown = infoShown == title ? nil : title
                    } label: {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(-6)
                    .help("What these settings do")
                    .popover(isPresented: Binding(get: { infoShown == title },
                                                  set: { if !$0 { infoShown = nil; infoDismissedAt = Date() } }),
                             arrowEdge: .leading) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(LocalizedStringKey(title)).font(.headline)
                            ForEach(Self.help[title] ?? [], id: \.0) { item in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.0).font(.subheadline.weight(.semibold))
                                    Text(item.1).font(.callout).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(14)
                        .frame(width: 320)
                    }
                    Spacer()
                    if let isOn {
                        Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden()
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if expanded { collapsed.insert(title) } else { collapsed.remove(title) }
                    }
                }
                if expanded {
                    Divider()
                    content()
                        .opacity(isOn?.wrappedValue ?? true ? 1 : 0.45)
                        .disabled(!(isOn?.wrappedValue ?? true))
                }
            }
            .padding(10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func slider(_ label: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>,
                        unit: String, digits: Int, offLabel: String? = nil, step: Double? = nil) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 110, alignment: .leading).font(.callout)
            // Snap to `step` in the binding instead of the slider, so no tick marks are drawn.
            if let step {
                Slider(value: Binding(get: { value.wrappedValue },
                                      set: { value.wrappedValue = (($0 / step).rounded() * step) }),
                       in: range)
            } else {
                Slider(value: value, in: range)
            }
            Text(valueText(value.wrappedValue, unit: unit, digits: digits, offLabel: offLabel))
                .font(.caption).monospacedDigit()
                .frame(width: 62, alignment: .trailing)
        }
    }

    private func valueText(_ v: Double, unit: String, digits: Int, offLabel: String?) -> String {
        if let offLabel, v == 0 { return offLabel }
        let num = String(format: "%.\(digits)f", v)
        return unit == ":1" ? "\(num):1" : "\(num) \(unit)"
    }
}
