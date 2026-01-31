import Foundation
import SwiftUI
import Combine

/// Manages recording sessions at the app level to persist across navigation
@MainActor
class RecordingSessionManager: ObservableObject {
    static let shared = RecordingSessionManager()
    
    @Published var isRecording = false
    @Published var activeMeetingId: UUID?
    @Published var errorMessage: String?
    @Published var activeRecordingTranscriptChunksUpdated: [TranscriptChunk] = []
    
    // Dynamic audio manager based on model source
    private var currentAudioManager: any AudioManagerProtocol {
        switch UserDefaultsManager.shared.modelSource {
        case .openAI:
            return AudioManager.shared
        case .local:
            return LocalAudioManager.shared
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    private let transcriptUpdateSubject = PassthroughSubject<[TranscriptChunk], Never>()
    
    // Store transcript chunks for the active recording session
    private var activeRecordingTranscriptChunks: [TranscriptChunk] = []
    
    private init() {
        setupAudioManagerBindings()
        setupDebouncedSaving()
        
        // Listen for model source changes to rebind audio manager
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleModelSourceChange),
            name: .modelSourceChanged,
            object: nil
        )
    }
    
    @objc private func handleModelSourceChange() {
        print("🔄 Model source changed, rebinding audio manager...")
        
        // Stop any active recording
        if isRecording {
            stopRecording()
        }
        
        // Clear existing bindings
        cancellables.removeAll()
        
        // Re-setup bindings with new audio manager
        setupAudioManagerBindings()
        setupDebouncedSaving()
    }
    
    private func setupAudioManagerBindings() {
        let audioManager = currentAudioManager
        
        // Bind to audio manager state
        audioManager.isRecordingPublisher
            .sink { [weak self] isRecording in
                self?.isRecording = isRecording
            }
            .store(in: &cancellables)
        
        audioManager.errorMessagePublisher
            .sink { [weak self] errorMessage in
                self?.errorMessage = errorMessage
            }
            .store(in: &cancellables)
        
        // When transcript chunks change, store them for the active recording and send to debouncer
        audioManager.transcriptChunksPublisher
            .sink { [weak self] newChunks in
                guard let self = self, self.isRecording, self.activeMeetingId != nil else { return }
                self.activeRecordingTranscriptChunks = newChunks
                self.activeRecordingTranscriptChunksUpdated = newChunks
                
                self.transcriptUpdateSubject.send(newChunks)
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
    
    func startRecording(for meetingId: UUID) {
        let modelSource = UserDefaultsManager.shared.modelSource
        print("🎙️ Starting recording for meeting: \(meetingId) using \(modelSource.rawValue)")
        
        let audioManager = currentAudioManager
        
        // Load the meeting to get existing transcript chunks
        if let existingMeeting = LocalStorageManager.shared.loadMeetings().first(where: { $0.id == meetingId }) {
            activeRecordingTranscriptChunks = existingMeeting.transcriptChunks
            // Seed the audio manager with existing chunks
            audioManager.transcriptChunks = existingMeeting.transcriptChunks
        }
        
        // Start audio recording
        AudioRecordingManager.shared.startRecording(for: meetingId)
        
        activeMeetingId = meetingId
        audioManager.startRecording()
    }
    
    func stopRecording() {
        print("🛑 Stopping recording for meeting: \(activeMeetingId?.uuidString ?? "unknown")")
        
        currentAudioManager.stopRecording()
        
        // Save audio file and update meeting
        var audioFileURL: String? = nil
        if let activeMeetingId = activeMeetingId {
            // Stop recording and get the audio file URL
            if let savedAudioURL = AudioRecordingManager.shared.stopRecordingAndSave(for: activeMeetingId) {
                audioFileURL = savedAudioURL.path
                print("✅ Audio file saved: \(savedAudioURL.path)")
            }
            
            // Update meeting with transcript and audio file URL
            updateActiveMeeting(meetingId: activeMeetingId, chunks: activeRecordingTranscriptChunks, audioFileURL: audioFileURL)
        }
        
        activeMeetingId = nil
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
}

// MARK: - Audio Manager Protocol
/// Protocol that both AudioManager and LocalAudioManager conform to
protocol AudioManagerProtocol: AnyObject {
    var transcriptChunks: [TranscriptChunk] { get set }
    var isRecordingPublisher: AnyPublisher<Bool, Never> { get }
    var errorMessagePublisher: AnyPublisher<String?, Never> { get }
    var transcriptChunksPublisher: AnyPublisher<[TranscriptChunk], Never> { get }
    
    func startRecording()
    func stopRecording()
}

// MARK: - AudioManager Extension
extension AudioManager: AudioManagerProtocol {
    var isRecordingPublisher: AnyPublisher<Bool, Never> {
        $isRecording.eraseToAnyPublisher()
    }
    
    var errorMessagePublisher: AnyPublisher<String?, Never> {
        $errorMessage.eraseToAnyPublisher()
    }
    
    var transcriptChunksPublisher: AnyPublisher<[TranscriptChunk], Never> {
        $transcriptChunks.eraseToAnyPublisher()
    }
}

// MARK: - LocalAudioManager Extension
extension LocalAudioManager: AudioManagerProtocol {
    var isRecordingPublisher: AnyPublisher<Bool, Never> {
        $isRecording.eraseToAnyPublisher()
    }
    
    var errorMessagePublisher: AnyPublisher<String?, Never> {
        $errorMessage.eraseToAnyPublisher()
    }
    
    var transcriptChunksPublisher: AnyPublisher<[TranscriptChunk], Never> {
        $transcriptChunks.eraseToAnyPublisher()
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let modelSourceChanged = Notification.Name("modelSourceChanged")
}