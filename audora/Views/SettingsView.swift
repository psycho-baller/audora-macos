import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showingTemplateManager = false
    @Binding var navigationPath: NavigationPath

    init(viewModel: SettingsViewModel, navigationPath: Binding<NavigationPath> = .constant(NavigationPath())) {
        self.viewModel = viewModel
        self._navigationPath = navigationPath
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // API Configuration Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("OpenAI API Key")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Stored locally and encrypted in Keychain.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    SecureField("OpenAI API Key", text: $viewModel.settings.openAIKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }

                // Meeting Reminders Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Meeting Reminders")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Get notified to record when these apps use the microphone.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Enable meeting reminders", isOn: $viewModel.settings.meetingReminderEnabled)
                        .toggleStyle(.switch)

                    if viewModel.settings.meetingReminderEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Monitored Apps")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.top, 4)

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
                                        .font(.body)
                                }
                                .toggleStyle(.switch)
                            }
                        }
                        .padding(.leading, 12)
                        .padding(.top, 4)
                    }
                }

                // Calendar Integration Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Calendar Integration")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Show upcoming meetings from your calendar.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Enable calendar integration", isOn: $viewModel.settings.calendarIntegrationEnabled)
                        .toggleStyle(.switch)
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
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Select Calendars")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.top, 4)

                            if viewModel.calendars.isEmpty {
                                Text("No calendars found or access denied.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
                                            // Refresh events when selection changes
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
                                }
                            }
                        }
                        .padding(.leading, 12)
                        .padding(.top, 4)
                    }
                }

                // Note Templates Section: only the Manage Templates button
                VStack(alignment: .leading, spacing: 8) {
                    Text("Note Templates")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Create and manage note templates")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button {
                        navigationPath.append("templates")
                    } label: {
                        Text("Manage Templates")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                // User Information Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("User Information")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Audora works best when it knows a bit about you. You should give your name, role, company, and any other relevant information.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: $viewModel.settings.userBlurb)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(8)
                        .frame(minHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )

                }

                // System Prompt Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("System Prompt")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Button {
                            viewModel.resetToDefaults()
                        } label: {
                            Text("Reset to Default")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }

                    TextEditor(text: $viewModel.settings.systemPrompt)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(8)
                        .frame(minHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )

                }

                // About Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("About")
                        .font(.headline)
                        .foregroundColor(.primary)

                    // Link to GitHub repository
                    Link("GitHub",
                         destination: URL(string: "https://github.com/psycho-baller/audora")!)
                        .foregroundColor(.blue)

                    // Link to landing page
                    Link("Landing Page",
                         destination: URL(string: "https://audora.psycho-baller.com")!)
                        .foregroundColor(.blue)

                    // Link to Privacy Policy
                    Link("Privacy Policy",
                         destination: URL(string: "https://audora.psycho-baller.com/privacy")!)
                        .foregroundColor(.blue)

                    // Link to Terms of Service
                    Link("Terms of Service",
                         destination: URL(string: "https://audora.psycho-baller.com/terms")!)
                        .foregroundColor(.blue)
                }

                // Development Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Development")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Button {
                        viewModel.resetOnboarding()
                    } label: {
                        Text("Reset Onboarding")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                // Save button
                Button {
                    viewModel.saveSettings()
                } label: {
                    Text("Save Settings")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.top)
            }
            .padding(24)
        }
        .navigationTitle("Settings")
        .frame(minWidth: 600, minHeight: 600)
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

#Preview {
    NavigationStack {
        SettingsView(viewModel: SettingsViewModel())
    }
}
