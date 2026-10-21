import SwiftUI
import AVKit

struct EditorView: View {
    @EnvironmentObject var m: ProjectModel

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                VStack(spacing: 10) {
                    PlayerPane()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    TransportBar()
                    TimelineView()
                }
                .padding(12)
                .frame(minWidth: 640)
                SettingsPanel()
                    .frame(minWidth: 330, idealWidth: 360, maxWidth: 440)
            }
            Divider()
            BottomBar()
        }
        .videoDrop(model: m)
    }
}

func mediaSummary(_ i: MediaInfo) -> String {
        var s = "\(i.videoCodec.uppercased()) \(i.width)×\(i.height)"
        if i.fps > 0 { s += " \(String(format: "%.3g", i.fps)) fps" }
        if i.videoBitrate > 0 { s += " · \(i.videoBitrate / 1000) kb/s" }
        s += " · audio \(i.audioCodec.uppercased())"
        if i.audioBitrate > 0 { s += " \(i.audioBitrate / 1000) kb/s" }
        s += " · \(timeString(i.duration))"
        return s
}

struct PlayerPane: View {
    @EnvironmentObject var m: ProjectModel
    var body: some View {
        PlayerViewRepresentable(player: m.player)
            .aspectRatio(aspect, contentMode: .fit)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { m.togglePlay() }
    }
    private var aspect: CGFloat {
        m.info.width > 0 && m.info.height > 0 ? CGFloat(m.info.width) / CGFloat(m.info.height) : 16 / 9
    }
}

/// Direct AVKit player view with no built-in controls.
struct PlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .none
        v.showsFullScreenToggleButton = false
        v.allowsVideoFrameAnalysis = false   // hides the Live Text button
        v.videoGravity = .resizeAspect
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
    }
}

struct TransportBar: View {
    @EnvironmentObject var m: ProjectModel
    var body: some View {
        HStack(spacing: 10) {
            Button(action: m.togglePlay) {
                Image(systemName: m.isPlaying ? "pause.fill" : "play.fill").frame(width: 20)
            }
            .keyboardShortcut(.space, modifiers: [])
            .help("Play / pause (space)")
            Text("\(timeString(m.currentTime)) / \(timeString(m.duration))")
                .font(.callout)
                .monospacedDigit()
                .fixedSize()
            Spacer()
            Image(systemName: m.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(.secondary)
            Slider(value: $m.volume, in: 0...1).frame(width: 70)
            Picker("", selection: Binding(get: { m.showingProcessed }, set: { m.setSource(processed: $0) })) {
                Text("Original").tag(false)
                Text("Processed").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .help("Processed applies the current settings while it plays.")
        }
        .controlSize(.small)
    }
}

struct BottomBar: View {
    @EnvironmentObject var m: ProjectModel

    var body: some View {
        HStack(spacing: 14) {
            if m.isBusy {
                ProgressView(value: m.progress >= 0 ? m.progress : nil)
                    .frame(width: 180)
                Text(m.busyLabel).font(.callout)
                Button("Cancel") { m.cancel() }
            } else if !m.statusMessage.isEmpty {
                Text(m.statusMessage).font(.callout).lineLimit(1)
                if let o = m.lastOutput {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([o]) }
                        .controlSize(.small)
                }
            } else {
                Text(mediaSummary(m.info)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("Auto-play", isOn: $m.autoplay)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help("Start playing each video as soon as it is opened")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// The big Export button used in both modes.
struct ExportButton: View {
    @EnvironmentObject var m: ProjectModel
    var body: some View {
        VStack(spacing: 6) {
            Button { Task { await m.export() } } label: {
                Label(m.isBusy ? m.busyLabel : "Export", systemImage: "square.and.arrow.down")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(m.isBusy || m.url == nil)
            if m.isBusy {
                ProgressView(value: m.progress >= 0 ? m.progress : nil)
            }
            Text("Saves a copy next to the original as name-1, name-2, …")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
