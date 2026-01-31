import Foundation
import SwiftUI
import Combine
import PostHog

// Add notification name for meeting saved events
extension Notification.Name {
    static let meetingSaved = Notification.Name("MeetingSaved")
    static let meetingDeleted = Notification.Name("MeetingDeleted")
    static let createNewRecording = Notification.Name("CreateNewRecording")
    static let openSettings = Notification.Name("OpenSettings")
    static let onboardingReset = Notification.Name("OnboardingReset")
    static let meetingsDeleted = Notification.Name("com.audora.notification.meetingsDeleted")
}

enum MeetingViewTab: String, CaseIterable {
    case analytics = "Analytics"
    case transcript = "Transcript"
    case myNotes = "My Notes"
    case enhancedNotes = "Enhanced Notes"
}



@MainActor
class MeetingViewModel: ObservableObject {
    @Published var meeting: Meeting
    @Published var isGeneratingNotes = false
    @Published var errorMessage: String?
    @Published private var recordingStateChanged = false // Trigger SwiftUI updates
    @Published var isValidatingKey = false // Indicates API key validation in progress
    @Published var isStartingRecording = false // Indicates recording start in progress
    
    // Computed property to determine if Generate button should animate
    var shouldAnimateGenerateButton: Bool {
        let generateButtonEnabled = !meeting.transcript.isEmpty && !isGeneratingNotes && !isRecording && !isStartingRecording
        let noEnhancedNotesYet = meeting.generatedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return generateButtonEnabled && noEnhancedNotesYet
    }
    
    // Computed property to determine if Transcribe button should animate
    var shouldAnimateTranscribeButton: Bool {
        return !isRecording && meeting.transcriptChunks.isEmpty && !isStartingRecording
    }
    
    // Computed property that always uses the direct RecordingSessionManager check
    var isRecording: Bool {
        return recordingSessionManager.isRecordingMeeting(meeting.id)
    }
    @Published var selectedTab: MeetingViewTab = .analytics  // Default to analytics tab
    
    @Published var isDeleted = false
    @Published var templates: [NoteTemplate] = []
    @Published var selectedTemplateId: UUID?
    
    private let recordingSessionManager = RecordingSessionManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var isNewMeeting = false
    
    // Computed property to check if meeting is empty
    var isEmpty: Bool {
        return meeting.transcriptChunks.isEmpty &&
        meeting.userNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        meeting.generatedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        meeting.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    init(meeting: Meeting = Meeting()) {
        // Load the latest version of the meeting from storage if it exists
        if let savedMeeting = LocalStorageManager.shared.loadMeetings().first(where: { $0.id == meeting.id }) {
            print("🔄 Loading latest version of meeting: \(meeting.id)")
            print("   audioFileURL: \(savedMeeting.audioFileURL ?? "nil")")
            if let audioPath = savedMeeting.audioFileURL {
                let fileExists = FileManager.default.fileExists(atPath: audioPath)
                print("   File exists: \(fileExists)")
            }
            self.meeting = savedMeeting
        } else {
            print("🆕 Using provided meeting: \(meeting.id)")
            self.meeting = meeting
        }
        
        
        
        // Detect if this is a new meeting based on content, not storage existence
        isNewMeeting = isEmpty
        
        // Set initial tab based on content availability
        if self.meeting.analytics != nil {
            selectedTab = .analytics
        } else if !self.meeting.generatedNotes.isEmpty {
            selectedTab = .enhancedNotes
        } else if !self.meeting.transcriptChunks.isEmpty {
            selectedTab = .transcript
        } else {
            selectedTab = .analytics
        }
        
        // Load templates and selected template
        loadTemplates()
        // Observe template selection: save to meeting and regenerate notes on changes (skip initial)
        $selectedTemplateId
            .dropFirst()
            .sink { [weak self] newTemplateId in
                guard let self = self else { return }
                self.meeting.templateId = newTemplateId
                Task {
                    await self.generateNotes()
                }
            }
            .store(in: &cancellables)
        
        // Trigger SwiftUI updates when recording state changes
        Publishers.CombineLatest(recordingSessionManager.$isRecording, recordingSessionManager.$activeMeetingId)
            .sink { [weak self] (isRecording, activeMeetingId) in
                guard let self = self else { return }
                
                // If recording started for this meeting, end starting state
                if isRecording && activeMeetingId == self.meeting.id {
                    self.isStartingRecording = false
                }
                // Toggle the dummy property to trigger SwiftUI re-render
                self.recordingStateChanged.toggle()
            }
            .store(in: &cancellables)
        
        // Update error message when recording session manager encounters errors
        recordingSessionManager.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] errorMessage in
                // Suppress non-critical, self-healing errors that should not distract the user
                let lowercased = errorMessage.lowercased()
                if errorMessage == ErrorMessage.sessionExpired || lowercased.contains("socket is not connected") {
                    print("ℹ️ Suppressed non-critical error: \(errorMessage)")
                    return
                }
                self?.errorMessage = errorMessage
                print("🚨 Recording Session Manager Error: \(errorMessage)")
            }
            .store(in: &cancellables)
        
        // If currently recording this meeting, load live transcript chunks
        if recordingSessionManager.isRecordingMeeting(meeting.id) {
            self.meeting.transcriptChunks = recordingSessionManager.getTranscriptChunks(for: meeting.id)
        }
        
        // Listen to real-time transcript updates for this meeting if it's being recorded
        recordingSessionManager.$activeRecordingTranscriptChunksUpdated
            .dropFirst()
            .sink { [weak self] updatedChunks in
                guard let self = self else { return }
                // Only update if this meeting is the active recording
                if recordingSessionManager.isRecordingMeeting(self.meeting.id) {
                    self.meeting.transcriptChunks = updatedChunks
                }
            }
            .store(in: &cancellables)

        // Listen for meeting saved notifications to update audioFileURL (e.g., when recording stops)
        NotificationCenter.default.publisher(for: .meetingSaved)
            .compactMap { $0.object as? Meeting }
            .filter { [weak self] savedMeeting in
                // Only process if it's for this meeting
                savedMeeting.id == self?.meeting.id
            }
            .sink { [weak self] savedMeeting in
                guard let self = self else { return }
                // Update audioFileURL if it was added/updated
                if savedMeeting.audioFileURL != self.meeting.audioFileURL {
                    print("🔄 Updating audioFileURL in MeetingViewModel")
                    print("   Old: \(self.meeting.audioFileURL ?? "nil")")
                    print("   New: \(savedMeeting.audioFileURL ?? "nil")")

                    if let newPath = savedMeeting.audioFileURL {
                        let fileExists = FileManager.default.fileExists(atPath: newPath)
                        print("   File exists: \(fileExists)")
                    }

                    self.meeting.audioFileURL = savedMeeting.audioFileURL
                }
            }
            .store(in: &cancellables)

        // Auto-save when meeting properties change
        $meeting
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] meeting in
                print("🔄 Auto-saving meeting: \(meeting.id) - title: '\(meeting.title)', notes: '\(meeting.userNotes.prefix(50))...'")
                self?.saveMeeting()
            }
            .store(in: &cancellables)
        
        
    }
    
    
    var recordingButtonText: String {
        // Use the same computed isRecording property for perfect consistency
        if isRecording {
            return "Stop"
        } else {
            // Check if there's existing transcript content
            return meeting.transcriptChunks.isEmpty ? "Transcribe" : "Resume"
        }
    }
    
    func toggleRecording() {
        // Prevent duplicate actions while validating API key or starting recording
        if isValidatingKey || isStartingRecording { return }
        // Use the same computed isRecording property for perfect consistency
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        let modelSource = UserDefaultsManager.shared.modelSource
        print("🎯 Starting recording with model: \(modelSource.rawValue)")
        
        // If using local model, skip authentication check
        if modelSource == .local {
            isStartingRecording = true
            recordingSessionManager.startRecording(for: meeting.id)
            return
        }
        
        // Check authentication before starting recording
        guard case .authenticated = ConvexService.shared.authState else {
            errorMessage = "Please sign in to start recording."
            return
        }

        isStartingRecording = true
        recordingSessionManager.startRecording(for: meeting.id)
    }

    func stopRecording() {
        recordingSessionManager.stopRecording()

        // Calculate analytics after stopping recording
        calculateAnalytics()

        saveMeeting()
    }

    /// Calculate speech analytics from transcript chunks
    private func calculateAnalytics() {
        guard !meeting.transcriptChunks.isEmpty else {
            print("⚠️ No transcript chunks to analyze")
            return
        }

        // Calculate duration in minutes
        let chunks = meeting.transcriptChunks
        guard let firstChunk = chunks.first, let lastChunk = chunks.last else {
            return
        }

        let durationSeconds = lastChunk.timestamp.timeIntervalSince(firstChunk.timestamp)
        let durationMinutes = max(durationSeconds / 60.0, 0.1) // Minimum 0.1 minutes

        print("📊 Calculating analytics for \(chunks.count) chunks, duration: \(String(format: "%.1f", durationMinutes)) min")

        // Calculate analytics
        if let analytics = AnalyticsCalculator.analyzeTranscript(
            chunks: chunks,
            durationMinutes: durationMinutes
        ) {
            meeting.analytics = analytics
            print("✅ Analytics calculated successfully")
            print("   Clarity: \(analytics.scores.clarity)")
            print("   Conciseness: \(analytics.scores.conciseness)")
            print("   Confidence: \(analytics.scores.confidence)")

            // Switch to analytics tab to show results
            selectedTab = .analytics
        } else {
            print("⚠️ Failed to calculate analytics")
        }
    }
    
    func loadTemplates() {
        templates = LocalStorageManager.shared.loadTemplates()
        
        // Load per-meeting template or default to Standard Meeting
        if let meetingTemplateId = meeting.templateId {
            selectedTemplateId = meetingTemplateId
        } else if let defaultTemplate = templates.first(where: { $0.title == "Standard Meeting" }) {
            selectedTemplateId = defaultTemplate.id
        }
    }
    
    func generateNotes() async {
        isGeneratingNotes = true
        errorMessage = nil
        
        // Clear existing notes for streaming
        meeting.generatedNotes = ""

        // Upload audio file to Convex if available
        if let audioFileURLString = meeting.audioFileURL {
            let audioFileURL = URL(fileURLWithPath: audioFileURLString)

            // Check if file exists
            if FileManager.default.fileExists(atPath: audioFileURL.path) {
                do {
                    print("📤 Uploading audio file to Convex before generating notes...")
                    let storageId = try await ConvexService.shared.uploadAudioFile(
                        audioFileURL: audioFileURL,
                        meetingId: meeting.id
                    )

                    if let storageId = storageId {
                        print("✅ Audio file uploaded to Convex. Storage ID: \(storageId)")
                        // TODO: Store storageId in meeting when database schema is updated
                        // For now, we just log it
                    } else {
                        print("⚠️ Audio file uploaded but no storage ID returned")
                    }
                } catch {
                    // Log error but don't block note generation if upload fails
                    print("⚠️ Failed to upload audio file to Convex: \(error.localizedDescription)")
                    // Continue with note generation even if upload fails
                }
            } else {
                print("⚠️ Audio file path exists but file not found: \(audioFileURLString)")
            }
        } else {
            print("ℹ️ No audio file available for this meeting, skipping upload")
        }

        // Load settings for generation
        let userBlurb = UserDefaultsManager.shared.userBlurb
        let systemPrompt = UserDefaultsManager.shared.systemPrompt
        
        // Use streaming generation
        let stream = NotesGenerator.shared.generateNotesStream(
            meeting: meeting,
            userBlurb: userBlurb,
            systemPrompt: systemPrompt,
            templateId: selectedTemplateId
        )
        
        var hasError = false
        for await result in stream {
            switch result {
            case .content(let chunk):
                meeting.generatedNotes += chunk
            case .error(let error):
                errorMessage = error
                hasError = true
                print("🚨 Note Generation Error: \(error)")
                break
            }
        }
        
        // Only save if there was no error
        if !hasError {
            saveMeeting()
        }
        
        isGeneratingNotes = false
    }
    
    func saveMeeting() {
        if isDeleted { return }
        print("💾 Saving meeting: \(meeting.id)")
        let success = LocalStorageManager.shared.saveMeeting(meeting)
        print("💾 Save result: \(success ? "SUCCESS" : "FAILED")")
        if success {
            NotificationCenter.default.post(name: .meetingSaved, object: meeting)
        }
    }
    
    func copyCurrentTabContent() {
        NSPasteboard.general.clearContents()
        
        let content: String
        switch selectedTab {
        case .myNotes:
            content = meeting.userNotes
        case .transcript:
            content = meeting.formattedTranscript
        case .enhancedNotes:
            var enhancedContent = ""
            
            // Add title as h1 header if title is set
            if !meeting.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                enhancedContent += "# \(meeting.title)\n\n"
            }
            
            // Add the generated notes
            enhancedContent += meeting.generatedNotes
            
            // Add attribution footer
            if !enhancedContent.isEmpty {
                enhancedContent += "\n\n---\n\nNotes generated using [audora](https://audora.psycho-baller.com), the free, open source AI notetaker."
            }
            
            content = enhancedContent
        case .analytics:
            content = "analytics"
        }
        
        NSPasteboard.general.setString(content, forType: .string)
    }
    
    func deleteMeeting() {
        // If this meeting is currently being recorded, stop the recording first
        if recordingSessionManager.isRecordingMeeting(meeting.id) {
            print("🛑 Stopping recording for meeting being deleted: \(meeting.id)")
            recordingSessionManager.stopRecording()
        }
        
        let success = LocalStorageManager.shared.deleteMeeting(meeting)
        if success {
            isDeleted = true
            NotificationCenter.default.post(name: .meetingDeleted, object: meeting)
        }
    }
    
    func deleteIfEmpty() {
        if isEmpty && !isRecording {
            print("🗑️ Auto-deleting empty meeting")
            deleteMeeting()
        } else {
            saveMeeting()
        }
    }
}
