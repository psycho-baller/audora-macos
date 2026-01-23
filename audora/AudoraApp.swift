//
//  AudoraApp.swift
//  Audora
//
//  Created by Owen Gretzinger on 2025-07-10.
//

import SwiftUI
import Sparkle
import PostHog
import RunAnywhere
import LLMSwift
import WhisperKitTranscription
import FluidAudioDiarization

@main
struct AudoraApp: App {
    private let updaterController: SPUStandardUpdaterController
    
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
        
        // --- RunAnywhere initialization ---
        Task {
            do {
                // Development mode (recommended for getting started)
                try await RunAnywhere.initialize(
                    apiKey: "dev",           // Any string works in dev mode
                    baseURL: "localhost",    // Not used in dev mode
                    environment: .development
                )
                
                // Register LLM adapter for text generation
                await LLMSwiftServiceProvider.register()
                try await RunAnywhere.registerFrameworkAdapter(
                    LLMSwiftAdapter(),
                    models: [
                        // SmolLM2 135M
                        try ModelRegistration(
                            url: "https://huggingface.co/prithivMLmods/SmolLM2-135M-GGUF/resolve/main/SmolLM2-135M.Q8_0.gguf",
                            framework: .llamaCpp,
                            id: "smollm2-135m",
                            name: "SmolLM2 135M",
                            memoryRequirement: 250_000_000
                        ),
                        // SmolLM2 360M
                        try ModelRegistration(
                            url: "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
                            framework: .llamaCpp,
                            id: "smollm2-360m",
                            name: "SmolLM2 360M",
                            memoryRequirement: 500_000_000
                        ),
                        // Qwen 2.5 0.5B
                        try ModelRegistration(
                            url: "https://huggingface.co/Qwen/Qwen2.5-0.5B-GGUF/resolve/main/qwen2.5-0.5b.Q8_0.gguf",
                            framework: .llamaCpp,
                            id: "qwen2.5-0.5b",
                            name: "Qwen 2.5 0.5B",
                            memoryRequirement: 650_000_000
                        )
                    ]
                )
                
                // Register WhisperKit for voice features
                await WhisperKitServiceProvider.register()
                try await RunAnywhere.registerFrameworkAdapter(
                    WhisperKitAdapter.shared,
                    models: [
                        // Whisper Small (better accuracy than Base)
                        try ModelRegistration(
                            url: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-small",
                            framework: .whisperKit,
                            id: "whisper-small",
                            name: "Whisper Small",
                            format: .mlmodel,
                            memoryRequirement: 244_000_000
                        ),
                    ]
                )
                
                // You cannot load the STT models, so the one that is downloaded should be used
                do {
                    try await RunAnywhere.downloadModel("whisper-small")
                } catch {
                    print("Failed to download model: \(error)")
                }

                // Register FluidAudio for speaker diarization
                await FluidAudioDiarizationProvider.register()
            } catch {
                print("RunAnywhere setup failed: \(error.localizedDescription)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 400)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 600)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
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
