// UserDefaultsManager.swift
// Manages non-sensitive app settings using UserDefaults

import Foundation

/// Manages non-sensitive app settings using UserDefaults
class UserDefaultsManager {
    static let shared = UserDefaultsManager()
    
    private let userDefaults = UserDefaults.standard
    
    private init() {}
    
    // MARK: - Keys
    private enum Keys {
        static let userBlurb = "userBlurb"
        static let systemPrompt = "systemPrompt"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let hasAcceptedTerms = "hasAcceptedTerms"
        static let selectedTemplateId = "selectedTemplateId"
        static let autoRecordingEnabled = "autoRecordingEnabled"
        static let micFollowingEnabled = "micFollowingEnabled"
        static let modelSource = "modelSource"
        static let loadedModel = "loadedModel"
    }
    
    // MARK: - User Blurb
    var userBlurb: String {
        get { userDefaults.string(forKey: Keys.userBlurb) ?? "" }
        set { userDefaults.set(newValue, forKey: Keys.userBlurb) }
    }
    
    // MARK: - System Prompt
    var systemPrompt: String {
        get { 
            let stored = userDefaults.string(forKey: Keys.systemPrompt)
            return stored?.isEmpty == false ? stored! : Settings.defaultSystemPrompt()
        }
        set { userDefaults.set(newValue, forKey: Keys.systemPrompt) }
    }
    
    // MARK: - Onboarding Status
    var hasCompletedOnboarding: Bool {
        get { userDefaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { userDefaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }
    
    // MARK: - Terms Acceptance
    var hasAcceptedTerms: Bool {
        get { userDefaults.bool(forKey: Keys.hasAcceptedTerms) }
        set { userDefaults.set(newValue, forKey: Keys.hasAcceptedTerms) }
    }
    
    // MARK: - Selected Template ID
    var selectedTemplateId: UUID? {
        get { 
            guard let uuidString = userDefaults.string(forKey: Keys.selectedTemplateId) else { return nil }
            return UUID(uuidString: uuidString)
        }
        set { 
            if let uuid = newValue {
                userDefaults.set(uuid.uuidString, forKey: Keys.selectedTemplateId)
            } else {
                userDefaults.removeObject(forKey: Keys.selectedTemplateId)
            }
        }
    }
    
    // MARK: - Auto-Recording
    var autoRecordingEnabled: Bool {
        get { userDefaults.bool(forKey: Keys.autoRecordingEnabled) }
        set { userDefaults.set(newValue, forKey: Keys.autoRecordingEnabled) }
    }
    
    // MARK: - Mic Following
    var micFollowingEnabled: Bool {
        get { userDefaults.bool(forKey: Keys.micFollowingEnabled) }
        set { userDefaults.set(newValue, forKey: Keys.micFollowingEnabled) }
    }
    
    var modelSource: ModelSource {
        get {
            guard
                let raw = UserDefaults.standard.string(forKey: Keys.modelSource),
                let source = ModelSource(rawValue: raw)
            else {
                return .openAI // safe default for existing users
            }
            return source
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.modelSource)
        }
    }
    
    var loadedModel: String? {
        get { userDefaults.string(forKey: Keys.loadedModel) }
        set {
            if let value = newValue {
                userDefaults.set(value, forKey: Keys.loadedModel)
            } else {
                userDefaults.removeObject(forKey: Keys.loadedModel)
            }
        }
    }
}
