# System Flow Analysis: From Meeting to Real-time Feedback

This document outlines the technical flow of the application, tracing the path from detecting a meeting to displaying real-time feedback.

## 1. Meeting Detection
**Entry Point:** `Managers/MeetingAppDetector.swift`

*   **Mechanism:** The app runs a background monitor that checks two conditions:
    1.  **Microphone Activity**: `MicActivityMonitor` detects if the microphone is in use.
    2.  **Frontmost App**: `FrontmostAppMonitor` checks the currently active application.
*   **Trigger:** If the microphone is active AND the frontmost app is a known meeting tool (Zoom, Teams, Meet, Slack, etc.), a "Meeting" is detected.
*   **User Interaction:** A `MeetingReminderWindowController` overlay appears, prompting the user to "Record", "Ignore", or open "Settings".
*   **Action:** Clicking "Record" posts a `.createNewRecording` notification.

## 2. Starting the Session
**Coordinator:** `Managers/RecordingSessionManager.swift`

*   **Initialization:** Listens for `.createNewRecording` or manual start.
*   **Session Creation:** Calls `startRecording(for: meetingId)`.
*   **State Management:** Sets `isRecording = true` and manages the active `Meeting` object.

## 3. Audio Capture
**Core Engine:** `Managers/AudioManager.swift`

*   **Engine Setup:** Initializes an `AVAudioEngine`.
*   **Dual Capture:**
    *   **Microphone:** Installs a tap on the input node (`installTap`).
    *   **System Audio:** Uses `ProcessTap` to capture audio from specific running applications (Zoom, Teams, etc.) identified by `AudioProcessController`.
*   **Local Recording:**
    *   `AudioRecordingManager.swift` writes raw audio buffers to disk (`mic_*.caf` and `system_*.caf`) immediately.

## 4. Real-time Processing (The "Feedback" Loop)
**Provider:** Speechmatics API (`wss://eu2.rt.speechmatics.com/v2/en`)

*   **Connection:** `AudioManager` establishes a WebSocket connection to Speechmatics using JWT obtained from backend via `ConvexService.getSpeechmaticsJWT()`.
*   **Streaming:** Audio buffers (Mic & System) are converted to 24kHz PCM format and sent via WebSocket messages.
    *   Microphone audio: Captured via `AVAudioEngine` input node tap
    *   System audio: Captured via `ProcessTap` from meeting applications
    *   Both streams are resampled to 24kHz PCM before transmission
*   **Response Parsing:** `AudioManager.receiveMessage` listens for Speechmatics events:
    *   `AddTranscript` (with `metadata.transcript`): Partial/interim and finalized transcription updates
    *   `EndOfTranscript`: Marks transcription session completion
    *   Includes speaker labels for diarization (S1, S2)
*   **Feedback:** The "Real-time Feedback" is strictly **Live Transcription with Speaker Diarization**. No other AI analysis (sentiment, fact extraction, coaching, etc.) happens in this real-time loop - those operations occur in backend processing after recording stops (see section 4.5).

## 4.5 Backend Processing (After Recording)
**Provider:** Convex Backend (`processRealtimeTranscript` action)

*   **Trigger:** Called automatically when recording stops via `RecordingSessionManager.stopRecording()`
*   **Data Format:**
    *   **Mac App:** Serializes transcript array to JSON string (`transcriptTurnsJson`) to bypass Swift type system limitations (see `docs/TRANSCRIPT_PROCESSING.md`)
    *   **Web App:** Sends transcript array directly (`transcriptTurns`)
    *   **Backend:** Parses JSON string if provided (Mac), otherwise uses array (Web) - maintains backward compatibility
*   **Timestamp Format:** Relative milliseconds from recording start (not Unix epoch)
*   **Processing:**
    *   GPT-4o extracts key facts from conversation (S1_facts, S2_facts)
    *   Generates conversation summary
    *   Saves transcript to `transcriptTurns` table
    *   Saves facts to `conversationFacts` table
    *   Updates `conversations` table (summary, status, endedAt)
    *   Updates Zep knowledge graph with entities and relationships
*   **Benefits:** 
    *   Cross-platform data access (Mac and Web share same database)
    *   AI-powered insights without requiring user API keys
    *   Centralized processing logic
    *   Knowledge graph integration for long-term context

## 5. UI Updates
**Display:** `ViewModels/MeetingViewModel.swift` & `Views/MeetingView.swift`

*   **Data Binding:** `RecordingSessionManager` observes `AudioManager.transcriptChunks` and updates the active `Meeting` model.
*   **UI Refresh:** `MeetingViewModel` sees the updated `Meeting` and publishes changes.
*   **User View:** The user sees the transcript appear in real-time, separated by "Me" (Mic) and "Them" (System).

## 6. Post-Meeting Processing (After Stop)
*   **Audio Save:** `AudioRecordingManager` combines the `.caf` segments into a final `.m4a` file.
*   **Analytics:** `MeetingViewModel.calculateAnalytics()` analyzes the full transcript for Clarity, Conciseness, and Confidence scores.
*   **Audio Storage (Convex):**
    *   **Trigger:** Happens inside `generateNotes()` in `MeetingViewModel`.
    *   **Action:** `ConvexService.shared.uploadAudioFile` uploads the final `.m4a` recording to Convex's Object Storage.
    *   **Purpose:** Secure cloud backup of the audio for future reference or potentially advanced processing later.
*   **Enhanced Notes:** User can manually trigger "Pro Notes" generation (or auto-trigger), which uses `NotesGenerator.swift`.
    *   **Upload:** Audio file acts as a backup/reference (uploaded via `ConvexService.swift`).
    *   **Generation:** `NotesGenerator` calls OpenAI Chat Completion (GPT-4) with the full transcript to generate organized notes based on a template.

## Summary Diagram
```mermaid
graph TD
    A[MeetingAppDetector] -->|Mic + App Detected| B(User Promoted to Record)
    B -->|User Clicks Record| C[RecordingSessionManager]
    C -->|Start| D[AudioManager]
    C -->|Create Conversation| CS[ConvexService]
    CS -->|Authenticate| CB[Convex Backend]

    subgraph Audio Capture
        D -->|Install Tap| E[Mic Input]
        D -->|ProcessTap| F[System Audio]
        E -->|Write File| G[Local Disk .caf]
        F -->|Write File| G
    end

    subgraph Real-time Loop
        E -->|Send Audio| H[Speechmatics API]
        F -->|Send Audio| H
        H -->|JSON Events| I[AudioManager Parser]
        I -->|Update chunks| J[RecordingSessionManager]
        J -->|Update Model| K[MeetingViewModel]
        K -->|Bind| L[UI / User View]
    end

    subgraph Post-Processing
        C -->|Stop| M[AudioRecordingManager]
        M -->|Combine| N[Final .m4a]
        C -->|Process Transcript| CB
        CB -->|GPT-4 Facts| ZEP[Zep Knowledge Graph]
        K -->|Trigger| O[NotesGenerator]
        O -->|GPT-4 via Backend| P[Enhanced Notes]
    end
```
