import SwiftUI
import AppKit

@main
struct UnmuffleApp: App {
    @StateObject private var model = ProjectModel()
    #if canImport(Sparkle)
    @StateObject private var updates = UpdateController()
    #endif

    var body: some Scene {
        WindowGroup("Unmuffle") {
            ContentView()
                .environmentObject(model)
                #if canImport(Sparkle)
                .environmentObject(updates)
                #endif
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    // Open small. macOS would otherwise restore the larger size the window grew to for a video.
                    // SwiftUI applies the saved size after onAppear, so resize on the next turn of the run loop.
                    DispatchQueue.main.async {
                        guard let win = NSApp.windows.first else { return }
                        let f = win.frame
                        win.setFrame(NSRect(x: f.minX, y: f.maxY - 400, width: 620, height: 400), display: true)
                    }
                    // Allow: Unmuffle.app/Contents/MacOS/Unmuffle /path/to/video.mp4 (several in Instant mode)
                    let paths = CommandLine.arguments.dropFirst()
                        .filter { !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0) }
                        .map { URL(fileURLWithPath: $0) }
                    if model.mode == .instant { model.addInstant(paths) }
                    else if let first = paths.first, model.url == nil {
                        Task { await model.load(first) }
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
        .defaultSize(width: 620, height: 400)
        .commands {
            #if canImport(Sparkle)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updates.checkForUpdates() }
            }
            #endif
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

    private var errorLines: [Substring] {
        (m.errorMessage ?? "").split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
    }

    var body: some View {
        ZStack {
            // The window grows to each view's minimum size when the view changes. 620 fits the mode picker.
            if m.mode == .instant { InstantView().frame(minWidth: 620, minHeight: 360) }
            else if m.url == nil { DropZoneView().frame(minWidth: 620, minHeight: 320) }
            else if m.mode == .simple { SimpleView().frame(minWidth: 740, minHeight: 500) }
            else { EditorView().frame(minWidth: 1100, minHeight: 720) }
        }
        #if canImport(Sparkle)
        .safeAreaInset(edge: .top, spacing: 0) { UpdateBanner() }
        #endif
        // The first line of an error is the headline; ffmpeg's details, if any, follow it.
        .alert(errorLines.first.map(String.init) ?? "",
               isPresented: Binding(get: { m.errorMessage != nil }, set: { if !$0 { m.errorMessage = nil } })) {
        } message: {
            Text(errorLines.dropFirst().first.map(String.init) ?? "")
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
                .disabled(m.isBusy && m.mode != .instant)  // Instant mode queues more videos
            }
            ToolbarItem(placement: .primaryAction) {
                Picker("", selection: $m.mode) {
                    Text("Instant").tag(AppMode.instant)
                    Text("Simple").tag(AppMode.simple)
                    Text("Advanced").tag(AppMode.advanced)
                }
                .pickerStyle(.segmented)
                .frame(width: 216)
                .disabled(m.instantRunning)
            }
        }
    }
}
