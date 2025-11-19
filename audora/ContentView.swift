//
//  ContentView.swift
//  audora
//
//  Created by Owen Gretzinger on 2025-07-10.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @State private var showingSettings = false
    @State private var triggerNewRecording = false
    @State private var triggerOpenSettings = false

    var body: some View {
        Group {
            if !settingsViewModel.settings.hasCompletedOnboarding {
                OnboardingView(settingsViewModel: settingsViewModel)
            } else {
                MeetingListView(
                    settingsViewModel: settingsViewModel,
                    triggerNewRecording: $triggerNewRecording,
                    triggerOpenSettings: $triggerOpenSettings
                )
                .onAppear {
                    // Restore auto-recording state on launch
                    if settingsViewModel.settings.autoRecordingEnabled {
                        AudioManager.shared.enableAutoRecording()
                    }

                    // Restore mic following state on launch
                    if settingsViewModel.settings.micFollowingEnabled {
                        AudioManager.shared.enableMicFollowing()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .createNewRecording)) { _ in
                    triggerNewRecording.toggle()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                    triggerOpenSettings.toggle()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
