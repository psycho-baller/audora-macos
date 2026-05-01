import Foundation

enum VocabularyRuleType: String, Codable, CaseIterable, Identifiable {
    case avoid
    case target

    var id: String { rawValue }
}

enum VocabularyRuleSource: String, Codable, CaseIterable {
    case corpusDerived = "corpus-derived"
    case exerciseDerived = "exercise-derived"
    case manual
}

struct VocabularyReplacementOption: Codable, Hashable, Identifiable {
    let word: String
    let useWhen: String
    let caution: String

    var id: String {
        "\(word)|\(useWhen)"
    }
}

struct VocabularyRule: Codable, Identifiable, Hashable {
    var id: String
    var type: VocabularyRuleType
    var term: String
    var replacementOptions: [VocabularyReplacementOption]
    var contexts: [String]
    var source: VocabularyRuleSource
    var active: Bool
    var priority: Int
    var notes: String
    var family: String
    var pinned: Bool

    var normalizedTerm: String {
        term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var primaryReplacement: String? {
        replacementOptions.first?.word
    }
}

struct FocusPack: Codable, Hashable {
    var date: Date
    var weeklyFamily: String
    var targetWords: [String]
    var bannedTerms: [String]
    var triggerQuestion: String
    var exampleRewrite: String
}

struct WritingMatch: Codable, Identifiable, Hashable {
    var id: String
    var ruleId: String
    var term: String
    var family: String
    var rangeLower: Int
    var rangeUpper: Int
    var snippet: String
    var replacement: String?
}

struct WritingSuggestion: Codable, Identifiable, Hashable {
    var id: String
    var ruleId: String
    var term: String
    var replacements: [String]
    var message: String
}

struct WritingCheckResult: Codable, Hashable {
    var inputText: String
    var flaggedTerms: [WritingMatch]
    var suggestedReplacements: [WritingSuggestion]
    var rewardedTerms: [WritingMatch]
    var confidence: Double
    var rewrittenText: String?
}

struct RepairEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var capturedAt: Date
    var sourceApp: String
    var rawSentence: String
    var improvedSentence: String
    var ruleIds: [String]
    var replacementWord: String
    var reusedSameDay: Bool
    var audioMemoPath: String?
}

enum ReinforcementKind: String, Codable, CaseIterable {
    case avoidCaught = "avoid-caught"
    case targetUsedWell = "target-used-well"
    case repairCompleted = "repair-completed"
}

struct ReinforcementEvent: Codable, Identifiable, Hashable {
    var id: UUID
    var term: String
    var kind: ReinforcementKind
    var context: String
    var createdAt: Date
}

struct FocusTemplate: Codable, Hashable, Identifiable {
    var id: String { family }
    var family: String
    var targetWords: [String]
    var bannedTerms: [String]
    var triggerQuestion: String
    var exampleRewrite: String
}

extension FocusTemplate {
    func makePack(for date: Date) -> FocusPack {
        FocusPack(
            date: date,
            weeklyFamily: family,
            targetWords: targetWords,
            bannedTerms: bannedTerms,
            triggerQuestion: triggerQuestion,
            exampleRewrite: exampleRewrite
        )
    }
}

struct ContextWordBankEntry: Codable, Hashable, Identifiable {
    var word: String
    var useWhen: String
    var example: String

    var id: String { word }
}

struct ContextWordBank: Codable, Hashable, Identifiable {
    var context: String
    var noteCount: Int
    var words: [ContextWordBankEntry]

    var id: String { context }
}

struct WritingAwarenessSeed: Codable {
    var sourceRunId: String
    var generatedAt: Date
    var rules: [VocabularyRule]
    var focusTemplates: [FocusTemplate]
    var contextWordBanks: [ContextWordBank]
}

extension WritingAwarenessSeed {
    static func fallback() -> WritingAwarenessSeed {
        WritingAwarenessSeed(
            sourceRunId: "fallback",
            generatedAt: .now,
            rules: [
                VocabularyRule(
                    id: "avoid:thing_family:thing",
                    type: .avoid,
                    term: "thing",
                    replacementOptions: [
                        VocabularyReplacementOption(
                            word: "constraint",
                            useWhen: "You mean a limit, blocker, or condition shaping what is possible.",
                            caution: "Do not use when you actually mean an object."
                        )
                    ],
                    contexts: ["productivity"],
                    source: .corpusDerived,
                    active: true,
                    priority: 5,
                    notes: "Placeholder nouns usually hide the exact object, action, or decision you mean.",
                    family: "thing_family",
                    pinned: false
                ),
                VocabularyRule(
                    id: "target:thing_family:constraint",
                    type: .target,
                    term: "constraint",
                    replacementOptions: [
                        VocabularyReplacementOption(
                            word: "constraint",
                            useWhen: "Use when a limit or condition shapes what is possible.",
                            caution: "Avoid forcing the word into casual contexts where a simpler noun is clearer."
                        )
                    ],
                    contexts: ["productivity"],
                    source: .corpusDerived,
                    active: true,
                    priority: 3,
                    notes: "Fallback precision target.",
                    family: "thing_family",
                    pinned: false
                )
            ],
            focusTemplates: [
                FocusTemplate(
                    family: "thing_family",
                    targetWords: ["constraint", "pattern", "decision"],
                    bannedTerms: ["thing", "stuff"],
                    triggerQuestion: "What exact object, action, or constraint do I mean?",
                    exampleRewrite: "I need to fix this thing. -> I need to resolve this onboarding blocker."
                )
            ],
            contextWordBanks: [
                ContextWordBank(
                    context: "productivity",
                    noteCount: 1,
                    words: [
                        ContextWordBankEntry(
                            word: "constraint",
                            useWhen: "A limit or condition shapes what is possible.",
                            example: "Energy is the real constraint, not motivation."
                        )
                    ]
                )
            ]
        )
    }
}

struct VocabularyRuleOverride: Codable, Hashable {
    var active: Bool?
    var priority: Int?
    var notes: String?
    var pinned: Bool?
}

enum LearningTargetSaveStatus: String, Hashable {
    case saved
    case updated
    case alreadyExists
    case invalid
}

struct LearningTargetSaveResult: Hashable {
    var status: LearningTargetSaveStatus
    var term: String
    var ruleID: String?
    var familyID: String?
    var message: String
    var anchorRect: CGRect?
}

struct LearningWordSuggestion: Codable, Hashable, Identifiable {
    var id = UUID()
    var term: String
    var useWhen: String
    var caution: String
    var matchedPersonalHistory: Bool = false

    private enum CodingKeys: String, CodingKey {
        case term
        case useWhen
        case caution
    }
}

struct LearningWordFamilyDraft: Hashable {
    var familyID: String?
    var targetRuleID: String?
    var targetTerm: String
    var suggestions: [LearningWordSuggestion]
    var suggestedSuggestions: [LearningWordSuggestion]
    var sourceApp: String
    var contextLabel: String
    var origin: String
    var anchorRect: CGRect?
    var notice: String?

    var isExistingFamily: Bool {
        familyID != nil || targetRuleID != nil
    }
}

struct LearningWordSuggestionRefreshResult: Hashable {
    var suggestions: [LearningWordSuggestion]
    var notice: String?
}

struct LearningWordFamilySaveResult: Hashable {
    var familyID: String
    var targetRuleID: String
    var rules: [VocabularyRule]
}

struct ManualRuleEditorDraft: Hashable {
    var ruleID: String?
    var type: VocabularyRuleType
    var term: String
    var replacementWords: [String]
    var contexts: [String]
    var notes: String
    var priority: Int
    var pinned: Bool

    static func blank() -> ManualRuleEditorDraft {
        ManualRuleEditorDraft(
            ruleID: nil,
            type: .avoid,
            term: "",
            replacementWords: [],
            contexts: [],
            notes: "",
            priority: 3,
            pinned: false
        )
    }

    static func learningTarget(term: String, ruleID: String? = nil) -> ManualRuleEditorDraft {
        ManualRuleEditorDraft(
            ruleID: ruleID,
            type: .target,
            term: term,
            replacementWords: [term],
            contexts: [],
            notes: "",
            priority: 5,
            pinned: true
        )
    }
}

extension ManualRuleEditorDraft {
    init(rule: VocabularyRule) {
        self.init(
            ruleID: rule.id,
            type: rule.type,
            term: rule.term,
            replacementWords: rule.replacementOptions.map(\.word),
            contexts: rule.contexts,
            notes: rule.notes,
            priority: rule.priority,
            pinned: rule.pinned
        )
    }
}

struct WritingAwarenessState: Codable {
    var ruleOverrides: [String: VocabularyRuleOverride] = [:]
    var manualRules: [VocabularyRule] = []
    var repairs: [RepairEntry] = []
    var reinforcementEvents: [ReinforcementEvent] = []
    var mutedSites: [String] = []
    var mutedTerms: [String] = []

    private enum CodingKeys: String, CodingKey {
        case ruleOverrides
        case manualRules
        case repairs
        case reinforcementEvents
        case mutedSites
        case mutedTerms
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ruleOverrides = try container.decodeIfPresent([String: VocabularyRuleOverride].self, forKey: .ruleOverrides) ?? [:]
        manualRules = try container.decodeIfPresent([VocabularyRule].self, forKey: .manualRules) ?? []
        repairs = try container.decodeIfPresent([RepairEntry].self, forKey: .repairs) ?? []
        reinforcementEvents = try container.decodeIfPresent([ReinforcementEvent].self, forKey: .reinforcementEvents) ?? []
        mutedSites = try container.decodeIfPresent([String].self, forKey: .mutedSites) ?? []
        mutedTerms = try container.decodeIfPresent([String].self, forKey: .mutedTerms) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ruleOverrides, forKey: .ruleOverrides)
        try container.encode(manualRules, forKey: .manualRules)
        try container.encode(repairs, forKey: .repairs)
        try container.encode(reinforcementEvents, forKey: .reinforcementEvents)
        try container.encode(mutedSites, forKey: .mutedSites)
        try container.encode(mutedTerms, forKey: .mutedTerms)
    }
}

extension WritingAwarenessState {
    static func empty() -> WritingAwarenessState {
        WritingAwarenessState()
    }
}

struct SelectionCaptureResult: Hashable {
    var text: String
    var selectedText: String?
    var sourceApp: String
    var sourceBundleIdentifier: String?
    var contextLabel: String
    var usedClipboardFallback: Bool
    var selectionRange: NSRange?
    var elementFrame: CGRect?
    var selectionBounds: CGRect?
    var capability: FocusedElementCapability
    var isSecureInput: Bool
}

enum FocusedElementMode: String, Hashable {
    case readable
    case replaceable
    case overlayOnly
}

struct FocusedElementCapability: Hashable {
    var canReadText: Bool
    var canReadSelection: Bool
    var canReplaceSelection: Bool
    var canLocateBounds: Bool

    var mode: FocusedElementMode {
        if canReplaceSelection {
            return .replaceable
        }
        if canLocateBounds {
            return .overlayOnly
        }
        return .readable
    }

    var shortLabel: String {
        switch mode {
        case .replaceable:
            return "Quick Replace"
        case .overlayOnly:
            return "Overlay Only"
        case .readable:
            return "Readable"
        }
    }

    var explanation: String {
        switch mode {
        case .replaceable:
            return "This focused field exposes enough Accessibility APIs for direct replacement."
        case .overlayOnly:
            return "Audora can read and coach here, but the host app does not expose safe replacement APIs."
        case .readable:
            return "Audora can inspect this field, but position and replacement data are limited."
        }
    }

    static let overlayOnly = FocusedElementCapability(
        canReadText: true,
        canReadSelection: true,
        canReplaceSelection: false,
        canLocateBounds: true
    )

    static let replaceable = FocusedElementCapability(
        canReadText: true,
        canReadSelection: true,
        canReplaceSelection: true,
        canLocateBounds: true
    )

    static let readable = FocusedElementCapability(
        canReadText: true,
        canReadSelection: true,
        canReplaceSelection: false,
        canLocateBounds: false
    )

    static let unavailable = FocusedElementCapability(
        canReadText: false,
        canReadSelection: false,
        canReplaceSelection: false,
        canLocateBounds: false
    )
}

struct WritingDaySummary: Hashable {
    var avoidCaught: Int
    var targetWins: Int
    var repairsCompleted: Int

    var summaryText: String {
        "\(avoidCaught) catches · \(targetWins) wins · \(repairsCompleted) repairs"
    }
}

extension WritingDaySummary {
    static let empty = WritingDaySummary(avoidCaught: 0, targetWins: 0, repairsCompleted: 0)
}
