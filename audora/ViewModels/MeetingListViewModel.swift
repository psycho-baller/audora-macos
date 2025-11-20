import Foundation
import SwiftUI
import Combine
import PostHog
import AppKit

@MainActor
class MeetingListViewModel: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText: String = ""
    
    private var cancellables = Set<AnyCancellable>()
    private let recordingSessionManager = RecordingSessionManager.shared
    
    // Computed property to filter meetings based on search text
    var filteredMeetings: [Meeting] {
        guard !searchText.isEmpty else { return meetings }
        
        return meetings.filter { meeting in
            // Search in title
            meeting.title.localizedCaseInsensitiveContains(searchText) ||
            // Search in user notes
            meeting.userNotes.localizedCaseInsensitiveContains(searchText) ||
            // Search in generated notes
            meeting.generatedNotes.localizedCaseInsensitiveContains(searchText) ||
            // Search in transcript text
            meeting.transcriptChunks.contains { chunk in
                chunk.text.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    init() {
        loadMeetings()
        
        // Listen for saved meeting notifications to update the specific meeting in the list
        NotificationCenter.default.publisher(for: .meetingSaved)
            .sink { [weak self] notification in
                guard let self = self,
                      let savedMeeting = notification.object as? Meeting else { return }
                
                // Update the specific meeting in the list without triggering a full reload
                if let index = self.meetings.firstIndex(where: { $0.id == savedMeeting.id }) {
                    print("🔄 Updating meeting in list: \(savedMeeting.id)")
                    self.meetings[index] = savedMeeting
                } else {
                    // If meeting not in list, it might be new - reload to be safe
                    print("🔔 Meeting not found in list, reloading...")
                    self.loadMeetings()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .meetingDeleted)
            .sink { [weak self] _ in
                print("🔔 Meeting deleted notification received. Reloading meetings list...")
                self?.loadMeetings()
            }
            .store(in: &cancellables)
        
        // Listen for transcription session save requests (from mic following)
        NotificationCenter.default.publisher(for: NSNotification.Name("SaveTranscriptionSession"))
            .sink { [weak self] notification in
                if let session = notification.userInfo?["session"] as? TranscriptionSession {
                    print("🔔 Transcription session save request received")
                    self?.saveTranscriptionSession(session)
                }
            }
            .store(in: &cancellables)
    }
    
    func loadMeetings() {
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.main.async { [weak self] in
            let loadedMeetings = LocalStorageManager.shared.loadMeetings()
            print("📋 Loaded \(loadedMeetings.count) meetings")
            self?.meetings = loadedMeetings
            self?.isLoading = false
        }
    }
    
    func deleteMeeting(_ meeting: Meeting) {
        meetings.removeAll { $0.id == meeting.id }
        _ = LocalStorageManager.shared.deleteMeeting(meeting)
    }
    
    func createNewMeeting() -> Meeting {
        let context = BrowserURLHelper.getCurrentContext()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, h:mm a"
        let formattedDate = dateFormatter.string(from: Date())
        
        let title: String
        if let contextName = context {
            title = "\(contextName) - \(formattedDate)"
        } else {
            title = "Recording - \(formattedDate)"
        }
        
        let newMeeting = Meeting(title: title)
        meetings.insert(newMeeting, at: 0)
        _ = LocalStorageManager.shared.saveMeeting(newMeeting)
        // Track meeting creation event
        PostHogSDK.shared.capture("meeting_created")
        return newMeeting
    }
    
    /// Save a transcription session (e.g., from mic following mode)
    func saveTranscriptionSession(_ session: TranscriptionSession) {
        print("💾 Saving transcription session: \(session.title)")
        
        // Add to the list
        meetings.insert(session, at: 0)
        
        // Persist to disk
        _ = LocalStorageManager.shared.saveMeeting(session)
        
        // Track the event
        PostHogSDK.shared.capture("transcription_session_saved", properties: [
            "source": session.source.rawValue,
            "chunk_count": session.transcriptChunks.count
        ])
        
        print("✅ Transcription session saved successfully")
    }
} 