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
        static let meetingReminderEnabled = "meetingReminderEnabled"
        static let ignoredAppBundleIDs = "ignoredAppBundleIDs"
        static let calendarIntegrationEnabled = "calendarIntegrationEnabled"
        static let selectedCalendarIDs = "selectedCalendarIDs"

        // New Settings Keys
        static let showUpcomingInMenuBar = "showUpcomingInMenuBar"
        static let showEventsWithNoParticipants = "showEventsWithNoParticipants"
        static let showLiveMeetingIndicator = "showLiveMeetingIndicator"
        static let launchAtLogin = "launchAtLogin"
        static let notifyScheduledMeetings = "notifyScheduledMeetings"
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

    // MARK: - Meeting Reminders
    var meetingReminderEnabled: Bool {
        get { userDefaults.object(forKey: Keys.meetingReminderEnabled) as? Bool ?? true } // Default to true
        set { userDefaults.set(newValue, forKey: Keys.meetingReminderEnabled) }
    }

    var ignoredAppBundleIDs: Set<String> {
        get {
            if let array = userDefaults.array(forKey: Keys.ignoredAppBundleIDs) as? [String] {
                return Set(array)
            }
            return []
        }
        set {
            userDefaults.set(Array(newValue), forKey: Keys.ignoredAppBundleIDs)
        }
    }
    // MARK: - Calendar Integration
    var calendarIntegrationEnabled: Bool {
        get { userDefaults.object(forKey: Keys.calendarIntegrationEnabled) as? Bool ?? false }
        set { userDefaults.set(newValue, forKey: Keys.calendarIntegrationEnabled) }
    }

    var selectedCalendarIDs: Set<String> {
        get {
            if let array = userDefaults.array(forKey: Keys.selectedCalendarIDs) as? [String] {
                return Set(array)
            }
            return []
        }
        set {
            userDefaults.set(Array(newValue), forKey: Keys.selectedCalendarIDs)
        }
    }

    // MARK: - Advanced Settings

    var showUpcomingInMenuBar: Bool {
        get { userDefaults.object(forKey: Keys.showUpcomingInMenuBar) as? Bool ?? true }
        set { userDefaults.set(newValue, forKey: Keys.showUpcomingInMenuBar) }
    }

    var showEventsWithNoParticipants: Bool {
        get { userDefaults.object(forKey: Keys.showEventsWithNoParticipants) as? Bool ?? true }
        set { userDefaults.set(newValue, forKey: Keys.showEventsWithNoParticipants) }
    }

    var showLiveMeetingIndicator: Bool {
        get { userDefaults.object(forKey: Keys.showLiveMeetingIndicator) as? Bool ?? true }
        set { userDefaults.set(newValue, forKey: Keys.showLiveMeetingIndicator) }
    }

    var launchAtLogin: Bool {
        get { userDefaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false }
        set { userDefaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    var notifyScheduledMeetings: Bool {
        get { userDefaults.object(forKey: Keys.notifyScheduledMeetings) as? Bool ?? true }
        set { userDefaults.set(newValue, forKey: Keys.notifyScheduledMeetings) }
    }
}
