import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case calendar = "Calendar"
    case notifications = "Notifications"
    case ai = "AI Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .calendar: return "calendar"
        case .notifications: return "bell"
        case .ai: return "sparkles"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var navigationPath: NavigationPath
    @State private var selectedTab: SettingsTab = .general

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
        .onAppear {
            viewModel.loadTemplates()
            viewModel.loadAPIKey()
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

struct AISettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var navigationPath: NavigationPath

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("AI Settings")
                .font(.title2)
                .fontWeight(.semibold)

            // API Key
            VStack(alignment: .leading, spacing: 16) {
                Text("OpenAI Configuration")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    SecureField("OpenAI API Key", text: $viewModel.settings.openAIKey)
                        .textFieldStyle(.roundedBorder)

                    Text("Stored locally and encrypted in Keychain.")
                        .font(.caption)
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

                TextEditor(text: $viewModel.settings.userBlurb)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
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

                TextEditor(text: $viewModel.settings.systemPrompt)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
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
