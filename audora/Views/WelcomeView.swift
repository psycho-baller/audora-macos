//
//  WelcomeView.swift
//  audora
//
//  Created by Tony Tran on 2025-11-18.
//

import SwiftUI

struct WelcomeView: View {
    let nextStep: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to Audora")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Record and transcribe your meetings effortlessly. Let's get you set up.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)

            Button("Get Started") {
                nextStep()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
