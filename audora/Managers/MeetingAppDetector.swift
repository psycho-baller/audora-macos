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
    private var cancellables = Set<AnyCancellable>()

    // Known meeting apps and browsers
    // This list can be expanded
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
        // Check and request notification permission
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error = error {
                        print("❌ Error requesting notification permission: \(error)")
                    } else if granted {
                        print("✅ Notification permission granted")
                    } else {
                        print("🚫 Notification permission denied by user")
                    }
                }
            case .denied:
                print("🚫 Notification permission is DENIED. Please enable it in System Settings -> Notifications -> Audora.")
            case .authorized, .provisional, .ephemeral:
                print("✅ Notification permission already granted")
            @unknown default:
                break
            }
        }

        micMonitor = MicActivityMonitor()
        appMonitor = FrontmostAppMonitor()

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
    }

    private func handleStateChange(isMicActive: Bool, frontmostApp: NSRunningApplication?) {
        print("🔄 State update - Mic: \(isMicActive), App: \(frontmostApp?.localizedName ?? "nil")")

        guard isMicActive, let app = frontmostApp, let bundleID = app.bundleIdentifier else {
            // If mic is off or no app, clear detected apps
            if !detectedMeetingApps.isEmpty {
                detectedMeetingApps.removeAll()
            }
            return
        }

        // Check if the frontmost app is a meeting app
        if knownMeetingApps.contains(bundleID) {
            print("🎯 Meeting app active with mic: \(bundleID)")

            // If this is a new detection
            if !detectedMeetingApps.contains(bundleID) {
                detectedMeetingApps.insert(bundleID)
                checkAndNotify(app: app)
            }
        } else {
            // Frontmost app is not a meeting app, but mic is on.
            // We might want to clear detected apps if we only care about the *frontmost* one.
            // For now, let's clear it to be strict.
            detectedMeetingApps.removeAll()
        }
    }

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

        // 4. Send notification
        sendNotification(appName: app.localizedName ?? bundleID)
    }

    private func sendNotification(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Meeting Detected"
        content.body = "It looks like you're in a meeting with \(appName). Start recording?"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error scheduling notification: \(error)")
            } else {
                print("📨 Notification scheduled for \(appName)")
            }
        }
    }
}
