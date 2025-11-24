//
//  AudoraApp.swift
//  Audora
//
//  Created by Owen Gretzinger on 2025-07-10.
//

import SwiftUI
import Sparkle
import PostHog

@main
struct AudoraApp: App {
    private let updaterController: SPUStandardUpdaterController
    @StateObject private var settingsViewModel = SettingsViewModel()

    init() {
        updaterController = SPUStandardUpdaterController(updaterDelegate: nil, userDriverDelegate: nil)
        // Setup PostHog analytics for anonymous tracking
        let posthogAPIKey = "phc_6y4KXMabWzGL2UJIK8RoGJt9QCGTU8R1yuJ8OVRp5IV"
        let posthogHost = "https://us.i.posthog.com"
        let config = PostHogConfig(apiKey: posthogAPIKey, host: posthogHost)
        // Only capture anonymous events
        config.personProfiles = .never
        // Enable lifecycle and screen view autocapture
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = true
        PostHogSDK.shared.setup(config)
        // Register environment as a super property
        #if DEBUG
        PostHogSDK.shared.register(["environment": "dev"] )
        #else
        PostHogSDK.shared.register(["environment": "prod"] )
        #endif

        // Start meeting app detection
        MeetingAppDetector.shared.startMonitoring()
        MeetingAppDetector.shared.onOpenSettings = {}
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 400)
                .environmentObject(settingsViewModel)
                .background(OpenSettingsInstaller())
        }
        .handlesExternalEvents(matching: ["main-window"])
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 600)

        SwiftUI.Settings {
            SettingsView(viewModel: settingsViewModel)
        }

        // Menu bar extra
        SwiftUI.MenuBarExtra("Audora", systemImage: "bolt.fill") {
            Button("New Recording") {
                // This would need to be coordinated with the app state
                NotificationCenter.default.post(name: .createNewRecording, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()



            Divider()

            SettingsLink {
                Text("Open Settings...")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            CheckForUpdatesView(updater: updaterController.updater)

            Divider()

            Link("Documentation", destination: URL(string: "https://audora.psycho-baller.com/docs")!)

            Link("Report an Issue", destination: URL(string: "https://github.com/psycho-baller/audora/issues")!)

            Link("Privacy Policy", destination: URL(string: "https://audora.psycho-baller.com/privacy")!)

            Button("Quit Audora") {
                NSApp.terminate(nil)
            }
        }
    }
}

extension NSApplication {
    @objc func showMainWindow() {
        // Brute-force way: just activate app and bring all windows forward
        self.activate(ignoringOtherApps: true)
        self.windows.forEach { $0.makeKeyAndOrderFront(nil) }
    }
}

struct CheckForUpdatesView: View {
    let updater: SPUUpdater

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .keyboardShortcut("u", modifiers: .command)
    }
}

private struct OpenSettingsInstaller: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .onAppear {
                MeetingAppDetector.shared.onOpenSettings = { openSettings() }
            }
            .onDisappear {
                // Avoid holding onto an environment action after the view goes away
                MeetingAppDetector.shared.onOpenSettings = {}
            }
            .accessibilityHidden(true)
    }
}
