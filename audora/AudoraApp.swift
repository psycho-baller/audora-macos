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
import EventKit
import Combine
import Clerk

@main
struct AudoraApp: App {
    private let updaterController: SPUStandardUpdaterController
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var menuBarViewModel = MenuBarViewModel()
    @StateObject private var convexService = ConvexService.shared

    init() {
        updaterController = SPUStandardUpdaterController(updaterDelegate: nil, userDriverDelegate: nil)

        // Configure Clerk
        print("🔐 [Clerk Init] Checking for publishable key...")

        // Check environment variable
        let envKey = ProcessInfo.processInfo.environment["CLERK_PUBLISHABLE_KEY"]
        print("   - Environment CLERK_PUBLISHABLE_KEY: \(envKey != nil ? "found (\(envKey!.prefix(20))...)" : "not found")")

        // Check Info.plist
        let plistKey = Bundle.main.object(forInfoDictionaryKey: "CLERK_PUBLISHABLE_KEY") as? String
        print("   - Info.plist CLERK_PUBLISHABLE_KEY: \(plistKey != nil ? "found (\(plistKey!.prefix(20))...)" : "not found")")

        if let clerkKey = envKey ?? plistKey {
            print("🔐 [Clerk Init] Configuring with key: \(clerkKey.prefix(20))...")
            Clerk.shared.configure(publishableKey: clerkKey)
            print("🔐 [Clerk Init] ✅ Configuration complete")
            // Note: Session will be loaded in loginFromCache() to avoid race condition
        } else {
            print("🔐 [Clerk Init] ⚠️ NO PUBLISHABLE KEY FOUND!")
            print("   - Make sure Config.xcconfig has CLERK_PUBLISHABLE_KEY set")
            print("   - And that it's linked in your Xcode project configuration")
        }

        // Setup PostHog analytics for anonymous tracking
        let posthogAPIKey = "phc_6y4KXMabWzGL2UJIK8RoGJt9QCGTU8R1yuJ8OVRp5IV"
        let posthogHost = "https://us.i.posthog.com"
        let config = PostHogConfig(apiKey: posthogAPIKey, host: posthogHost)
        config.personProfiles = .never
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = true
        PostHogSDK.shared.setup(config)
        
        // Register environment as a super property
#if DEBUG
        PostHogSDK.shared.register(["environment": "dev"] )
#else
        PostHogSDK.shared.register(["environment": "prod"] )
#endif
        
        #if DEBUG
        PostHogSDK.shared.register(["environment": "dev"])
        #else
        PostHogSDK.shared.register(["environment": "prod"])
        #endif

        // Start meeting app detection
        MeetingAppDetector.shared.startMonitoring()
        MeetingAppDetector.shared.onOpenSettings = {}

        // Initialize managers
        _ = NotificationManager.shared
    }
    
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

                let largeModel = try ModelRegistration(
                    url: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3",
                    framework: .whisperKit,
                    id: "whisper-large",
                    name: "Whisper Large",
                    format: .mlmodel,
                    memoryRequirement: 1_550_000_000
                )

                try await RunAnywhere.registerFrameworkAdapter(
                    WhisperKitAdapter.shared,
                    models: [largeModel]
                )

                // Only download if not already present
                do {
                    // Fetch current available models
                    let models = try await RunAnywhere.availableModels()
                    
                    if let modelInfo = models.first(where: { $0.id == largeModel.id }) {
                        if modelInfo.isDownloaded {
                            print("✅ Model already downloaded: \(modelInfo.id)")
                        } else {
                            print("⬇️ Downloading model: \(modelInfo.id)")
                            try await RunAnywhere.downloadModel(largeModel.id)
                            print("✅ Download complete")
                        }
                        
                        // 5️⃣ Load the model using ModelInfo
                        let _ = try await WhisperKitAdapter.shared.loadModel(modelInfo, for: .voiceToText)
                        print("✅ WhisperKit is now using model: \(modelInfo.id) for voice-to-text")
                    } else {
                        print("❌ Model not found in available models")
                    }
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
            Group {
                switch convexService.authState {
                case .loading:
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        Text("Loading...")
                            .foregroundColor(.secondary)
                    }
                    .frame(minWidth: 400, minHeight: 300)
                    .task {
                        // Try to restore session from cache on launch
                        _ = await convexService.loginFromCache()
                    }
                case .authenticated:
                    ContentView()
                        .frame(minWidth: 700, minHeight: 400)
                        .environmentObject(settingsViewModel)
                        .environmentObject(convexService)
                        .background(OpenSettingsInstaller())
                case .unauthenticated:
                    SignInView()
                }
            }
            .onOpenURL { url in
                print("🔗 [OAuth] Received URL: \(url)")
                print("🔗 [OAuth] URL scheme: \(url.scheme ?? "none")")
                print("🔗 [OAuth] URL host: \(url.host ?? "none")")

                // After receiving OAuth callback, check session after a brief delay
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)

                    if let session = Clerk.shared.session {
                        print("🔗 [OAuth] ✅ Session established: \(session.id)")
                        ConvexService.shared.onSignInComplete()
                    } else {
                        print("🔗 [OAuth] ⚠️ No session after URL callback")
                        print("   - Clerk.shared.user: \(Clerk.shared.user != nil ? "exists" : "nil")")
                    }
                }
            }
        }
        .handlesExternalEvents(matching: ["main-window"])
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 600)

        SwiftUI.Settings {
            SettingsView(viewModel: settingsViewModel)
                .environmentObject(convexService)
        }

        // Menu bar extra
        MenuBarExtra(content: {
            Button("New Recording") {
                // This would need to be coordinated with the app state
                NotificationCenter.default.post(name: .createNewRecording, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            if let nextEvent = menuBarViewModel.nextEvent {
                Text("Next: \(nextEvent.title)")
                Text(nextEvent.startDate, style: .relative)
                Divider()
            }

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
        }, label: {
            if menuBarViewModel.showUpcomingInMenuBar, let nextEvent = menuBarViewModel.nextEvent {
                HStack {
                    Image(systemName: "bolt.fill")
                    Text(nextEvent.title)
                }
            } else {
                Image(systemName: "bolt.fill")
            }
        })
    }
}

class MenuBarViewModel: ObservableObject {
    @Published var nextEvent: EKEvent?
    @Published var showUpcomingInMenuBar: Bool = true

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Subscribe to calendar updates
        CalendarManager.shared.$nextEvent
            .receive(on: DispatchQueue.main)
            .assign(to: &$nextEvent)

        // Initial load
        showUpcomingInMenuBar = UserDefaultsManager.shared.showUpcomingInMenuBar

        // Observe UserDefaults changes reactively instead of polling
        UserDefaults.standard.publisher(for: \.showUpcomingInMenuBar)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                self?.showUpcomingInMenuBar = newValue
            }
            .store(in: &cancellables)
    }
}

extension UserDefaults {
    @objc dynamic var showUpcomingInMenuBar: Bool {
        return bool(forKey: "showUpcomingInMenuBar")
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
