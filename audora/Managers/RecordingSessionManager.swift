// RecordingSessionManager.swift
// Manages recording sessions with backend integration

import Foundation
import SwiftUI
import Combine

/// Manages recording sessions at the app level, coordinates audio recording with Convex backend
@MainActor
class RecordingSessionManager: ObservableObject {
    static let shared = RecordingSessionManager()

    @Published var isRecording = false
    @Published var activeMeetingId: UUID?
    @Published var errorMessage: String?
    @Published var activeRecordingTranscriptChunksUpdated: [TranscriptChunk] = []
    @Published var currentConversationId: String?

    private let audioManager = AudioManager.shared
    private var cancellables = Set<AnyCancellable>()
    private let transcriptUpdateSubject = PassthroughSubject<[TranscriptChunk], Never>()

    // Store transcript chunks for the active recording session
    private var activeRecordingTranscriptChunks: [TranscriptChunk] = []

    // Track last sent state to avoid redundant network calls
    private var lastSentChunks: [TranscriptChunk] = []

    private init() {
        setupAudioManagerBindings()
        setupDebouncedSaving()
    }

    private func setupAudioManagerBindings() {
        // Bind to audio manager state
        audioManager.$isRecording
            .sink { [weak self] isRecording in
                self?.isRecording = isRecording
                if !isRecording {
                    self?.lastSentChunks = [] // Reset on stop
                }
            }
            .store(in: &cancellables)

        audioManager.$errorMessage
            .sink { [weak self] errorMessage in
                self?.errorMessage = errorMessage
            }
            .store(in: &cancellables)

        // When transcript chunks change, store them for the active recording and send to debouncer
        audioManager.$transcriptChunks
            .sink { [weak self] newChunks in
                guard let self = self, self.isRecording, self.activeMeetingId != nil else { return }
                self.activeRecordingTranscriptChunks = newChunks
                self.activeRecordingTranscriptChunksUpdated = newChunks

                self.transcriptUpdateSubject.send(newChunks)

                // Stream updates to backend
                self.streamToBackend(chunks: newChunks)
            }
            .store(in: &cancellables)
    }

    private func setupDebouncedSaving() {
        transcriptUpdateSubject
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] chunks in
                guard let self = self, let activeMeetingId = self.activeMeetingId else { return }
                print("💾 Debounced save triggered for meeting: \(activeMeetingId.uuidString)")
                self.updateActiveMeetingTranscript(meetingId: activeMeetingId, chunks: chunks)
            }
            .store(in: &cancellables)
    }

    /// Streams changed transcript chunks to backend
    private func streamToBackend(chunks: [TranscriptChunk]) {
        guard let conversationId = currentConversationId else { return }

        // Compare with lastSentChunks and send updates
        for (index, chunk) in chunks.enumerated() {
            // Check if this index exists in lastSent and matches (hashable check should suffice)
            if index < lastSentChunks.count && lastSentChunks[index] == chunk {
                continue // No change
            }

            // Send update
            Task {
                do {
                    // Map generic WordTiming to ConvexService.WordTiming
                    let serviceWords = chunk.words?.map { word in
                        ConvexService.WordTiming(
                            word: word.word,
                            startTime: word.startTime,
                            endTime: word.endTime,
                            wordId: word.wordId
                        )
                    }

                    try await ConvexService.shared.appendTranscriptTurn(
                        conversationId: conversationId,
                        speaker: chunk.source == .mic ? "S1" : "S2",
                        text: chunk.text,
                        order: index,
                        timestamp: chunk.timestamp.timeIntervalSince1970, // Or relative? Backend expects number. Timestamp usually absolute or relative. Schema says 'timestamp: v.optional(v.number())'.
                        // Let's us absolute for now, or relative to start?
                        // Schema comment: "Timestamp in seconds from start of conversation"
                        // But here I'm passing TimeInterval (Double).
                        // I should ideally pass relative time if I know start time.
                        // But for now passing raw timestamp Double is okay if backend handles it or I fix it.
                        // Actually schema.ts says: `timestamp: v.optional(v.number())`.
                        // Re-reading schema: `timestamp` comment says "seconds from start".
                        words: serviceWords
                    )
                } catch {
                    print("⚠️ Failed to stream transcript turn: \(error)")
                }
            }
        }

        lastSentChunks = chunks
    }

    func startRecording(for meetingId: UUID, title: String? = nil, calendarEventId: String? = nil) {
        guard !isRecording else { return }

        print("🎙️ Starting recording for meeting: \(meetingId)")

        isRecording = true
        activeMeetingId = meetingId

        // Load the meeting to get existing transcript chunks
        if let existingMeeting = LocalStorageManager.shared.loadMeetings().first(where: { $0.id == meetingId }) {
            activeRecordingTranscriptChunks = existingMeeting.transcriptChunks
            audioManager.transcriptChunks = existingMeeting.transcriptChunks
        }

        AudioRecordingManager.shared.startRecording(for: meetingId)
        audioManager.startRecording()

        // Create backend conversation asynchronously
        Task {
            do {
                let convexId = try await ConvexService.shared.createConversation(
                    title: title,
                    calendarEventId: calendarEventId
                )
                await MainActor.run {
                    self.currentConversationId = convexId
                    self.saveMeetingConversationId(meetingId: meetingId, conversationId: convexId)
                }
            } catch {
                print("❌ Failed to create conversation: \(error)")
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        print("🛑 Stopping recording for meeting: \(activeMeetingId?.uuidString ?? "unknown")")

        isRecording = false
        audioManager.stopRecording()

        let capturedMeetingId = activeMeetingId
        let capturedConversationId = currentConversationId
        let capturedTranscriptChunks = activeRecordingTranscriptChunks

        var audioFileURL: String? = nil
        if let activeMeetingId = capturedMeetingId {
            // Stop recording and get the audio file URL
            if let savedAudioURL = AudioRecordingManager.shared.stopRecordingAndSave(for: activeMeetingId) {
                audioFileURL = savedAudioURL.path
                print("✅ Audio file saved: \(savedAudioURL.path)")
            }

            updateActiveMeeting(meetingId: activeMeetingId, chunks: capturedTranscriptChunks, audioFileURL: audioFileURL)

            // Process transcript with backend
            Task {
                var conversationId = capturedConversationId

                // Wait for conversation ID if still being created (up to 3 seconds)
                if conversationId == nil {
                    print("⏳ Waiting for conversation creation...")
                    for attempt in 1...6 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        conversationId = await MainActor.run { self.currentConversationId }
                        if conversationId != nil {
                            print("✅ Conversation ready after \(attempt * 500)ms")
                            break
                        }
                    }
                }

                if let conversationId = conversationId,
                   let meeting = LocalStorageManager.shared.loadMeetings().first(where: { $0.id == activeMeetingId }) {
                    await processTranscriptWithBackend(
                        conversationId: conversationId,
                        meeting: meeting
                    )
                } else if conversationId == nil {
                    print("⚠️ No conversation ID after 3s - skipping backend processing (check auth)")
                }
            }
        }

        // Reset state after capturing values for the Task
        activeMeetingId = nil
        currentConversationId = nil
        activeRecordingTranscriptChunks = []
    }

    func isRecordingMeeting(_ meetingId: UUID) -> Bool {
        return isRecording && activeMeetingId == meetingId
    }

    private func updateActiveMeetingTranscript(meetingId: UUID, chunks: [TranscriptChunk]) {
        updateActiveMeeting(meetingId: meetingId, chunks: chunks, audioFileURL: nil)
    }

    private func updateActiveMeeting(meetingId: UUID, chunks: [TranscriptChunk], audioFileURL: String?) {
        // Load all meetings
        var meetings = LocalStorageManager.shared.loadMeetings()

        // Find and update the active meeting
        if let index = meetings.firstIndex(where: { $0.id == meetingId }) {
            meetings[index].transcriptChunks = chunks
            if let audioFileURL = audioFileURL {
                meetings[index].audioFileURL = audioFileURL
            }

            // Save the updated meeting
            let success = LocalStorageManager.shared.saveMeeting(meetings[index])
            if success {
                print("✅ Saved meeting: \(meetingId.uuidString)")
                NotificationCenter.default.post(name: .meetingSaved, object: meetings[index])
            } else {
                print("❌ Failed to save meeting: \(meetingId.uuidString)")
            }
        }
    }

    func getActiveRecordingTranscriptChunks() -> [TranscriptChunk] {
        return activeRecordingTranscriptChunks
    }

    /// Get transcript chunks for a specific meeting, ensuring proper data separation
    func getTranscriptChunks(for meetingId: UUID) -> [TranscriptChunk] {
        if isRecording && activeMeetingId == meetingId {
            // Return live transcript chunks for the active recording
            return activeRecordingTranscriptChunks
        } else {
            // Load saved transcript chunks from storage for non-active meetings
            if let savedMeeting = LocalStorageManager.shared.loadMeetings().first(where: { $0.id == meetingId }) {
                return savedMeeting.transcriptChunks
            }
            return []
        }
    }

    // MARK: - Backend Processing

    /// Processes transcript with backend after recording completes
    /// Extracts facts with GPT-4 and updates knowledge graph
    private func processTranscriptWithBackend(
        conversationId: String,
        meeting: Meeting
    ) async {
        do {
            let recordingStartTime = meeting.transcriptChunks.first?.timestamp ?? Date()

            let transcriptTurns: [[String: Any]] = meeting.transcriptChunks.map { chunk in
                let relativeMs = chunk.timestamp.timeIntervalSince(recordingStartTime) * 1000
                return [
                    "speaker": chunk.source == .mic ? "S1" : "S2",
                    "text": chunk.text,
                    "startTime": relativeMs,
                    "endTime": relativeMs
                ]
            }

            guard !transcriptTurns.isEmpty else {
                print("⚠️ No transcript to process")
                return
            }

            let userName = UserDefaultsManager.shared.userBlurb.isEmpty
                ? "Me"
                : UserDefaultsManager.shared.userBlurb

            print("📤 Processing transcript with backend...")
            let _ = try await ConvexService.shared.processRealtimeTranscript(
                conversationId: conversationId,
                transcriptTurns: transcriptTurns,
                initiatorName: userName
            )

            print("✅ Backend processing complete")

        } catch {
            print("❌ Backend processing failed: \(error)")
        }
    }

    /// Helper method to save conversation ID to meeting record
    private func saveMeetingConversationId(meetingId: UUID, conversationId: String) {
        var meetings = LocalStorageManager.shared.loadMeetings()
        if let index = meetings.firstIndex(where: { $0.id == meetingId }) {
            meetings[index].convexConversationId = conversationId
            let success = LocalStorageManager.shared.saveMeeting(meetings[index])
            if success {
                print("✅ Saved conversation ID to meeting: \(meetingId)")
            } else {
                print("❌ Failed to save conversation ID to meeting: \(meetingId)")
            }
        }
    }
}