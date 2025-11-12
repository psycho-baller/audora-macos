//
//  ContentView.swift
//  audora
//
//  Created by Owen Gretzinger on 2025-07-10.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var settingsViewModel = SettingsViewModel()
    @State private var showingSettings = false

    var body: some View {
        Group {
            if !settingsViewModel.settings.hasCompletedOnboarding {
                OnboardingView(settingsViewModel: settingsViewModel)
            } else {
                MeetingListView(settingsViewModel: settingsViewModel)
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
            }
        }
    }
}

#Preview {
    ContentView()
}
