import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @EnvironmentObject var m: ProjectModel
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 12) {
            // The app icon from the bundle (a generic icon under `swift run`).
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .scaleEffect(targeted ? 1.08 : 1)
                .animation(.easeOut(duration: 0.15), value: targeted)
            Text("Drop a video here").font(.title2)
            Text("Only the audio is changed. The video stream is saved exactly as it is.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose Video…") { m.openPanel() }
                .keyboardShortcut("o")
            if !m.toolsAvailable {
                Text("ffmpeg was not found. In Terminal run:  brew install ffmpeg")
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }
            if m.isBusy {
                ProgressView(m.busyLabel).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.4))
                .padding(16)
        )
        .videoDrop(model: m, targeted: $targeted)
    }
}

extension View {
    func videoDrop(model: ProjectModel, targeted: Binding<Bool>? = nil) -> some View {
        onDrop(of: [.fileURL], isTargeted: targeted) { providers in
            guard let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
                return false
            }
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var u: URL?
                if let d = item as? Data { u = URL(dataRepresentation: d, relativeTo: nil) }
                else if let x = item as? URL { u = x }
                guard let u else { return }
                Task { @MainActor in await model.load(u) }
            }
            return true
        }
    }
}
