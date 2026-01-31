import Foundation
import AppKit
import Combine
import UserNotifications

@MainActor
class MeetingAppDetector: ObservableObject {
    static let shared = MeetingAppDetector()

    @Published var detectedMeetingApps: Set<String> = []

    private var micMonitor: MicActivityMonitor?
    private var appMonitor: FrontmostAppMonitor?
    // private var audioMonitor: AppAudioLevelMonitor? // Removed
    private var cancellables = Set<AnyCancellable>()

    private let windowController = MeetingReminderWindowController()

    // Callback to open settings from SwiftUI context
    var onOpenSettings: (() -> Void)?

    // Known meeting apps and browsers
    public let knownMeetingApps: Set<String> = [
        "us.zoom.xos",              // Zoom
        "com.microsoft.teams",      // Microsoft Teams
        "com.google.Chrome",        // Google Chrome (Meet)
        "com.apple.Safari",         // Safari (Meet)
        "app.zen-browser.zen",      // Zen Browser
        // "com.electron.wispr-flow",           // Wispr Flow
        "company.thebrowser.Browser", // Arc Browser
        "com.microsoft.edgemac",    // Microsoft Edge
        "com.hnc.Discord",          // Discord
        "com.cisco.webexmeetingsapp", // Webex
        "com.slack.Slack"           // Slack
    ]

    private init() {}

    func startMonitoring() {
        micMonitor = MicActivityMonitor()
        appMonitor = FrontmostAppMonitor()

        // Listen for recording state changes to hide window
        AudioManager.shared.$isRecording
            .sink { [weak self] isRecording in
                if isRecording {
                    self?.windowController.hide()
                }
            }
            .store(in: &cancellables)

        // Combine mic activity and frontmost app
        micMonitor?.$isMicActive
            .combineLatest(appMonitor!.$frontmostApp)
            .sink { [weak self] isMicActive, frontmostApp in
                self?.handleStateChange(isMicActive: isMicActive, frontmostApp: frontmostApp)
            }
            .store(in: &cancellables)
    }

    func stopMonitoring() {
        micMonitor = nil
        appMonitor = nil
        cancellables.removeAll()
        windowController.hide()
    }

    private func handleStateChange(isMicActive: Bool, frontmostApp: NSRunningApplication?) {
        print("🔄 State update - Mic: \(isMicActive), App: \(frontmostApp?.localizedName ?? "nil")")

        guard isMicActive, let app = frontmostApp, let bundleID = app.bundleIdentifier else {
            // If mic is off or no app, clear detected apps and stop monitoring
            if !detectedMeetingApps.isEmpty {
                detectedMeetingApps.removeAll()
                windowController.hide() // Hide window if meeting ends
            }
            return
        }

        // Check if the frontmost app is a meeting app
        if knownMeetingApps.contains(bundleID) {
            print("🎯 Meeting app active with mic: \(bundleID)")

            // If this is a new detection, check and notify
            if !detectedMeetingApps.contains(bundleID) {
                detectedMeetingApps.insert(bundleID)
                checkAndNotify(app: app)
            }
        } else {
            // Frontmost app is not a meeting app, but mic is on.
            detectedMeetingApps.removeAll()
            windowController.hide()
        }
    }

    // verifyAudioOutput and stopAudioMonitoring removed

    private func checkAndNotify(app: NSRunningApplication) {
        let bundleID = app.bundleIdentifier ?? "unknown"
        print("🧐 Checking notification for: \(bundleID)")

        // 1. Check if global setting is enabled
        guard UserDefaultsManager.shared.meetingReminderEnabled else {
            print("🚫 Meeting reminders are disabled")
            return
        }

        // 2. Check if recording is already active
        guard !AudioManager.shared.isRecording else {
            print("🚫 Recording is already active")
            return
        }

        // 3. Check if ignored
        if UserDefaultsManager.shared.ignoredAppBundleIDs.contains(bundleID) {
            print("🚫 App is ignored")
            return
        }

        // 4. Show UI Overlay
        showOverlay(for: app)
    }

    private func showOverlay(for app: NSRunningApplication) {
        let appName = app.localizedName ?? "Unknown App"
        let bundleID = app.bundleIdentifier ?? ""

        print("🎨 Showing overlay for: \(appName) (\(bundleID))")

        DispatchQueue.main.async {
            self.windowController.show(
                appName: appName,
                onRecord: {
                    print("🔴 User clicked Record from overlay - Creating new meeting")
                    self.windowController.hide()
                    NotificationCenter.default.post(name: .createNewRecording, object: nil)
                },
                onIgnore: {
                    print("🚫 User clicked Ignore from overlay for: \(bundleID)")
                    Task { @MainActor in
                        var ignoredApps = UserDefaultsManager.shared.ignoredAppBundleIDs
                        ignoredApps.insert(bundleID)
                        UserDefaultsManager.shared.ignoredAppBundleIDs = ignoredApps
                        print("✅ Added \(bundleID) to ignored apps. Current ignored: \(ignoredApps)")
                    }
                },
                onSettings: {
                    print("⚙️ User clicked Settings from overlay")
                    Task { @MainActor in
                        self.onOpenSettings?()
                        if self.onOpenSettings == nil {
                            print("⚠️ onOpenSettings callback is nil!")
                        }
                    }
                }
            )
        }
    }
}
