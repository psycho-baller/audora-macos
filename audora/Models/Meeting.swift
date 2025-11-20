import Foundation

// MARK: - Backward Compatibility
// Type alias for existing code that references Meeting
typealias Meeting = TranscriptionSession

// MARK: - Audio & Transcription Enums

enum AudioSource: String, Codable, CaseIterable {
    case mic = "MIC"
    case system = "SYS"
    
    var displayName: String {
        switch self {
        case .mic:
            return "Me"
        case .system:
            return "Them"
        }
    }
    
    var copyPrefix: String {
        switch self {
        case .mic:
            return "Me"
        case .system:
            return "Them"
        }
    }
    
    var icon: String {
        switch self {
        case .mic:
            return "mic.fill"
        case .system:
            return "speaker.wave.2.fill"
        }
    }
}

enum TranscriptionSource: String, Codable {
    case manual = "manual"           // User manually started recording
    case micFollowing = "micFollowing"  // Auto-started from mic following mode
    case autoRecording = "autoRecording" // Auto-started from auto recording mode
    
    var displayName: String {
        switch self {
        case .manual:
            return "Manual Recording"
        case .micFollowing:
            return "Mic Following"
        case .autoRecording:
            return "Auto Recording"
        }
    }
    
    var icon: String {
        switch self {
        case .manual:
            return "record.circle"
        case .micFollowing:
            return "waveform.circle"
        case .autoRecording:
            return "bolt.circle"
        }
    }
}

struct TranscriptChunk: Codable, Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let source: AudioSource
    let text: String
    let isFinal: Bool
    
    init(id: UUID = UUID(), timestamp: Date = Date(), source: AudioSource, text: String, isFinal: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.text = text
        self.isFinal = isFinal
    }
}

struct CollapsedTranscriptChunk: Identifiable {
    let id: UUID
    let timestamp: Date
    let source: AudioSource
    let combinedText: String
    
    init(id: UUID = UUID(), timestamp: Date, source: AudioSource, combinedText: String) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.combinedText = combinedText
    }
}

struct TranscriptionSession: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    var title: String
    var transcriptChunks: [TranscriptChunk]
    var userNotes: String
    var generatedNotes: String
    var templateId: UUID?  // Template used for this session
    var source: TranscriptionSource  // How this session was created
    var analytics: SpeechAnalytics?  // Speech analytics for this session
    var audioFileURL: String?  // Path to the saved audio recording file
    // MARK: - Data versioning
    /// Version of this TranscriptionSession record on disk. Useful for migration.
    var dataVersion: Int
    /// Current app data version. Increment whenever you make a breaking change to `TranscriptionSession` that requires migration.
    static let currentDataVersion = 4  // Incremented for audio file support
    
    init(id: UUID = UUID(),
         date: Date = Date(),
         title: String = "",
         transcriptChunks: [TranscriptChunk] = [],
         userNotes: String = "",
         generatedNotes: String = "",
         templateId: UUID? = nil,
         source: TranscriptionSource = .manual,
         analytics: SpeechAnalytics? = nil,
         audioFileURL: String? = nil,
         dataVersion: Int = TranscriptionSession.currentDataVersion) {
        self.id = id
        self.date = date
        self.title = title
        self.transcriptChunks = transcriptChunks
        self.userNotes = userNotes
        self.generatedNotes = generatedNotes
        self.templateId = templateId
        self.source = source
        self.analytics = analytics
        self.audioFileURL = audioFileURL
        self.dataVersion = dataVersion
    }
    
    // `Codable` conformance now uses the compiler-synthesised implementation.
    
    // Computed property for backward compatibility with existing code
    var transcript: String {
        return transcriptChunks
            .filter { $0.isFinal }
            .map { "[\($0.source.rawValue)] \($0.text)" }
            .joined(separator: " ")
    }
    
    // Formatted transcript for copying with collapsed sequential chunks
    var formattedTranscript: String {
        let finalChunks = transcriptChunks.filter { $0.isFinal }
        
        guard !finalChunks.isEmpty else { return "" }
        
        var result: [String] = []
        var currentSource: AudioSource?
        var currentTexts: [String] = []
        
        for chunk in finalChunks {
            if chunk.source != currentSource {
                // Finish previous section if exists
                if let source = currentSource, !currentTexts.isEmpty {
                    let combinedText = currentTexts.joined(separator: " ")
                    result.append("\(source.copyPrefix): \(combinedText)")
                }
                
                // Start new section
                currentSource = chunk.source
                currentTexts = [chunk.text]
            } else {
                // Same source, add to current section
                currentTexts.append(chunk.text)
            }
        }
        
        // Finish last section
        if let source = currentSource, !currentTexts.isEmpty {
            let combinedText = currentTexts.joined(separator: " ")
            result.append("\(source.copyPrefix): \(combinedText)")
        }
        
        return result.joined(separator: "  \n")
    }
    
    // Collapsed chunks for UI display
    var collapsedTranscriptChunks: [CollapsedTranscriptChunk] {
        guard !transcriptChunks.isEmpty else { return [] }
        
        var result: [CollapsedTranscriptChunk] = []
        var currentSource: AudioSource?
        var currentTexts: [String] = []
        var currentTimestamp: Date?
        
        for chunk in transcriptChunks {
            if chunk.source != currentSource {
                // Finish previous section if exists
                if let source = currentSource, !currentTexts.isEmpty, let timestamp = currentTimestamp {
                    let combinedText = currentTexts.joined(separator: " ")
                    result.append(CollapsedTranscriptChunk(
                        timestamp: timestamp,
                        source: source,
                        combinedText: combinedText
                    ))
                }
                
                // Start new section
                currentSource = chunk.source
                currentTexts = [chunk.text]
                currentTimestamp = chunk.timestamp
            } else {
                // Same source, add to current section
                currentTexts.append(chunk.text)
            }
        }
        
        // Finish last section
        if let source = currentSource, !currentTexts.isEmpty, let timestamp = currentTimestamp {
            let combinedText = currentTexts.joined(separator: " ")
            result.append(CollapsedTranscriptChunk(
                timestamp: timestamp,
                source: source,
                combinedText: combinedText
            ))
        }
        
        return result
    }
    
    // Separate computed properties for mic and system transcripts
    var micTranscript: String {
        return transcriptChunks
            .filter { $0.source == .mic && $0.isFinal }
            .map { $0.text }
            .joined(separator: " ")
    }
    
    var systemTranscript: String {
        return transcriptChunks
            .filter { $0.source == .system && $0.isFinal }
            .map { $0.text }
            .joined(separator: " ")
    }
} 