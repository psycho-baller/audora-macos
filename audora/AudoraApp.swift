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
        let posthogAPIKey = "phc_Wt8sWUzUF7YPF50aQ0B1qbfA5SJWWR341zmXCaIaIRJ"
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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 400)
                .environmentObject(settingsViewModel)
        }
        .handlesExternalEvents(matching: ["main-window"])
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 600)

        // Menu bar extra
        MenuBarExtra("Audora", systemImage: "bolt.fill") {
            Button("New Recording") {
                // This would need to be coordinated with the app state
                NotificationCenter.default.post(name: .createNewRecording, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Toggle("Auto-Recording", isOn: Binding(
                get: { settingsViewModel.settings.autoRecordingEnabled },
                set: { newValue in
                    settingsViewModel.settings.autoRecordingEnabled = newValue
                    if newValue {
                        AudioManager.shared.enableAutoRecording()
                    } else {
                        AudioManager.shared.disableAutoRecording()
                    }
                }
            ))
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Toggle("Mic Following Mode", isOn: Binding(
                get: { settingsViewModel.settings.micFollowingEnabled },
                set: { newValue in
                    settingsViewModel.settings.micFollowingEnabled = newValue
                    if newValue {
                        AudioManager.shared.enableMicFollowing()
                    } else {
                        AudioManager.shared.disableMicFollowing()
                    }
                }
            ))
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Divider()

            Button("Open Settings...") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()
            
            CheckForUpdatesView(updater: updaterController.updater)

            Divider()

            Link("Documentation", destination: URL(string: "https://audora.psycho-baller.com/docs")!)

            Link("Report an Issue", destination: URL(string: "https://github.com/psycho-baller/audora/issues")!)

            Link("Privacy Policy", destination: URL(string: "https://audora.psycho-baller.com/privacy")!)

            Button("Quit MyApp") {
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
