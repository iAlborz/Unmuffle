import SwiftUI

enum AppMode: String { case instant, simple, advanced }

/// A video dropped in Instant mode.
struct InstantJob: Identifiable {
    enum State: Equatable { case waiting, working, saved(URL), failed(String) }
    let id = UUID()
    let input: URL
    var state = State.waiting

    var isFinished: Bool {
        switch state {
        case .saved, .failed: return true
        case .waiting, .working: return false
        }
    }
}

/// Instant mode: drop videos and each one is cleaned up with the choices on the right and saved next to
/// the original. Nothing to confirm.
struct InstantView: View {
    @EnvironmentObject var m: ProjectModel
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if m.instantJobs.isEmpty {
                    VStack(spacing: 10) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 80, height: 80)
                            .scaleEffect(targeted ? 1.08 : 1)
                            .animation(.easeOut(duration: 0.15), value: targeted)
                        Text("Drop videos here").font(.title2)
                        Text("Each one is cleaned up right away and saved next to the original as name-1.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Choose Videos…") { m.openPanel() }
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(m.instantJobs) { InstantRow(job: $0) }
                        }
                        .padding(28)
                    }
                    HStack {
                        Text("Drop more videos to clean them up too.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") { m.instantJobs.removeAll { $0.isFinished } }
                            .controlSize(.small)
                            .disabled(!m.instantJobs.contains { $0.isFinished })
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 26)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                    .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.4))
                    .padding(16)
            )
            .contentShape(Rectangle())
            .videoDrop(model: m, targeted: $targeted)

            Divider()
            InstantOptions().frame(width: 190)
        }
    }
}

private struct InstantRow: View {
    @EnvironmentObject var m: ProjectModel
    let job: InstantJob

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "film").foregroundStyle(.secondary)
            Text(job.input.lastPathComponent).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 12)
            switch job.state {
            case .waiting:
                Text("Waiting").foregroundStyle(.secondary)
            case .working:
                ProgressView(value: m.progress >= 0 ? m.progress : nil)
                    .controlSize(.small)
                    .frame(width: 90)
            case .saved(let out):
                Label {
                    Text("Saved")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .help(out.lastPathComponent)
                Button { NSWorkspace.shared.activateFileViewerSelecting([out]) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            case .failed(let message):
                Label(message.components(separatedBy: "\n")[0], systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(message)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
    }
}

/// The Simple choices, small. They apply to each video when its turn comes.
private struct InstantOptions: View {
    @EnvironmentObject var m: ProjectModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                option("Audio", selection: $m.simpleChoices.audio)
                if m.simpleChoices.audio != .mute {
                    option("Voice", selection: $m.simpleChoices.voice)
                    option("Background Noise", selection: $m.simpleChoices.noise)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func option<T: CaseIterable & Identifiable & RawRepresentable & Hashable>(
        _ title: LocalizedStringKey, selection: Binding<T>
    ) -> some View where T.RawValue == String, T.AllCases: RandomAccessCollection {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(Array(T.allCases)) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .controlSize(.small)
        }
    }
}
