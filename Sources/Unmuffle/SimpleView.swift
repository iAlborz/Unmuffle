import SwiftUI

/// Simple mode: player on the left, three choices on the right that combine into one effect chain.
struct SimpleView: View {
    @EnvironmentObject var m: ProjectModel

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                VStack(spacing: 8) {
                    PlayerPane()
                    TransportBar()
                }
                .frame(maxHeight: .infinity)
                .padding(10)
                .frame(minWidth: 450)

                ScrollView {
                    VStack(spacing: 10) {
                        choiceCard("Audio", icon: "speaker.wave.2.fill",
                                   selection: Binding(get: { m.simpleChoices.audio },
                                                      set: { m.simpleChoices.audio = $0; m.applySimpleChoices() }),
                                   description: m.simpleChoices.audio.description)
                        if m.simpleChoices.audio != .mute {
                            choiceCard("Voice", icon: "person.wave.2.fill",
                                       selection: Binding(get: { m.simpleChoices.voice },
                                                          set: { m.simpleChoices.voice = $0; m.applySimpleChoices() }),
                                       description: m.simpleChoices.voice.description)
                            choiceCard("Background Noise", icon: "wind",
                                       selection: Binding(get: { m.simpleChoices.noise },
                                                          set: { m.simpleChoices.noise = $0; m.applySimpleChoices() }),
                                       description: m.simpleChoices.noise.description)
                        }
                        Text(m.simpleChoices.audio == .mute
                             ? "The exported video will have no sound."
                             : "The player plays the result. Export when it sounds right.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ExportButton()
                    }
                    .padding(10)
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 300)
            }
            Divider()
            BottomBar()
        }
        .videoDrop(model: m)
    }

    private func choiceCard<T: CaseIterable & Identifiable & RawRepresentable & Hashable>(
        _ title: String, icon: String, selection: Binding<T>, description: String
    ) -> some View where T.RawValue == String, T.AllCases: RandomAccessCollection {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 16)
                    Text(title).font(.subheadline.weight(.semibold))
                }
                BigSegmented(selection: selection)
                Text(description)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 28, alignment: .topLeading)
            }
            .padding(4)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

/// A full-width segmented control with large click targets.
struct BigSegmented<T: CaseIterable & Identifiable & RawRepresentable & Hashable>: View
    where T.RawValue == String, T.AllCases: RandomAccessCollection {
    @Binding var selection: T
    @State private var hover: T?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(T.allCases)) { option in
                let selected = option == selection
                Button { withAnimation(.easeInOut(duration: 0.12)) { selection = option } } label: {
                    Text(option.rawValue)
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .padding(.horizontal, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selected ? Color.accentColor
                                      : (hover == option ? Color.primary.opacity(0.08) : Color.clear))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hover = $0 ? option : (hover == option ? nil : hover) }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.gray.opacity(0.18)))
    }
}
