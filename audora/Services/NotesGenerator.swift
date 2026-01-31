// NotesGenerator.swift
// Handles AI-powered note generation via backend

import Foundation

/// Result type for note generation streaming
enum GenerationResult {
    case content(String)
    case error(String)
}

/// Generates meeting notes using the backend AI service
class NotesGenerator {
    static let shared = NotesGenerator()

    private init() {}

    /// Generates meeting notes from meeting data using template-based system prompt with streaming
    /// - Parameters:
    ///   - meeting: The meeting object containing all necessary data
    ///   - userBlurb: Information about the user for context
    ///   - systemPrompt: The system prompt template with placeholders
    ///   - templateId: Optional template ID to use for generating notes
    /// - Returns: AsyncStream of partial generated notes
    func generateNotesStream(meeting: Meeting,
                            userBlurb: String,
                            systemPrompt: String,
                            templateId: UUID? = nil) -> AsyncStream<GenerationResult> {

        return AsyncStream<GenerationResult>(GenerationResult.self) { continuation in
            Task {
                do {
                    // Check auth state
                    let authState = await MainActor.run { ConvexService.shared.authState }
                    guard case .authenticated = authState else {
                        continuation.yield(.error("Please sign in to generate notes."))
                        continuation.finish()
                        return
                    }

                    // Load template content
                    var templateContent = ""
                    if let templateId = templateId {
                        let templates = LocalStorageManager.shared.loadTemplates()
                        if let template = templates.first(where: { $0.id == templateId }) {
                            templateContent = template.formattedContent
                        }
                    }

                    // If no template content, use default
                    if templateContent.isEmpty {
                        continuation.yield(.error(ErrorMessage.noTemplate))
                        continuation.finish()
                        return
                    }

                    // Check if transcript is empty
                    if meeting.formattedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continuation.yield(.error(ErrorMessage.noTranscript))
                        continuation.finish()
                        return
                    }

                    // Create date formatter for meeting date
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .full
                    dateFormatter.timeStyle = .short

                    // Prepare template variables
                    let templateVariables: [String: String] = [
                        "meeting_title": meeting.title.isEmpty ? "Untitled Meeting" : meeting.title,
                        "meeting_date": dateFormatter.string(from: meeting.date),
                        "transcript": meeting.formattedTranscript,
                        "user_blurb": userBlurb,
                        "user_notes": meeting.userNotes,
                        "template_content": templateContent
                    ]

                    // Process the system prompt template
                    let systemContent = Settings.processTemplate(systemPrompt, with: templateVariables)

                    // Use backend to generate notes
                    let notesStream = await ConvexService.shared.generateNotes(
                        transcript: meeting.formattedTranscript,
                        templateId: templateId?.uuidString
                    )

                    for try await content in notesStream {
                        continuation.yield(.content(content))
                    }

                    continuation.finish()
                } catch {
                    let errorMessage = ErrorHandler.shared.handleError(error)
                    print("Error in streaming generation: \(error)")
                    continuation.yield(.error(errorMessage))
                    continuation.finish()
                }
            }
        }
    }

    /// Checks if notes generation is available (user is authenticated)
    /// - Returns: True if user is authenticated, false otherwise
    @MainActor
    func isConfigured() -> Bool {
        // Check if user is authenticated
        if case .authenticated = ConvexService.shared.authState {
            return true
        }
        return false
    }
}