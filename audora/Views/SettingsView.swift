import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case calendar = "Calendar"
    case notifications = "Notifications"
    case writing = "Writing"
    case ai = "AI Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .calendar: return "calendar"
        case .notifications: return "bell"
        case .writing: return "text.redaction"
        case .ai: return "sparkles"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var navigationPath: NavigationPath
    @State private var selectedTab: SettingsTab = .general
    @EnvironmentObject var convexService: ConvexService
    @Environment(\.dismiss) private var dismiss

    init(viewModel: SettingsViewModel, navigationPath: Binding<NavigationPath> = .constant(NavigationPath())) {
        self.viewModel = viewModel
        self._navigationPath = navigationPath
    }

    var body: some View {
        HSplitView {
            // Sidebar
            VStack(alignment: .leading, spacing: 0) {
                // Settings Title
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                // Tab List
                VStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 16))
                                    .frame(width: 20)
                                    .foregroundColor(selectedTab == tab ? .accentColor : .secondary)

                                Text(tab.rawValue)
                                    .font(.system(size: 14))
                                    .foregroundColor(selectedTab == tab ? .primary : .secondary)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)

                Spacer()
            }
            .frame(width: 200)
            .background(Color(NSColor.controlBackgroundColor))

            // Detail View
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsView(viewModel: viewModel)
                    case .calendar:
                        CalendarSettingsView(viewModel: viewModel)
                    case .notifications:
                        NotificationSettingsView(viewModel: viewModel)
                    case .writing:
                        WritingSettingsView(viewModel: viewModel)
                    case .ai:
                        AISettingsView(viewModel: viewModel, navigationPath: $navigationPath)
                    }
                }
                .padding(24)
                .frame(maxWidth: 800, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 700, minHeight: 500)
        .onChange(of: convexService.authState) { oldValue, newValue in
            if newValue == .unauthenticated {
                // Use dismiss to close only this settings window
                dismiss()
            }
        }
        .onAppear {
            viewModel.loadTemplates()
        }
        .onDisappear {
            DispatchQueue.main.async {
                viewModel.saveSettings(showMessage: false)
            }
        }
        .alert("Settings Saved", isPresented: $viewModel.showingSaveMessage) {
            Button("OK") { }
        } message: {
            Text(viewModel.saveMessage)
        }
    }
}

// MARK: - Sub-Views

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject var convexService: ConvexService

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Preferences Section
            VStack(alignment: .leading, spacing: 16) {
                Text("Preferences")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 0) {
                    ToggleRow(
                        title: "Show the live meeting indicator",
                        description: "The meeting indicator sits on the right of your screen, and shows when you're transcribing",
                        isOn: $viewModel.settings.showLiveMeetingIndicator
                    )
                    .onChange(of: viewModel.settings.showLiveMeetingIndicator) { _, _ in
                        AudioLevelManager.shared.checkSettingAndHideIfNeeded()
                    }

                    Divider()
                        .padding(.leading, 16)

                    ToggleRow(
                        title: "Open Audora when you log in",
                        description: "Audora will open automatically when you log in",
                        isOn: $viewModel.settings.launchAtLogin
                    )
                    .onChange(of: viewModel.settings.launchAtLogin) { _, newValue in
                        LaunchAtLoginManager.shared.setLaunchAtLogin(enabled: newValue)
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }

            // About Section
            VStack(alignment: .leading, spacing: 16) {
                Text("About")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 12) {
                    LinkRow(title: "GitHub Repository", url: "https://github.com/psycho-baller/audora")
                    LinkRow(title: "Landing Page", url: "https://audora.psycho-baller.com")
                    LinkRow(title: "Privacy Policy", url: "https://audora.psycho-baller.com/privacy")
                    LinkRow(title: "Terms of Service", url: "https://audora.psycho-baller.com/terms")
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }

            // Development Section
            VStack(alignment: .leading, spacing: 16) {
                Text("Development")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sign Out")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Sign out and navigate to the Sign In screen.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Sign Out") {
                            Task {
                                await convexService.logout()
                            }
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reset Onboarding")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Clear onboarding status to go through the setup flow again.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Reset") {
                            viewModel.resetOnboarding()
                        }
                    }

                    #if DEBUG
                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Delete All Meetings")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Permanently delete all meetings. This cannot be undone.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        Spacer()
                        Button("Delete All") {
                            viewModel.deleteAllMeetings()
                        }
                        .foregroundColor(.red)
                    }
                    #endif
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
        }
    }
}

struct CalendarSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Calendar Settings")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 0) {
                ToggleRow(
                    title: "Enable Calendar Integration",
                    description: "Show upcoming meetings from your calendar in the sidebar.",
                    isOn: $viewModel.settings.calendarIntegrationEnabled
                )
                .onChange(of: viewModel.settings.calendarIntegrationEnabled) { _, newValue in
                    if newValue {
                        CalendarManager.shared.requestAccess { granted, _ in
                            if !granted {
                                DispatchQueue.main.async {
                                    viewModel.settings.calendarIntegrationEnabled = false
                                }
                            }
                        }
                    }
                }

                if viewModel.settings.calendarIntegrationEnabled {
                    Divider()
                        .padding(.leading, 16)

                    ToggleRow(
                        title: "Show upcoming meetings in menu bar",
                        description: "Display your next meeting and time until it starts in the macOS menu bar",
                        isOn: $viewModel.settings.showUpcomingInMenuBar
                    )

                    Divider()
                        .padding(.leading, 16)

                    ToggleRow(
                        title: "Show events with no participants",
                        description: "When enabled, Coming Up shows events without participants or a video link.",
                        isOn: $viewModel.settings.showEventsWithNoParticipants
                    )
                    .onChange(of: viewModel.settings.showEventsWithNoParticipants) { _, _ in
                        // Refresh events when filter changes
                        CalendarManager.shared.fetchUpcomingEvents(calendarIDs: viewModel.settings.selectedCalendarIDs)
                    }

                    Divider()
                        .padding(.leading, 16)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Select Calendars")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.top, 16)
                            .padding(.horizontal, 16)

                        if viewModel.calendars.isEmpty {
                            Text("No calendars found or access denied.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        } else {
                            ForEach(viewModel.calendars, id: \.calendarIdentifier) { calendar in
                                Toggle(isOn: Binding(
                                    get: { viewModel.settings.selectedCalendarIDs.contains(calendar.calendarIdentifier) },
                                    set: { isSelected in
                                        if isSelected {
                                            viewModel.settings.selectedCalendarIDs.insert(calendar.calendarIdentifier)
                                        } else {
                                            viewModel.settings.selectedCalendarIDs.remove(calendar.calendarIdentifier)
                                        }
                                        CalendarManager.shared.fetchUpcomingEvents(calendarIDs: viewModel.settings.selectedCalendarIDs)
                                    }
                                )) {
                                    HStack {
                                        Circle()
                                            .fill(Color(calendar.cgColor))
                                            .frame(width: 8, height: 8)
                                        Text(calendar.title)
                                    }
                                }
                                .toggleStyle(.switch)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                            .padding(.bottom, 8)
                        }
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
    }
}

struct NotificationSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Meeting Notifications")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 0) {
                ToggleRow(
                    title: "Scheduled meetings",
                    description: "Show notifications 1 minute before meetings start based on your Calendar",
                    isOn: $viewModel.settings.notifyScheduledMeetings
                )
                .onChange(of: viewModel.settings.notifyScheduledMeetings) { _, _ in
                    NotificationManager.shared.updateSchedule()
                }

                Divider()
                    .padding(.leading, 16)

                ToggleRow(
                    title: "Auto-detected meetings",
                    description: "Show notifications when a call is detected. You can mute specific apps below.",
                    isOn: $viewModel.settings.meetingReminderEnabled
                )

                if viewModel.settings.meetingReminderEnabled {
                    Divider()
                        .padding(.leading, 16)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Don't notify me when a call is detected in these apps:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.top, 16)
                            .padding(.horizontal, 16)

                        ForEach(Array(MeetingAppDetector.shared.knownMeetingApps.sorted()), id: \.self) { bundleID in
                            let appName = bundleID.components(separatedBy: ".").last ?? bundleID
                            let isIgnored = viewModel.settings.ignoredAppBundleIDs.contains(bundleID)

                            Toggle(isOn: Binding(
                                get: { !isIgnored },
                                set: { isEnabled in
                                    if isEnabled {
                                        viewModel.settings.ignoredAppBundleIDs.remove(bundleID)
                                    } else {
                                        viewModel.settings.ignoredAppBundleIDs.insert(bundleID)
                                    }
                                }
                            )) {
                                Text(appName)
                            }
                            .toggleStyle(.switch)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
    }
}

struct WritingSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var writingAwarenessManager = WritingAwarenessManager.shared
    @ObservedObject private var systemWideWritingMonitor = SystemWideWritingMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Writing Awareness")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 0) {
                ToggleRow(
                    title: "Enable writing awareness",
                    description: "Turn on the personalized vocabulary and repair workflow inside the macOS app.",
                    isOn: $viewModel.settings.writingAwarenessEnabled
                )
                .onChange(of: viewModel.settings.writingAwarenessEnabled) { _, enabled in
                    if enabled {
                        systemWideWritingMonitor.start()
                    } else {
                        systemWideWritingMonitor.stop()
                    }
                }

                Divider()
                    .padding(.leading, 16)

                ToggleRow(
                    title: "Subtle vocabulary rewards",
                    description: "Show quiet positive reinforcement when active target words appear naturally.",
                    isOn: $viewModel.settings.subtleVocabularyRewardsEnabled
                )

                Divider()
                    .padding(.leading, 16)

                ToggleRow(
                    title: "Show writing summary in menu bar",
                    description: "Add today’s preload words and progress summary to the menu bar extra.",
                    isOn: $viewModel.settings.showWritingSummaryInMenuBar
                )

                Divider()
                    .padding(.leading, 16)

                ToggleRow(
                    title: "Allow clipboard fallback",
                    description: "If the learning-word shortcut or Writing Lens selection capture fails, pull text from the clipboard instead.",
                    isOn: $viewModel.settings.writingLensClipboardFallbackEnabled
                )
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 16) {
                Text("Live Capture")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Checklist")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("1. Grant Accessibility. 2. Grant Input Monitoring. 3. Leave Live Coach running. 4. Expect overlay-only guidance in apps that do not expose safe replacement APIs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(writingAwarenessManager.isAccessibilityTrusted ? "Accessibility access is enabled." : "Accessibility access is required for selected-text capture.")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Use the Services menu item `Add to Learning Words` when apps expose it. Use `Control` + `Option` + `Command` + `L` to save the current selection from anywhere, or `Cmd` + `Shift` + `L` to open Writing Lens.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(writingAwarenessManager.isAccessibilityTrusted ? "Refresh Status" : "Grant Access") {
                        if writingAwarenessManager.isAccessibilityTrusted {
                            writingAwarenessManager.refreshPermissionTrust()
                        } else {
                            writingAwarenessManager.requestAccessibilityAccess()
                        }
                    }
                }

                Divider()

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(writingAwarenessManager.isInputMonitoringTrusted ? "Input Monitoring is enabled." : "Input Monitoring is required for live updates while you type in other apps.")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("This is the permission that lets the live coach refresh when keys are pressed outside Audora.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(writingAwarenessManager.isInputMonitoringTrusted ? "Open Settings" : "Grant Access") {
                        if writingAwarenessManager.isInputMonitoringTrusted {
                            writingAwarenessManager.openInputMonitoringSettings()
                        } else {
                            writingAwarenessManager.requestInputMonitoringAccess()
                        }
                    }
                }

                Divider()

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current focus")
                            .font(.body)
                            .fontWeight(.medium)
                        Text(writingAwarenessManager.focusPack.targetWords.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Focused field mode: \(writingAwarenessManager.liveCapability.shortLabel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(writingAwarenessManager.liveCapability.explanation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("To verify Obsidian support, place the caret inside a note, type or click once so Live Coach sees it, then return here and copy the last observed focus diagnostics.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let lastObservedExternalFocusApp = writingAwarenessManager.lastObservedExternalFocusApp {
                            Text("Last observed external focus: \(lastObservedExternalFocusApp)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Button("Copy Focus Diagnostics") {
                            writingAwarenessManager.copyFocusedElementDiagnostics()
                        }
                        Button("Add Selection to Learning Words") {
                            writingAwarenessManager.captureSelectionAsLearningTarget()
                        }
                        Button("Open Writing Lens") {
                            WritingLensWindowManager.shared.show(captureSelection: true)
                        }
                        Button(systemWideWritingMonitor.isRunning ? "Pause Live Coach" : "Resume Live Coach") {
                            if systemWideWritingMonitor.isRunning {
                                systemWideWritingMonitor.stop()
                            } else {
                                systemWideWritingMonitor.start()
                            }
                        }
                    }
                }

                if let focusDiagnosticsMessage = writingAwarenessManager.focusDiagnosticsMessage {
                    Text(focusDiagnosticsMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Inline adapters")
                        .font(.body)
                        .fontWeight(.medium)

                    ForEach(WritingAdapterKind.allCases) { adapter in
                        let status = writingAwarenessManager.adapterStatus(for: adapter)
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(adapter.title)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(status.explanation)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(status.shortLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text("Shared writing storage: \(writingAwarenessManager.sharedWritingStoragePath)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
    }
}

struct AISettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var navigationPath: NavigationPath

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("AI Settings")
                .font(.title2)
                .fontWeight(.semibold)

            // Account Info
            VStack(alignment: .leading, spacing: 16) {
                Text("Account")
                    .font(.headline)

                Text("Transcription and AI features are powered by your Audora account.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )

            // Templates
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Note Templates")
                            .font(.headline)
                        Text("Customize how your meeting notes are generated.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Manage Templates") {
                        navigationPath.append("templates")
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )

            // User Info
            VStack(alignment: .leading, spacing: 16) {
                Text("User Context")
                    .font(.headline)

                Text("Audora works best when it knows a bit about you. Add your name, role, company, etc.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                WritingAwareTextView(
                    text: $viewModel.settings.userBlurb,
                    surfaceID: "settings-user-blurb",
                    placeholder: "Your role, company, context, and what matters in meetings.",
                    contextLabel: "User Context",
                    minHeight: 100,
                    backgroundColor: .textBackgroundColor,
                    borderColor: .clear,
                    cornerRadius: 8
                )
                    .frame(minHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )

            // System Prompt
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("System Prompt")
                        .font(.headline)
                    Spacer()
                    Button("Reset to Default") {
                        viewModel.resetToDefaults()
                    }
                    .font(.caption)
                }

                WritingAwareTextView(
                    text: $viewModel.settings.systemPrompt,
                    surfaceID: "settings-system-prompt",
                    placeholder: "System prompt",
                    contextLabel: "System Prompt",
                    minHeight: 150,
                    backgroundColor: .textBackgroundColor,
                    borderColor: .clear,
                    cornerRadius: 8
                )
                    .frame(minHeight: 150)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )

            // Save Button
            Button {
                viewModel.saveSettings()
            } label: {
                Text("Save AI Settings")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Helper Views

struct LinkRow: View {
    let title: String
    let url: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Link("Visit", destination: URL(string: url)!)
                .foregroundColor(.accentColor)
        }
    }
}

struct ToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
        }
        .padding(16)
    }
}

#Preview {
    SettingsView(viewModel: SettingsViewModel())
}
