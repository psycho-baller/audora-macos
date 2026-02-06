import Foundation
import SwiftUI
import PostHog
import EventKit
import RunAnywhere

class SettingsViewModel: ObservableObject {
    @Published var settings = Settings()
    @Published var saveMessage = ""
    @Published var showingSaveMessage = false
    @Published var templates: [NoteTemplate] = []
    @Published var calendars: [EKCalendar] = []

    @Published var availableModels: [ModelInfo] = []
    @Published var downloadedModels: Set<String> = []
    
    @Published var loadedModel: String? = nil

    init() {
        loadTemplates()
        loadedModel = settings.loadedModel

        // Load calendars if authorized
        if CalendarManager.shared.authorizationStatus == .authorized {
            CalendarManager.shared.fetchCalendars()
        }

        // Subscribe to calendar updates
        CalendarManager.shared.$calendars.assign(to: &$calendars)
    }

    /// Loads the API key from keychain (only called when actually needed)
    func loadAPIKey() {
        if settings.openAIKey.isEmpty {
            settings.openAIKey = KeychainHelper.shared.getAPIKey() ?? ""
        }
    }

    func loadTemplates() {
        templates = LocalStorageManager.shared.loadTemplates()

        // Validate that the selected template still exists
        if let selectedId = settings.selectedTemplateId {
            if !templates.contains(where: { $0.id == selectedId }) {
                // Selected template was deleted, clear the selection
                settings.selectedTemplateId = nil
            }
        }

        // If no template is selected, select the first default template
        if settings.selectedTemplateId == nil {
            if let defaultTemplate = templates.first(where: { $0.title == "Standard Meeting" }) {
                settings.selectedTemplateId = defaultTemplate.id
            } else if let firstTemplate = templates.first {
                // Fallback to first available template
                settings.selectedTemplateId = firstTemplate.id
            }
        }
    }

    func fetchAvailableModels() async {
        do {
            print("Fetching available models...")
            availableModels = try await RunAnywhere.availableModels()
            
            downloadedModels = Set(
                availableModels
                    .filter { $0.localPath != nil }
                    .map(\.id)
            )
        } catch {
            print("Failed to fetch models: \(error)")
        }
    }
    
    func downloadModel(_ model: ModelInfo) async {
        do {
            print("Downloading model: \(model.id)")
            try await RunAnywhere.downloadModel(model.id)
            downloadedModels.insert(model.id)
        } catch {
            print("Failed to download model: \(error)")
        }
    }

    func loadModel(_ model: ModelInfo) async {
        do {
            print("Loading model: \(model.id)")
            try await RunAnywhere.loadModel(model.id)
            
            loadedModel = model.id
            settings.loadedModel = model.id
        } catch {
            print("Failed to load model: \(error)")
        }
    }

    func deleteModel(_ model: ModelInfo) async {
        do {
            print("Deleting model: \(model.id)")
            try await RunAnywhere.deleteModel(model.id)
            downloadedModels.remove(model.id)
            
            if loadedModel == model.id {
                loadedModel = nil
                settings.loadedModel = nil
            }
        } catch {
            print("Failed to delete model: \(error)")
        }
    }

    func saveSettings(showMessage: Bool = true) {
        // Validate that systemPrompt contains all required template placeholders
        let requiredKeys = ["meeting_title", "meeting_date", "transcript", "user_blurb", "user_notes", "template_content"]
        let missing = requiredKeys.filter { !settings.systemPrompt.contains("{{\($0)}}") }
        if !missing.isEmpty {
            if showMessage {
                saveMessage = "Cannot save settings: missing placeholders \(missing.map { "{{\($0)}}" }.joined(separator: ", ")) in system prompt"
                showingSaveMessage = true
            }
            return
        }

        // Only save API key to keychain - other values are automatically saved to UserDefaults
        // via computed properties when they're modified
        let openAISaved = KeychainHelper.shared.saveAPIKey(settings.openAIKey)

        if showMessage {
            if openAISaved {
                saveMessage = "Settings saved successfully!"
            } else {
                saveMessage = "Error saving settings"
            }

            showingSaveMessage = true

            // Hide the message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.showingSaveMessage = false
            }
        }
    }

    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        settings.hasAcceptedTerms = true
        saveSettings(showMessage: false)
        PostHogSDK.shared.capture("onboarding_completed")
    }

    func resetToDefaults() {
        settings.systemPrompt = Settings.defaultSystemPrompt()
    }

    func resetOnboarding() {
        settings.hasCompletedOnboarding = false
        saveSettings(showMessage: false)

        // Force app to restart or recreate views by posting a notification
        // This will cause ContentView to re-evaluate and show onboarding
        NotificationCenter.default.post(name: .onboardingReset, object: nil)
    }

    #if DEBUG
    func deleteAllMeetings() {
        // Delete all meetings from storage
        LocalStorageManager.shared.deleteAllMeetings()

        // Post notification to reload meetings in the UI
        NotificationCenter.default.post(name: .meetingsDeleted, object: nil)
    }
    #endif
}
