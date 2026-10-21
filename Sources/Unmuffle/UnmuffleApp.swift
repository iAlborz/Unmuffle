import SwiftUI
import AppKit

@main
struct UnmuffleApp: App {
    @StateObject private var model = ProjectModel()

    var body: some Scene {
        WindowGroup("Unmuffle") {
            ContentView()
                .environmentObject(model)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    // Open small. macOS would otherwise restore the larger size the window grew to for a video.
                    // SwiftUI applies the saved size after onAppear, so resize on the next turn of the run loop.
                    DispatchQueue.main.async {
                        guard let win = NSApp.windows.first else { return }
                        let f = win.frame
                        win.setFrame(NSRect(x: f.minX, y: f.maxY - 400, width: 560, height: 400), display: true)
                    }
                    // Allow: Unmuffle.app/Contents/MacOS/Unmuffle /path/to/video.mp4
                    if let path = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }),
                       model.url == nil {
                        Task { await model.load(URL(fileURLWithPath: path)) }
                    }
                    // Debug: UNMUFFLE_AUTOPLAY=1 switches to Processed and plays 3 s after launch.
                    if ProcessInfo.processInfo.environment["UNMUFFLE_AUTOPLAY"] != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            model.setSource(processed: true)
                            model.play()
                        }
                    }
                    // Debug: UNMUFFLE_SNAPSHOT=/path/out.png writes a picture of the window after 5 s.
                    if let snap = ProcessInfo.processInfo.environment["UNMUFFLE_SNAPSHOT"] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
                            guard let win = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first,
                                  let v = win.contentView?.superview ?? win.contentView,
                                  let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else {
                                FileHandle.standardError.write("snapshot: no window (\(NSApp.windows.count))\n".data(using: .utf8)!)
                                return
                            }
                            v.cacheDisplay(in: v.bounds, to: rep)
                            do {
                                try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: snap))
                                FileHandle.standardError.write("snapshot: wrote \(snap)\n".data(using: .utf8)!)
                            } catch {
                                FileHandle.standardError.write("snapshot: \(error)\n".data(using: .utf8)!)
                            }
                        }
                    }
                }
        }
        .defaultSize(width: 560, height: 400)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Video…") { model.openPanel() }
                    .keyboardShortcut("o")
                Button("Export Video") { Task { await model.export() } }
                    .keyboardShortcut("s")
                    .disabled(model.url == nil || model.isBusy)
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: ProjectModel

    var body: some View {
        ZStack {
            // The window grows to each view's minimum size when the view changes.
            if m.url == nil { DropZoneView().frame(minWidth: 460, minHeight: 320) }
            else if m.simpleMode { SimpleView().frame(minWidth: 740, minHeight: 500) }
            else { EditorView().frame(minWidth: 1100, minHeight: 720) }
        }
        .navigationTitle("Unmuffle")
        .navigationSubtitle(m.url?.lastPathComponent ?? "")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { m.openPanel() } label: {
                    Label("Open", systemImage: "folder").padding(.horizontal, 8)
                }
                .labelStyle(.titleAndIcon)
                .help("Open another video (⌘O)")
                .disabled(m.isBusy)
            }
            ToolbarItem(placement: .primaryAction) {
                Picker("", selection: $m.simpleMode) {
                    Text("Simple").tag(true)
                    Text("Advanced").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
        }
    }
}
