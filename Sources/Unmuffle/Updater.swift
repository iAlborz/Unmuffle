#if canImport(Sparkle)
// Only the GitHub version links Sparkle (Package.swift). The App Store version is built from the Xcode
// project without it, so none of this is compiled there: the App Store updates its own apps.
import AppKit
import Sparkle
import SwiftUI
import UserNotifications

/// Checks for updates once a day with Sparkle. A found update first shows as a banner in the window and,
/// while Unmuffle is in the background, as a notification. Both open Sparkle's update window, which
/// downloads, installs and relaunches.
@MainActor
final class UpdateController: NSObject, ObservableObject {
    /// The version that is ready to install, while the banner is showing.
    @Published var availableVersion: String?
    private var updater: SPUStandardUpdaterController!

    override init() {
        super.init()
        // `swift run` makes a bare executable with no Info.plist, where Sparkle would show a startup error.
        let isBundledApp = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        updater = SPUStandardUpdaterController(startingUpdater: isBundledApp, updaterDelegate: nil,
                                               userDriverDelegate: self)
        UNUserNotificationCenter.current().delegate = self
    }

    /// Opens Sparkle's update window: shows the new version, or says Unmuffle is up to date.
    func checkForUpdates() {
        updater.checkForUpdates(nil)
    }

    func dismissBanner() {
        availableVersion = nil
    }

    /// macOS asks for permission the first time; without it only the banner shows.
    private func notify(version: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Unmuffle \(version) is available.")
        content.body = String(localized: "Click to update.")
        Task {
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            try? await center.add(UNNotificationRequest(identifier: "update", content: content, trigger: nil))
        }
    }
}

// Sparkle calls these on the main thread.
extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Updates found by the daily check: show the banner instead of Sparkle's window.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }  // Sparkle shows its own window
        availableVersion = update.displayVersionString
        if !NSApp.isActive { notify(version: update.displayVersionString) }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["update"])
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}

extension UpdateController: UNUserNotificationCenterDelegate {
    /// Clicking the notification opens the update window.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { self.checkForUpdates() }
        completionHandler()
    }
}

/// A slim bar at the top of the window while an update is waiting.
struct UpdateBanner: View {
    @EnvironmentObject var updates: UpdateController

    var body: some View {
        if let version = updates.availableVersion {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Unmuffle \(version) is available.")
                    .lineLimit(1)
                Spacer()
                Button("Later") { updates.dismissBanner() }
                Button("Update") { updates.checkForUpdates() }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}
#endif
