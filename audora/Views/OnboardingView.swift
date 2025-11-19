//
//  OnboardingView.swift
//  audora
//
//  Created by Tony Tran on 2025-11-18.
//

import SwiftUI

struct OnboardingView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @State private var currentStep: Int = 0

    var body: some View {
        VStack {
            switch currentStep {
            case 0:
                // First step: Welcome screen
                WelcomeView(nextStep: { currentStep += 1 })
            case 1:
                // Second step: Full configuration/setup page
                SetupView(
                    settingsViewModel: settingsViewModel,
                    goBack: { currentStep = 0 }
                )
            default:
                EmptyView()
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

#Preview {
    OnboardingView(settingsViewModel: SettingsViewModel())
}
