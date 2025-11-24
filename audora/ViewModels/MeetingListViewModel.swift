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

        // Listen for saved meeting notifications to refresh the list
        NotificationCenter.default.publisher(for: .meetingSaved)
            .sink { [weak self] _ in
                print("🔔 Meeting saved notification received. Reloading meetings list...")
                self?.loadMeetings()
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
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, h:mm a"
        let formattedDate = dateFormatter.string(from: Date())

        // Create meeting immediately with placeholder title
        var newMeeting = Meeting(title: "Recording - \(formattedDate)")
        let meetingId = newMeeting.id // Capture ID for background task
        meetings.insert(newMeeting, at: 0)
        // _ = LocalStorageManager.shared.saveMeeting(newMeeting)

        // Get browser context asynchronously and update title later
        Task.detached(priority: .background) {
            if let context = BrowserURLHelper.getCurrentContext() {
                print("📱 Browser context: \(context)")
                await MainActor.run {
                    // Find and update the meeting in the array by ID
                    if let index = self.meetings.firstIndex(where: { $0.id == meetingId }) {
                        self.meetings[index].title = "\(context) - \(formattedDate)"
                        print("✅ Updated title to: \(self.meetings[index].title)")
                        let success = LocalStorageManager.shared.saveMeeting(self.meetings[index])
                        if success {
                            // Post notification so MeetingViewModel can update
                            NotificationCenter.default.post(name: .meetingSaved, object: self.meetings[index])
                        }
                    }
                }
            }
        }

        // Activate the app to bring it to focus
        NSApp.activate(ignoringOtherApps: true)

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
