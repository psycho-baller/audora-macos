// ConvexService.swift
// Handles interactions with Convex backend

import Foundation
import ConvexMobile
import ConvexClerk
import Clerk
import Combine

/// Authentication state for the app
enum AuthState: Equatable {
    case loading
    case authenticated(userId: String)
    case unauthenticated
}

/// Service for interacting with Convex backend with Clerk authentication
/// Manages conversations, transcript processing, and user session state
@MainActor
class ConvexService: ObservableObject {
    static let shared = ConvexService()

    private var client: ConvexClientWithAuth<ClerkCredentials>?

    @Published var authState: AuthState = .loading
    @Published var errorMessage: String?

    private init() {
        // Initialize Convex client with Clerk authentication
        if let deploymentURL = getConvexDeploymentURL() {
            // Create Clerk auth provider using ConvexClerk package
            // jwtTemplate must match the template name in Clerk Dashboard (default: "convex")
            let authProvider = ClerkAuthProvider(jwtTemplate: "convex")

            // Initialize authenticated client
            client = ConvexClientWithAuth(
                deploymentUrl: deploymentURL,
                authProvider: authProvider
            )
            print("✅ Convex client initialized with Clerk authentication")
        } else {
            print("⚠️ Convex deployment URL not configured")
        }
        // Keep authState as .loading until loginFromCache() completes
    }

    /// Gets the Convex deployment URL from environment or configuration
    private func getConvexDeploymentURL() -> String? {
        print("🔍 [ConvexService] Looking for CONVEX_DEPLOYMENT_URL...")

        // Check environment variable
        let envUrl = ProcessInfo.processInfo.environment["CONVEX_DEPLOYMENT_URL"]
        print("   - Environment: \(envUrl ?? "not found")")

        if let url = envUrl, !url.isEmpty {
            return url
        }

        // Check Info.plist
        let plistUrl = Bundle.main.object(forInfoDictionaryKey: "CONVEX_DEPLOYMENT_URL") as? String
        print("   - Info.plist: \(plistUrl ?? "not found")")

        if let url = plistUrl, !url.isEmpty, url != "$(CONVEX_DEPLOYMENT_URL)" {
            return url
        }

        print("   ⚠️ CONVEX_DEPLOYMENT_URL not found!")
        return nil
    }

    /// Gets the Clerk publishable key from environment or configuration
    private func getClerkPublishableKey() -> String? {
        // Check environment variable
        let envKey = ProcessInfo.processInfo.environment["CLERK_PUBLISHABLE_KEY"]
        if let key = envKey, !key.isEmpty {
            return key
        }

        // Check Info.plist
        let plistKey = Bundle.main.object(forInfoDictionaryKey: "CLERK_PUBLISHABLE_KEY") as? String
        if let key = plistKey, !key.isEmpty, key != "$(CLERK_PUBLISHABLE_KEY)" {
            return key
        }

        return nil
    }

    // MARK: - Authentication

    /// Attempts to restore session from Clerk on app launch
    func loginFromCache() async -> Bool {
        print("🔐 [ConvexService] loginFromCache() called")

        // First, ensure Clerk has loaded its saved session
        print("   - Calling Clerk.shared.load()...")
        do {
            try await Clerk.shared.load()
            print("   - Clerk.load() completed")
        } catch {
            print("   ⚠️ Clerk.load() failed: \(error)")
        }

        // Check for session
        print("   - Checking for session...")
        if let session = Clerk.shared.session {
            print("   ✅ Session found: \(session.id)")
            if let user = Clerk.shared.user {
                print("   ✅ User found: \(user.id)")

                // Authenticate the Convex client with Clerk session
                await authenticateConvexClient()

                authState = .authenticated(userId: user.id)
                return true
            }
        }

        print("   ⚠️ No session found")
        authState = .unauthenticated
        return false
    }

    /// Called after Clerk sign-in completes
    func onSignInComplete() {
        if let user = Clerk.shared.user {
            authState = .authenticated(userId: user.id)

            // Authenticate the Convex client with new session
            Task {
                await authenticateConvexClient()
            }
        }
    }

    /// Authenticates the Convex client using current Clerk session
    private func authenticateConvexClient() async {
        guard let client = client else { return }

        do {
            // The ClerkAuthProvider should handle fetching the JWT automatically
            // If it requires manual login, call:
            try await client.login()
            print("✅ Convex client authenticated with Clerk")

            // CRITICAL: Create/update user record in Convex database
            // This must be done after authentication so the backend has a user record
            // We run this in the background so it doesn't block the UI/loading state
            Task {
                try? await ensureUserExists()
            }
        } catch {
            print("❌ Failed to authenticate Convex client: \(error)")
        }
    }

    /// Ensures the user record exists in Convex database
    /// CRITICAL: Must be called after authentication before creating conversations
    /// Backend's createMacConversation throws error if user doesn't exist
    private func ensureUserExists() async throws {
        guard let client = client else { return }

        do {
            struct UserResponse: Decodable {
                let _id: String
            }

            let _: UserResponse? = try await client.mutation(
                "users:upsertUser",
                with: [:]
            )
            print("✅ User record created/updated")
        } catch {
            print("⚠️ Failed to create user record: \(error)")
        }
    }

    /// Signs out the current user
    func logout() async {
        do {
            // Logout from Convex client first
            if let client = client {
                try await client.logout()
            }

            // Then logout from Clerk
            try await Clerk.shared.signOut()
            authState = .unauthenticated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Transcription

    // MARK: - Speechmatics Transcription

    /// Fetches a JWT for Speechmatics real-time transcription from the backend
    func getSpeechmaticsJWT() async throws -> String {
        guard let client = client else {
            throw ConvexError.clientNotInitialized
        }

        print("🔑 Fetching Speechmatics JWT from backend...")
        let jwt: String = try await client.action("speechmatics:generateJWT", with: [:])

        print("   ✅ JWT fetched successfully")
        return jwt
    }

    // MARK: - Conversation Management

    /// Creates a new conversation for Mac app recording
    /// - Parameters:
    ///   - title: Optional conversation title (typically meeting name)
    ///   - calendarEventId: Optional calendar event ID for linking
    /// - Returns: The conversation ID from Convex database
    func createConversation(title: String?, calendarEventId: String?) async throws -> String {
        guard let client = client else {
            print("❌ Cannot create conversation: Client not initialized")
            throw ConvexError.clientNotInitialized
        }

        // Check if user is authenticated
        guard case .authenticated = authState else {
            print("❌ Cannot create conversation: Not authenticated (authState: \(authState))")
            throw ConvexError.authenticationRequired
        }

        // Build args dictionary with ConvexEncodable types
        var args: [String: (any ConvexEncodable)?] = [:]
        if let title = title {
            args["title"] = title as (any ConvexEncodable)?
        }
        if let calendarEventId = calendarEventId {
            args["calendarEventId"] = calendarEventId as (any ConvexEncodable)?
        }

        print("📝 Creating conversation: \(title ?? "Untitled")")

        do {
            // Define response structure - backend returns { id: conversationId }
            struct CreateConversationResponse: Decodable {
                let id: String
            }

            let result: CreateConversationResponse? = try await client.mutation(
                "conversations:createMacConversation",
                with: args
            )

            if let id = result?.id {
                print("   ✅ Conversation created: \(id)")
                return id
            } else {
                 print("⚠️ Conversation creation returned null response")
                 throw ConvexError.netError("Backend returned null conversation ID")
            }
        } catch {
            print("❌ Conversation creation failed: \(error)")
            throw error
        }
    }

    /// Processes transcript with backend after recording completes
    /// Uses JSON string serialization to bypass Swift's ConvexEncodable type system limitations
    /// - Parameters:
    ///   - conversationId: The conversation ID to associate the transcript with
    ///   - transcriptTurns: Array of transcript turns with speaker, text, and timestamps
    ///   - initiatorName: Name of the user/initiator (defaults to "Me")
    /// - Returns: Dictionary containing processed transcript and extracted facts
    func processRealtimeTranscript(
        conversationId: String,
        transcriptTurns: [[String: Any]],
        initiatorName: String?
    ) async throws -> [String: Any] {
        guard let client = client else {
            throw ConvexError.clientNotInitialized
        }

        // Serialize transcript to JSON string to bypass Swift's ConvexEncodable type system limitations
        // This avoids the issue where [[String: (any ConvexEncodable)?]] cannot be cast to (any ConvexEncodable)
        guard let jsonData = try? JSONSerialization.data(withJSONObject: transcriptTurns, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("❌ Failed to serialize transcript to JSON")
            throw ConvexError.netError("Failed to serialize transcript")
        }

        // Build args with JSON string (backend will parse it)
        var args: [String: (any ConvexEncodable)?] = [:]
        args["conversationId"] = conversationId
        args["transcriptTurnsJson"] = jsonString  // Send as JSON string
        args["initiatorName"] = initiatorName ?? "Me"
        args["scannerName"] = "System"

        print("📤 Processing transcript (\(transcriptTurns.count) turns)")
        // Backend returns: { transcript: [...], S1_facts: [...], S2_facts: [...] }
        struct ProcessTranscriptResponse: Decodable {
            let transcript: [[String: String]]?
            let S1_facts: [String]?
            let S2_facts: [String]?

            enum CodingKeys: String, CodingKey {
                case transcript
                case S1_facts = "S1_facts"
                case S2_facts = "S2_facts"
            }
        }

        // Try without explicit type on args to see if Swift infers correct overload
        let response = try await client.action(
            "realtimeTranscription:processRealtimeTranscript",
            with: args
        ) as ProcessTranscriptResponse?

        // Convert to [String: Any] dictionary
        var resultDict: [String: Any] = [:]
        if let transcript = response?.transcript {
            resultDict["transcript"] = transcript
        }
        if let s1Facts = response?.S1_facts {
            resultDict["S1_facts"] = s1Facts
        }
        if let s2Facts = response?.S2_facts {
            resultDict["S2_facts"] = s2Facts
        }

        print("   ✅ Transcript processed successfully")
        return resultDict
    }

    /// Struct for word-level timing data
    struct WordTiming: Codable {
        let word: String
        let startTime: Double
        let endTime: Double
        let wordId: String
    }

    /// Appends a transcript turn to the backend conversation in real-time
    func appendTranscriptTurn(
        conversationId: String,
        speaker: String,
        text: String,
        order: Int,
        timestamp: Double?,
        words: [WordTiming]?
    ) async throws {
        guard let client = client else { return }

        // We need to encode the words array to a structure Convex accepts
        // Using a dictionary approach for arguments
        var args: [String: (any ConvexEncodable)?] = [
            "conversationId": conversationId,
            "speaker": speaker,
            "text": text,
            "order": order
        ]

        if let timestamp = timestamp {
            args["timestamp"] = timestamp as (any ConvexEncodable)?
        }

        if let words = words {
            // Serialize words to JSON string to bypass ConvexEncodable nested type limitations
            let wordsArray: [[String: Any]] = words.map { word in
                [
                    "word": word.word,
                    "startTime": word.startTime,
                    "endTime": word.endTime,
                    "wordId": word.wordId
                ]
            }
            if let jsonData = try? JSONSerialization.data(withJSONObject: wordsArray, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                args["wordsJson"] = jsonString as (any ConvexEncodable)?
            }
        }

        // Use 'streaming:appendTranscriptTurn' mutation
        // Since we are using ConvexMobile's client.mutation which expects [String: Any] (technically [String: ConvexEncodable]),
        // and standard types conform to it (hopefully).
        // If compilation fails, we might need to adjust.

        struct AppendResponse: Decodable {
            let _id: String
        }

        let _: AppendResponse? = try await client.mutation(
            "streaming:appendTranscriptTurn",
            with: args
        )
    }

    /// Checks if Convex is properly configured
    func isConfigured() -> Bool {
        return client != nil
    }
    // MARK: - Notes Generation

    /// Generates notes from a transcript using the backend
    func generateNotes(transcript: String, templateId: String?) async -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let client = client else {
                        throw ConvexError.clientNotInitialized
                    }

                    // Call backend action named "notes:generate"
                    let args: [String: String] = [
                        "transcript": transcript,
                        "templateId": templateId ?? ""
                    ]

                    let result: String = try await client.action("notes:generate", with: args)

                    continuation.yield(result)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    // MARK: - Audio Upload

    /// Uploads an audio file to Convex storage
    func uploadAudioFile(audioFileURL: URL, meetingId: UUID) async throws -> String? {
        guard let client = client else { return nil }

        // 1. Get upload URL
        // Standard Convex action for getting upload URL
        let uploadUrl: String = try await client.action("storage:generateUploadUrl", with: [:])
        guard let url = URL(string: uploadUrl) else { return nil }

        // 2. Upload file
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")

        let data = try Data(contentsOf: audioFileURL)
        let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        // 3. Parse response to get storageId
        struct UploadResponse: Decodable {
            let storageId: String
        }

        let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: responseData)
        return uploadResponse.storageId
    }
}

// MARK: - Supporting Types

struct TranscriptionSessionConfig {
    let wsUrl: String
    let authToken: String?
    let config: [String: Any]?
}

// MARK: - Convex Errors

enum ConvexError: LocalizedError {
    case clientNotInitialized
    case fileReadFailed
    case uploadFailed(String)
    case netError(String)
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .clientNotInitialized:
            return "Backend not configured. Please set CONVEX_DEPLOYMENT_URL."
        case .fileReadFailed:
            return "Failed to read audio file."
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .netError(let message):
            return "Network error: \(message)"
        case .authenticationRequired:
            return "Please sign in to continue."
        }
    }
}

