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

                // Auto-Recording Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Auto-Recording")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Automatically start and stop recording when other apps use audio (e.g., Zoom calls).")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Enable auto-recording", isOn: $viewModel.settings.autoRecordingEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: viewModel.settings.autoRecordingEnabled) { oldValue, newValue in
                            if newValue {
                                AudioManager.shared.enableAutoRecording()
                            } else {
                                AudioManager.shared.disableAutoRecording()
                            }
                        }

                    if viewModel.settings.autoRecordingEnabled {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Recording starts when other apps use audio, stops 3s after they stop")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }

                // Mic Following Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mic Following")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Record microphone only when other apps are using it. Does NOT record system audio - only captures your microphone input when detected.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Enable mic following", isOn: $viewModel.settings.micFollowingEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: viewModel.settings.micFollowingEnabled) { oldValue, newValue in
                            if newValue {
                                AudioManager.shared.enableMicFollowing()
                            } else {
                                AudioManager.shared.disableMicFollowing()
                            }
                        }

                    if viewModel.settings.micFollowingEnabled {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Microphone-only. Stops after 3s of silence when no other apps using mic.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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