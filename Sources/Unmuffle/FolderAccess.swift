import AppKit

/// The App Store version runs in the App Sandbox, where Unmuffle may only write where the user chose.
/// Instant mode saves next to the original, so it asks once per folder and remembers the answer.
/// The GitHub version isn't sandboxed and never asks.
@MainActor
enum FolderAccess {
    private static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    private static let key = "folderBookmarks"
    private static var folders: [URL] = []

    /// Starts using the folders allowed in earlier sessions.
    static func restore() {
        guard isSandboxed else { return }
        for data in UserDefaults.standard.array(forKey: key) as? [Data] ?? [] {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale),
               u.startAccessingSecurityScopedResource() {
                folders.append(u)
            }
        }
    }

    /// Whether Unmuffle may save in `dir`. Asks the first time.
    static func ensureWritable(_ dir: URL) -> Bool {
        guard isSandboxed, !covers(dir) else { return true }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = dir
        panel.message = String(localized: "Instant mode saves next to the original. Allow Unmuffle to save in this folder?")
        panel.prompt = String(localized: "Allow")
        guard panel.runModal() == .OK, let u = panel.url else { return false }
        if let data = try? u.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set((UserDefaults.standard.array(forKey: key) ?? []) + [data], forKey: key)
        }
        folders.append(u)
        return covers(dir)
    }

    private static func covers(_ dir: URL) -> Bool {
        let path = dir.resolvingSymlinksInPath().pathComponents
        return folders.contains { path.starts(with: $0.resolvingSymlinksInPath().pathComponents) }
    }
}
