import AppKit
import Foundation
import OpenAI
import SwiftUI

@MainActor
final class WritingAwarenessManager: ObservableObject {
    typealias LearningWordSuggestionGenerator = @MainActor (
        _ targetTerm: String,
        _ sourceApp: String,
        _ contextLabel: String,
        _ personalOveruseCounts: [(term: String, count: Int)],
        _ excludingTerms: [String]
    ) async throws -> [LearningWordSuggestion]

    static let shared = WritingAwarenessManager()

    @Published private(set) var seed: WritingAwarenessSeed
    @Published private(set) var state: WritingAwarenessState
    @Published private(set) var rules: [VocabularyRule] = []
    @Published private(set) var contextWordBanks: [ContextWordBank] = []
    @Published private(set) var focusPack: FocusPack
    @Published private(set) var isAccessibilityTrusted = false
    @Published private(set) var isInputMonitoringTrusted = false
    @Published var lensInputText = ""
    @Published var lensSourceApp = "Manual"
    @Published var lensContextLabel = "Manual"
    @Published var lensUsedClipboardFallback = false
    @Published var lensRewrite = ""
    @Published var lensResult: WritingCheckResult?
    @Published private(set) var liveCapture: SelectionCaptureResult?
    @Published private(set) var liveResult: WritingCheckResult?
    @Published private(set) var liveUnderlinePayload: WritingUnderlinePayload?
    @Published private(set) var liveActionMessage: String?
    @Published private(set) var focusDiagnosticsMessage: String?
    @Published private(set) var lastObservedExternalFocusApp: String?
    @Published var lastCaptureError: String?
    @Published private(set) var pendingManualRuleEditorDraft: ManualRuleEditorDraft?
    @Published private(set) var pendingLearningWordFamilyDraft: LearningWordFamilyDraft?

    private let storageManager: WritingAwarenessStorageManager
    private let calendar: Calendar
    private let learningWordSuggestionGenerator: LearningWordSuggestionGenerator?
    private let revealsLearningWordReview: Bool
    private var analysisFingerprints: Set<String> = []
    private var lastObservedExternalFocusDiagnostics: String?
    private var learningWordPreparationTask: Task<Void, Never>?

    private convenience init() {
        let storageManager = WritingAwarenessStorageManager.shared
        let loadedSeed = Self.loadSeed()
        self.init(
            seed: loadedSeed,
            state: storageManager.loadState(),
            storageManager: storageManager,
            calendar: .autoupdatingCurrent,
            learningWordSuggestionGenerator: nil,
            syncSeedOnInit: true,
            refreshPermissionTrustOnInit: true,
            revealsLearningWordReview: true
        )
    }

    init(
        seed: WritingAwarenessSeed,
        state: WritingAwarenessState,
        storageManager: WritingAwarenessStorageManager,
        calendar: Calendar = .autoupdatingCurrent,
        learningWordSuggestionGenerator: LearningWordSuggestionGenerator? = nil,
        syncSeedOnInit: Bool = false,
        refreshPermissionTrustOnInit: Bool = false,
        revealsLearningWordReview: Bool = true
    ) {
        self.storageManager = storageManager
        self.calendar = calendar
        self.learningWordSuggestionGenerator = learningWordSuggestionGenerator
        self.revealsLearningWordReview = revealsLearningWordReview
        self.seed = seed
        self.state = state
        self.contextWordBanks = seed.contextWordBanks
        self.focusPack = Self.resolveFocusPack(from: seed, date: .now)
        if syncSeedOnInit {
            storageManager.syncSeed(seed)
        }
        rebuildRules()
        if refreshPermissionTrustOnInit {
            refreshPermissionTrust()
        }
    }

    var writingAwarenessEnabled: Bool {
        UserDefaultsManager.shared.writingAwarenessEnabled
    }

    var subtleRewardsEnabled: Bool {
        UserDefaultsManager.shared.subtleVocabularyRewardsEnabled
    }

    var currentSummary: WritingDaySummary {
        let todaysEvents = state.reinforcementEvents.filter { calendar.isDateInToday($0.createdAt) }
        return WritingDaySummary(
            avoidCaught: todaysEvents.filter { $0.kind == .avoidCaught }.count,
            targetWins: todaysEvents.filter { $0.kind == .targetUsedWell }.count,
            repairsCompleted: todaysEvents.filter { $0.kind == .repairCompleted }.count
        )
    }

    var liveCapability: FocusedElementCapability {
        liveCapture?.capability ?? .unavailable
    }

    var activeFocusTitle: String {
        focusPack.weeklyFamily
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "family", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
    }

    var focusAvoidRules: [VocabularyRule] {
        liveAvoidRules.filter { $0.family == focusPack.weeklyFamily }
    }

    var focusTargetRules: [VocabularyRule] {
        liveTargetRules.filter { liveTargetTerms.contains($0.normalizedTerm) || $0.family == focusPack.weeklyFamily }
    }

    var pinnedRules: [VocabularyRule] {
        rules.filter(\.pinned)
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.term < rhs.term
                }
                return lhs.priority > rhs.priority
            }
    }

    var manualRules: [VocabularyRule] {
        state.manualRules.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.term < rhs.term
            }
            return lhs.priority > rhs.priority
        }
    }

    func isLearningWordRule(_ rule: VocabularyRule) -> Bool {
        Self.isLearningWordFamily(rule.family)
    }

    var topDerivedRules: [VocabularyRule] {
        rules
            .filter { $0.source != .manual }
            .sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned {
                    return lhs.pinned && !rhs.pinned
                }
                if lhs.priority == rhs.priority {
                    return lhs.term < rhs.term
                }
                return lhs.priority > rhs.priority
            }
    }

    var recentRepairs: [RepairEntry] {
        state.repairs.sorted { $0.capturedAt > $1.capturedAt }
    }

    var focusContextBanks: [ContextWordBank] {
        let focusContexts = Set((focusAvoidRules + focusTargetRules).flatMap(\.contexts))
        let filtered = contextWordBanks.filter { focusContexts.contains($0.context) }
        return filtered.isEmpty ? Array(contextWordBanks.prefix(2)) : filtered
    }

    var sharedWritingStoragePath: String {
        storageManager.storageDirectory.path
    }

    func adapterStatus(for kind: WritingAdapterKind) -> WritingAdapterStatus {
        switch kind {
        case .audoraInline:
            return .available

        case .browserInline:
            return browserNativeHostInstalled ? .available : .unavailable

        case .accessibilityInline:
            guard isAccessibilityTrusted else {
                return .unavailable
            }
            if liveCapture?.isSecureInput == true {
                return .unavailable
            }
            if let liveCapture, !liveCapture.capability.canLocateBounds {
                return .popupFallback
            }
            return .available
        }
    }

    func refresh() {
        seed = Self.loadSeed()
        contextWordBanks = seed.contextWordBanks
        state = storageManager.loadState()
        refreshFocusPack()
        storageManager.syncSeed(seed)
        rebuildRules()
        refreshPermissionTrust()
        analyzeCurrentLensText(recordFeedback: false)
    }

    func refreshFocusPack(for date: Date = .now) {
        focusPack = Self.resolveFocusPack(from: seed, date: date)
        rebuildRules()
    }

    func refreshPermissionTrust() {
        isAccessibilityTrusted = SelectionCaptureManager.shared.isTrusted
        isInputMonitoringTrusted = SystemWideWritingMonitor.shared.isInputMonitoringTrusted
    }

    func copyFocusedElementDiagnostics() {
        let diagnostics = lastObservedExternalFocusDiagnostics ?? SelectionCaptureManager.shared.debugFocusedElementDiagnostics()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)

        let sourceApp = lastObservedExternalFocusApp ?? NSWorkspace.shared.frontmostApplication?.localizedName ?? "the frontmost app"
        focusDiagnosticsMessage = "Copied focused-element diagnostics for \(sourceApp)."
    }

    func cacheExternalFocusDiagnostics(_ diagnostics: String, sourceApp: String) {
        lastObservedExternalFocusDiagnostics = diagnostics
        lastObservedExternalFocusApp = sourceApp
    }

    func refreshAccessibilityTrust() {
        refreshPermissionTrust()
    }

    func requestAccessibilityAccess() {
        SelectionCaptureManager.shared.requestAccess()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            refreshPermissionTrust()
            if !isAccessibilityTrusted {
                SelectionCaptureManager.shared.openAccessibilitySettings()
            }
        }
    }

    func openAccessibilitySettings() {
        SelectionCaptureManager.shared.openAccessibilitySettings()
        refreshPermissionTrust()
    }

    func requestInputMonitoringAccess() {
        SystemWideWritingMonitor.shared.requestInputMonitoringAccess()
        refreshPermissionTrust()
    }

    func openInputMonitoringSettings() {
        SystemWideWritingMonitor.shared.openInputMonitoringSettings()
        refreshPermissionTrust()
    }

    func captureSelectionAsLearningTarget(preferClipboardFallback: Bool? = nil) {
        let allowClipboard = preferClipboardFallback ?? UserDefaultsManager.shared.writingLensClipboardFallbackEnabled
        guard let capture = SelectionCaptureManager.shared.captureSelection(allowClipboardFallback: allowClipboard) else {
            refreshAccessibilityTrust()
            let message: String
            if !isAccessibilityTrusted {
                message = "Accessibility access is required to capture selected text from other apps."
            } else if allowClipboard {
                message = "No text found. Highlight a word first or copy it to the clipboard."
            } else {
                message = "No selected text was found in the frontmost app."
            }
            presentLearningTargetHUD(
                for: LearningTargetSaveResult(
                    status: .invalid,
                    term: "",
                    ruleID: nil,
                    familyID: nil,
                    message: message,
                    anchorRect: nil
                )
            )
            return
        }

        _ = submitLearningTarget(
            text: capture.selectedText ?? capture.text,
            sourceApp: capture.sourceApp,
            contextLabel: capture.contextLabel,
            origin: capture.usedClipboardFallback ? "clipboard" : "selection",
            anchorRect: capture.selectionBounds ?? capture.elementFrame
        )
    }

    @discardableResult
    func submitLearningTarget(
        text: String,
        sourceApp: String,
        contextLabel: String,
        origin: String,
        anchorRect: CGRect? = nil
    ) -> LearningTargetSaveResult? {
        switch Self.normalizeLearningTargetText(text) {
        case let .failure(message, suggestedTerm):
            let result = LearningTargetSaveResult(
                status: .invalid,
                term: suggestedTerm,
                ruleID: nil,
                familyID: nil,
                message: message,
                anchorRect: anchorRect
            )
            presentLearningTargetHUD(for: result)
            return result

        case let .success(term):
            presentLearningTargetLoadingHUD(term: term, anchorRect: anchorRect)
            startLearningWordDraftPreparation(
                term: term,
                sourceApp: sourceApp,
                contextLabel: contextLabel,
                origin: origin,
                anchorRect: anchorRect
            )
            return nil
        }
    }

    func saveLearningWordFamily(_ draft: LearningWordFamilyDraft) -> LearningTargetSaveResult {
        switch Self.normalizeLearningTargetText(draft.targetTerm) {
        case let .failure(message, suggestedTerm):
            return LearningTargetSaveResult(
                status: .invalid,
                term: suggestedTerm,
                ruleID: nil,
                familyID: draft.familyID,
                message: message,
                anchorRect: draft.anchorRect
            )

        case let .success(targetTerm):
            let saveResult = buildLearningWordFamilySaveResult(for: draft, targetTerm: targetTerm)
            let removedRuleIDs = rulesToReplaceForLearningWordDraft(draft, targetTerm: targetTerm)

            state.manualRules.removeAll { removedRuleIDs.contains($0.id) }
            state.ruleOverrides = state.ruleOverrides.filter { !removedRuleIDs.contains($0.key) }
            state.manualRules.append(contentsOf: saveResult.rules)
            persistState()
            rebuildRules()

            return LearningTargetSaveResult(
                status: draft.isExistingFamily ? .updated : .saved,
                term: targetTerm,
                ruleID: saveResult.targetRuleID,
                familyID: saveResult.familyID,
                message: draft.isExistingFamily
                    ? "Updated linked words for \"\(targetTerm)\"."
                    : learningWordSavedMessage(term: targetTerm, origin: draft.origin),
                anchorRect: draft.anchorRect
            )
        }
    }

    @discardableResult
    func commitLearningWordFamily(_ draft: LearningWordFamilyDraft) -> LearningTargetSaveResult {
        let result = saveLearningWordFamily(draft)
        presentLearningTargetHUD(for: result)
        return result
    }

    func undoLearningTarget(ruleID: String, familyID: String?) {
        deleteLearningWordFamily(familyID: familyID, targetRuleID: ruleID)
    }

    func deleteLearningWordFamily(familyID: String?, targetRuleID: String?) {
        let ruleIDsToDelete: Set<String>
        if let familyID, Self.isLearningWordFamily(familyID) {
            ruleIDsToDelete = Set(state.manualRules.filter { $0.family == familyID }.map(\.id))
        } else if let targetRuleID {
            ruleIDsToDelete = [targetRuleID]
        } else {
            return
        }

        guard !ruleIDsToDelete.isEmpty else { return }
        state.manualRules.removeAll { ruleIDsToDelete.contains($0.id) }
        state.ruleOverrides = state.ruleOverrides.filter { !ruleIDsToDelete.contains($0.key) }
        persistState()
        rebuildRules()
    }

    func openLearningTargetEditor(term: String, ruleID: String?, familyID: String?) {
        let draft = existingLearningWordDraft(
            for: term,
            targetRuleID: ruleID,
            familyID: familyID,
            sourceApp: "Writing Awareness",
            contextLabel: "Writing Awareness",
            origin: "editor",
            anchorRect: nil
        ) ?? LearningWordFamilyDraft(
            familyID: familyID,
            targetRuleID: ruleID,
            targetTerm: term,
            suggestions: [],
            suggestedSuggestions: [],
            sourceApp: "Writing Awareness",
            contextLabel: "Writing Awareness",
            origin: "editor",
            anchorRect: nil,
            notice: "Review and edit the linked words before saving."
        )
        openLearningWordReview(with: draft)
    }

    func openLearningTargetEditor(for rule: VocabularyRule) {
        openLearningTargetEditor(
            term: learningWordTargetTerm(for: rule),
            ruleID: rule.type == .target ? rule.id : nil,
            familyID: Self.isLearningWordFamily(rule.family) ? rule.family : nil
        )
    }

    func consumePendingManualRuleEditorDraft() -> ManualRuleEditorDraft? {
        let draft = pendingManualRuleEditorDraft
        pendingManualRuleEditorDraft = nil
        return draft
    }

    func consumePendingLearningWordFamilyDraft() -> LearningWordFamilyDraft? {
        let draft = pendingLearningWordFamilyDraft
        pendingLearningWordFamilyDraft = nil
        return draft
    }

    func captureSelectionIntoLens(preferClipboardFallback: Bool? = nil) {
        lastCaptureError = nil
        let allowClipboard = preferClipboardFallback ?? UserDefaultsManager.shared.writingLensClipboardFallbackEnabled
        guard let capture = SelectionCaptureManager.shared.captureSelection(allowClipboardFallback: allowClipboard) else {
            refreshAccessibilityTrust()
            if !isAccessibilityTrusted {
                lastCaptureError = "Accessibility access is required to read selected text from other apps."
            } else if allowClipboard {
                lastCaptureError = "No selected text was found. Copy text to the clipboard or paste it into the panel."
            } else {
                lastCaptureError = "No selected text was found in the frontmost app."
            }
            return
        }
        applyCapture(capture, recordFeedback: true)
    }

    func applyCapture(_ capture: SelectionCaptureResult, recordFeedback: Bool) {
        lensInputText = capture.text
        lensSourceApp = capture.sourceApp
        lensContextLabel = capture.contextLabel
        lensUsedClipboardFallback = capture.usedClipboardFallback
        lensRewrite = ""
        analyzeCurrentLensText(recordFeedback: recordFeedback)
    }

    func loadClipboardIntoLens() {
        if let value = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            applyCapture(
                SelectionCaptureResult(
                    text: value,
                    selectedText: value,
                    sourceApp: "Clipboard",
                    sourceBundleIdentifier: nil,
                    contextLabel: BrowserURLHelper.getCurrentContext() ?? "Clipboard",
                    usedClipboardFallback: true,
                    selectionRange: nil,
                    elementFrame: nil,
                    selectionBounds: nil,
                    capability: .readable,
                    isSecureInput: false
                ),
                recordFeedback: true
            )
        } else {
            lastCaptureError = "Clipboard does not contain text right now."
        }
    }

    func applyLiveCapture(_ capture: SelectionCaptureResult, recordFeedback: Bool) {
        liveActionMessage = nil
        liveCapture = capture
        let result = analyze(text: capture.text, sourceApp: capture.sourceApp, contextLabel: capture.contextLabel)
        liveResult = result
        liveUnderlinePayload = underlinePayload(
            for: result,
            snapshot: WritingSurfaceSnapshot(
                surfaceID: capture.sourceBundleIdentifier ?? capture.sourceApp,
                text: capture.text,
                sourceApp: capture.sourceApp,
                contextLabel: capture.contextLabel,
                origin: .accessibility,
                selectionRange: capture.selectionRange
            )
        )
        if recordFeedback {
            recordEvents(for: result)
        }
    }

    func clearLiveCapture() {
        liveActionMessage = nil
        liveCapture = nil
        liveResult = nil
        liveUnderlinePayload = nil
    }

    func replaceTopLiveSuggestion() {
        guard liveCapability.canReplaceSelection else {
            liveActionMessage = "This field does not expose a safe replacement API."
            return
        }
        guard let suggestion = liveResult?.suggestedReplacements.first,
              let replacement = suggestion.replacements.first else {
            liveActionMessage = "No live replacement is available for this suggestion."
            return
        }

        let success = SelectionCaptureManager.shared.replaceFocusedSelection(with: replacement)
        liveActionMessage = success
            ? "Replaced with \"\(replacement)\"."
            : "The host app rejected the replacement."

        guard success else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.lastCaptureError = nil
            if let capture = SelectionCaptureManager.shared.captureFocusedTextSnapshot() {
                self?.applyLiveCapture(capture, recordFeedback: false)
            } else {
                self?.clearLiveCapture()
            }
        }
    }

    func analyzeCurrentLensText(recordFeedback: Bool = false) {
        let result = analyze(text: lensInputText, sourceApp: lensSourceApp, contextLabel: lensContextLabel)
        lensResult = result
        if recordFeedback {
            recordEvents(for: result)
        }
    }

    func analyzeSurface(_ snapshot: WritingSurfaceSnapshot, recordFeedback: Bool = false) -> WritingUnderlinePayload? {
        let result = analyze(
            text: snapshot.text,
            sourceApp: snapshot.sourceApp,
            contextLabel: snapshot.contextLabel
        )
        if recordFeedback {
            recordEvents(for: result)
        }
        return underlinePayload(for: result, snapshot: snapshot)
    }

    func analyze(text: String, sourceApp: String, contextLabel: String) -> WritingCheckResult {
        guard writingAwarenessEnabled else {
            return WritingCheckResult(
                inputText: text,
                flaggedTerms: [],
                suggestedReplacements: [],
                rewardedTerms: [],
                confidence: 0.0,
                rewrittenText: nil
            )
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return WritingCheckResult(
                inputText: text,
                flaggedTerms: [],
                suggestedReplacements: [],
                rewardedTerms: [],
                confidence: 0.0,
                rewrittenText: nil
            )
        }

        let mutedTerms = Set(state.mutedTerms.map { $0.lowercased() })
        let wordCount = max(1, Self.wordCount(in: text))
        let flaggedTerms = liveAvoidRules
            .filter { !mutedTerms.contains($0.normalizedTerm) }
            .flatMap { Self.matches(for: $0, in: text) }
            .sorted { $0.rangeLower < $1.rangeLower }

        let rewardedTerms = subtleRewardsEnabled
            ? liveTargetRules
            .filter { !mutedTerms.contains($0.normalizedTerm) }
            .flatMap { rule in
                let matches = Self.matches(for: rule, in: text)
                return Self.rewardableMatches(for: rule, matches: matches, wordCount: wordCount)
            }
            .sorted { $0.rangeLower < $1.rangeLower }
            : []

        let flaggedRuleIDs = Set(flaggedTerms.map(\.ruleId))
        let suggestions = liveAvoidRules.compactMap { rule -> WritingSuggestion? in
            guard flaggedRuleIDs.contains(rule.id) else { return nil }
            let replacements = rule.replacementOptions.map(\.word).filter { !$0.isEmpty }
            let messageSource = rule.replacementOptions.first?.useWhen ?? rule.notes
            return WritingSuggestion(
                id: "suggestion:\(rule.id)",
                ruleId: rule.id,
                term: rule.term,
                replacements: Array(replacements.prefix(3)),
                message: messageSource
            )
        }

        let confidence = min(0.98, 0.58 + (Double(flaggedTerms.count) * 0.04) + (Double(rewardedTerms.count) * 0.03))
        return WritingCheckResult(
            inputText: text,
            flaggedTerms: flaggedTerms,
            suggestedReplacements: suggestions,
            rewardedTerms: rewardedTerms,
            confidence: confidence,
            rewrittenText: nil
        )
    }

    func underlinePayload(for result: WritingCheckResult, snapshot: WritingSurfaceSnapshot) -> WritingUnderlinePayload? {
        let spans = issueSpans(for: result)
        guard !spans.isEmpty else { return nil }

        let fingerprintSource = spans.map { span in
            "\(span.id)|\(span.rangeLower)|\(span.rangeUpper)|\(span.kind.rawValue)"
        }.joined(separator: "||")

        return WritingUnderlinePayload(
            surfaceID: snapshot.surfaceID,
            text: snapshot.text,
            sourceApp: snapshot.sourceApp,
            contextLabel: snapshot.contextLabel,
            origin: snapshot.origin,
            spans: spans,
            confidence: result.confidence,
            fingerprint: "\(snapshot.surfaceID)|\(fingerprintSource)"
        )
    }

    func applySuggestion(to text: String, span: WritingIssueSpan, replacement: String) -> String {
        let nsText = text as NSString
        let range = NSRange(location: span.rangeLower, length: max(0, span.rangeUpper - span.rangeLower))
        guard range.location != NSNotFound, NSMaxRange(range) <= nsText.length else {
            return text
        }
        return nsText.replacingCharacters(in: range, with: replacement)
    }

    func replaceLiveSpan(_ span: WritingIssueSpan, with replacement: String) -> Bool {
        let success = SelectionCaptureManager.shared.replaceFocusedRange(span.sourceRange, with: replacement)
        liveActionMessage = success
            ? "Replaced with \"\(replacement)\"."
            : "The host app rejected the replacement."

        guard success else { return false }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            if let capture = SelectionCaptureManager.shared.captureFocusedTextSnapshot() {
                self.applyLiveCapture(capture, recordFeedback: false)
            } else {
                self.clearLiveCapture()
            }
        }

        return success
    }

    func generateLensRewrite() {
        guard let result = lensResult else { return }
        let rewritten = Self.rewrite(text: lensInputText, using: result, rules: rules)
        lensRewrite = rewritten
        lensResult = WritingCheckResult(
            inputText: result.inputText,
            flaggedTerms: result.flaggedTerms,
            suggestedReplacements: result.suggestedReplacements,
            rewardedTerms: result.rewardedTerms,
            confidence: result.confidence,
            rewrittenText: rewritten
        )
    }

    func setRulePinned(_ rule: VocabularyRule, pinned: Bool) {
        updateOverride(for: rule.id) { override in
            override.pinned = pinned
        }
    }

    func setRuleActive(_ rule: VocabularyRule, active: Bool) {
        updateOverride(for: rule.id) { override in
            override.active = active
        }
    }

    func updateRuleNotes(_ rule: VocabularyRule, notes: String) {
        updateOverride(for: rule.id) { override in
            override.notes = notes
        }
    }

    func saveManualRule(
        id: String?,
        type: VocabularyRuleType,
        term: String,
        replacementWords: [String],
        contexts: [String],
        notes: String,
        priority: Int,
        pinned: Bool
    ) {
        let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTerm.isEmpty else { return }

        let replacements = replacementWords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map {
                VocabularyReplacementOption(
                    word: $0,
                    useWhen: "Manual focus word added from the Writing Awareness workspace.",
                    caution: "Keep it only where it genuinely makes the sentence clearer."
                )
            }

        let manualRule = VocabularyRule(
            id: id ?? "manual:\(UUID().uuidString.lowercased())",
            type: type,
            term: normalizedTerm,
            replacementOptions: replacements,
            contexts: contexts.filter { !$0.isEmpty },
            source: .manual,
            active: true,
            priority: max(1, min(5, priority)),
            notes: notes,
            family: "manual",
            pinned: pinned
        )

        if let index = state.manualRules.firstIndex(where: { $0.id == manualRule.id }) {
            state.manualRules[index] = manualRule
        } else {
            state.manualRules.append(manualRule)
        }

        persistState()
        rebuildRules()
    }

    func deleteManualRule(id: String) {
        state.manualRules.removeAll { $0.id == id }
        persistState()
        rebuildRules()
    }

    private func startLearningWordDraftPreparation(
        term: String,
        sourceApp: String,
        contextLabel: String,
        origin: String,
        anchorRect: CGRect?
    ) {
        learningWordPreparationTask?.cancel()
        learningWordPreparationTask = Task { [weak self] in
            await self?.prepareLearningWordDraftAsync(
                term: term,
                sourceApp: sourceApp,
                contextLabel: contextLabel,
                origin: origin,
                anchorRect: anchorRect
            )
        }
    }

    func prepareLearningWordDraftAsync(
        term: String,
        sourceApp: String,
        contextLabel: String,
        origin: String,
        anchorRect: CGRect?
    ) async {
        if let existingDraft = existingLearningWordDraft(
            for: term,
            targetRuleID: nil,
            familyID: nil,
            sourceApp: sourceApp,
            contextLabel: contextLabel,
            origin: origin,
            anchorRect: anchorRect
        ) {
            openLearningWordReview(with: existingDraft)
            return
        }

        let refreshResult = await refreshLearningWordSuggestionCandidates(
            targetTerm: term,
            sourceApp: sourceApp,
            contextLabel: contextLabel,
            excluding: []
        )
        guard !Task.isCancelled else { return }
        openLearningWordReview(
            with: LearningWordFamilyDraft(
                familyID: nil,
                targetRuleID: nil,
                targetTerm: term,
                suggestions: [],
                suggestedSuggestions: refreshResult.suggestions,
                sourceApp: sourceApp,
                contextLabel: contextLabel,
                origin: origin,
                anchorRect: anchorRect,
                notice: refreshResult.notice
            )
        )
    }

    private func openLearningWordReview(with draft: LearningWordFamilyDraft) {
        pendingLearningWordFamilyDraft = draft
        NotificationCenter.default.post(name: .openWritingWorkspace, object: nil)
        NotificationCenter.default.post(name: .openLearningTargetEditor, object: nil)
        if revealsLearningWordReview, let app = NSApp {
            app.showMainWindow()
        }
    }

    private func existingLearningWordDraft(
        for term: String,
        targetRuleID: String?,
        familyID: String?,
        sourceApp: String,
        contextLabel: String,
        origin: String,
        anchorRect: CGRect?
    ) -> LearningWordFamilyDraft? {
        let normalizedTerm = Self.normalizeComparableTerm(term)
        let explicitRule = targetRuleID.flatMap { id in
            state.manualRules.first(where: { $0.id == id })
        }
        let matchingFamilyID = explicitRule
            .flatMap { rule in
                Self.isLearningWordFamily(rule.family) ? rule.family : nil
            } ?? familyID.flatMap { candidate in
                Self.isLearningWordFamily(candidate) ? candidate : nil
            }

        let targetRule: VocabularyRule?
        if let explicitRule {
            if explicitRule.type == .target {
                targetRule = explicitRule
            } else if let matchingFamilyID {
                targetRule = state.manualRules.first(where: { $0.family == matchingFamilyID && $0.type == .target })
            } else {
                targetRule = nil
            }
        } else if let matchingFamilyID {
            targetRule = state.manualRules.first(where: { $0.family == matchingFamilyID && $0.type == .target })
        } else {
            targetRule = state.manualRules.first(where: {
                $0.type == .target && $0.normalizedTerm == normalizedTerm
            })
        }

        guard let targetRule else { return nil }

        let resolvedFamilyID = Self.isLearningWordFamily(targetRule.family) ? targetRule.family : matchingFamilyID
        let relatedRules = resolvedFamilyID.map { familyID in
            state.manualRules.filter { $0.family == familyID }
        } ?? [targetRule]
        let suggestions = relatedRules
            .filter { $0.type == .avoid }
            .sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
            .map(Self.learningWordSuggestion(from:))

        let notice = resolvedFamilyID == nil
            ? "\"\(targetRule.term)\" is already in your learning words. Add or revise the linked words below."
            : "\"\(targetRule.term)\" is already in your learning words. Review the linked words below."

        return LearningWordFamilyDraft(
            familyID: resolvedFamilyID,
            targetRuleID: targetRule.id,
            targetTerm: targetRule.term,
            suggestions: suggestions,
            suggestedSuggestions: [],
            sourceApp: sourceApp,
            contextLabel: contextLabel,
            origin: origin,
            anchorRect: anchorRect,
            notice: notice
        )
    }

    func refreshLearningWordSuggestionCandidates(
        targetTerm: String,
        sourceApp: String,
        contextLabel: String,
        excluding existingSuggestions: [LearningWordSuggestion]
    ) async -> LearningWordSuggestionRefreshResult {
        switch Self.normalizeLearningTargetText(targetTerm) {
        case let .failure(message, _):
            return LearningWordSuggestionRefreshResult(
                suggestions: [],
                notice: message
            )

        case let .success(normalizedTarget):
            let excludedTerms = Array(
                Set(
                    existingSuggestions.compactMap { suggestion in
                        Self.normalizedLearningWordSuggestionTerm(suggestion.term)
                    }
                )
            )

            do {
                let personalOveruseCounts = recentPersonalOveruseCounts(limit: 10)
                let suggestions = try await generateLearningWordSuggestions(
                    for: normalizedTarget,
                    sourceApp: sourceApp,
                    contextLabel: contextLabel,
                    personalOveruseCounts: personalOveruseCounts,
                    excludingTerms: excludedTerms
                ).filter { suggestion in
                    guard let normalizedSuggestion = Self.normalizedLearningWordSuggestionTerm(suggestion.term) else {
                        return false
                    }
                    return !excludedTerms.contains(normalizedSuggestion)
                }

                return LearningWordSuggestionRefreshResult(
                    suggestions: suggestions,
                    notice: suggestions.isEmpty
                        ? "No new AI suggestions right now. Add one manually or refresh again."
                        : "Click an AI suggestion to add it as a linked overused word."
                )
            } catch LearningWordGenerationError.apiKeyMissing {
                return LearningWordSuggestionRefreshResult(
                    suggestions: [],
                    notice: "OpenAI key not configured. Add linked words manually below."
                )
            } catch is CancellationError {
                return LearningWordSuggestionRefreshResult(
                    suggestions: [],
                    notice: nil
                )
            } catch {
                return LearningWordSuggestionRefreshResult(
                    suggestions: [],
                    notice: "Couldn't refresh linked words automatically. Add them manually below."
                )
            }
        }
    }

    private func buildLearningWordFamilySaveResult(
        for draft: LearningWordFamilyDraft,
        targetTerm: String
    ) -> LearningWordFamilySaveResult {
        let existingTargetRule = draft.targetRuleID.flatMap { id in
            state.manualRules.first(where: { $0.id == id && $0.type == .target })
        } ?? state.manualRules.first(where: {
            $0.type == .target && $0.normalizedTerm == Self.normalizeComparableTerm(targetTerm)
        })
        let resolvedFamilyID = draft.familyID.flatMap { familyID in
            Self.isLearningWordFamily(familyID) ? familyID : nil
        } ?? existingTargetRule.flatMap { rule in
            Self.isLearningWordFamily(rule.family) ? rule.family : nil
        } ?? Self.makeLearningWordFamilyID()

        let existingAvoidRulesByTerm = Dictionary(
            uniqueKeysWithValues: state.manualRules
                .filter { $0.family == resolvedFamilyID && $0.type == .avoid }
                .map { ($0.normalizedTerm, $0) }
        )

        let sanitizedSuggestions = sanitizeLearningWordSuggestions(
            draft.suggestions,
            targetTerm: targetTerm
        )
        let targetRule = VocabularyRule(
            id: existingTargetRule?.id ?? "manual:\(UUID().uuidString.lowercased())",
            type: .target,
            term: targetTerm,
            replacementOptions: Self.makeLearningTargetReplacements(for: targetTerm),
            contexts: [],
            source: .manual,
            active: true,
            priority: 5,
            notes: "",
            family: resolvedFamilyID,
            pinned: true
        )

        let avoidRules = sanitizedSuggestions.prefix(Self.maxLearningWordSuggestions).map { suggestion in
            let normalizedSuggestion = Self.normalizeComparableTerm(suggestion.term)
            let existingRule = existingAvoidRulesByTerm[normalizedSuggestion]
            return VocabularyRule(
                id: existingRule?.id ?? "manual:\(UUID().uuidString.lowercased())",
                type: .avoid,
                term: suggestion.term.trimmingCharacters(in: .whitespacesAndNewlines),
                replacementOptions: [
                    VocabularyReplacementOption(
                        word: targetTerm,
                        useWhen: suggestion.useWhen,
                        caution: suggestion.caution
                    )
                ],
                contexts: [],
                source: .manual,
                active: true,
                priority: 5,
                notes: suggestion.useWhen,
                family: resolvedFamilyID,
                pinned: true
            )
        }

        return LearningWordFamilySaveResult(
            familyID: resolvedFamilyID,
            targetRuleID: targetRule.id,
            rules: [targetRule] + avoidRules
        )
    }

    private func rulesToReplaceForLearningWordDraft(
        _ draft: LearningWordFamilyDraft,
        targetTerm: String
    ) -> Set<String> {
        let normalizedTarget = Self.normalizeComparableTerm(targetTerm)
        var ruleIDs = Set<String>()

        if let familyID = draft.familyID, Self.isLearningWordFamily(familyID) {
            ruleIDs.formUnion(state.manualRules.filter { $0.family == familyID }.map(\.id))
        }

        if let targetRuleID = draft.targetRuleID {
            ruleIDs.insert(targetRuleID)
            if let existingRule = state.manualRules.first(where: { $0.id == targetRuleID }),
               Self.isLearningWordFamily(existingRule.family) {
                ruleIDs.formUnion(state.manualRules.filter { $0.family == existingRule.family }.map(\.id))
            }
        }

        for rule in state.manualRules where rule.type == .target && rule.normalizedTerm == normalizedTarget {
            ruleIDs.insert(rule.id)
            if Self.isLearningWordFamily(rule.family) {
                ruleIDs.formUnion(state.manualRules.filter { $0.family == rule.family }.map(\.id))
            }
        }

        return ruleIDs
    }

    private func sanitizeLearningWordSuggestions(
        _ suggestions: [LearningWordSuggestion],
        targetTerm: String
    ) -> [LearningWordSuggestion] {
        let normalizedTarget = Self.normalizeComparableTerm(targetTerm)
        let mutedTerms = Set(state.mutedTerms.map(Self.normalizeComparableTerm))
        var seenTerms = Set<String>()
        var sanitized: [LearningWordSuggestion] = []

        for suggestion in suggestions {
            guard let normalizedSuggestion = Self.normalizedLearningWordSuggestionTerm(suggestion.term),
                  normalizedSuggestion != normalizedTarget,
                  !mutedTerms.contains(normalizedSuggestion),
                  seenTerms.insert(normalizedSuggestion).inserted else {
                continue
            }

            let trimmedUseWhen = suggestion.useWhen.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedCaution = suggestion.caution.trimmingCharacters(in: .whitespacesAndNewlines)
            sanitized.append(
                LearningWordSuggestion(
                    term: suggestion.term.trimmingCharacters(in: .whitespacesAndNewlines),
                    useWhen: trimmedUseWhen.isEmpty
                        ? "Use this when \"\(targetTerm)\" is genuinely more precise than the original wording."
                        : trimmedUseWhen,
                    caution: trimmedCaution.isEmpty
                        ? "Skip it if the sentence becomes forced."
                        : trimmedCaution,
                    matchedPersonalHistory: suggestion.matchedPersonalHistory
                )
            )
        }

        return Array(sanitized.prefix(Self.maxLearningWordSuggestions))
    }

    private func learningWordTargetTerm(for rule: VocabularyRule) -> String {
        guard rule.type == .avoid,
              Self.isLearningWordFamily(rule.family),
              let targetRule = state.manualRules.first(where: { $0.family == rule.family && $0.type == .target }) else {
            return rule.term
        }
        return targetRule.term
    }

    private func recentPersonalOveruseCounts(limit: Int) -> [(term: String, count: Int)] {
        let cutoffDate = calendar.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        let counts = state.reinforcementEvents.reduce(into: [String: Int]()) { result, event in
            guard event.kind == .avoidCaught, event.createdAt >= cutoffDate else { return }
            let normalizedTerm = Self.normalizeComparableTerm(event.term)
            guard !normalizedTerm.isEmpty else { return }
            result[normalizedTerm, default: 0] += 1
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }

    func generateLearningWordSuggestions(
        for targetTerm: String,
        sourceApp: String,
        contextLabel: String,
        personalOveruseCounts: [(term: String, count: Int)],
        excludingTerms: [String] = []
    ) async throws -> [LearningWordSuggestion] {
        let personalTermSet = Set(personalOveruseCounts.map(\.term))

        if let learningWordSuggestionGenerator {
            let suggestions = try await learningWordSuggestionGenerator(
                targetTerm,
                sourceApp,
                contextLabel,
                personalOveruseCounts,
                excludingTerms
            ).map { suggestion in
                var matchedSuggestion = suggestion
                matchedSuggestion.matchedPersonalHistory =
                    matchedSuggestion.matchedPersonalHistory ||
                    personalTermSet.contains(Self.normalizeComparableTerm(suggestion.term))
                return matchedSuggestion
            }

            return rankLearningWordSuggestions(
                sanitizeLearningWordSuggestions(suggestions, targetTerm: targetTerm)
            )
        }

        let apiKey = KeychainHelper.shared.getAPIKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty else {
            throw LearningWordGenerationError.apiKeyMissing
        }

        let overuseSummary = personalOveruseCounts.isEmpty
            ? "No personal overuse history is available yet."
            : personalOveruseCounts
                .map { "\"\($0.term)\" (\($0.count)x)" }
                .joined(separator: ", ")
        let excludedSummary = excludingTerms.isEmpty
            ? "None."
            : excludingTerms
                .sorted()
                .map { "\"\($0)\"" }
                .joined(separator: ", ")

        let openAI = OpenAI(apiToken: apiKey)
        let query = ChatQuery(
            messages: [
                .developer(
                    .init(
                        content: .textContent(
                            """
                            You are generating linked vocabulary coaching rules for a writing coach.
                            Return up to five overused words or short phrases that the saved target word can replace naturally.
                            Favor common vague words over rare jargon.
                            Keep each suggested term to four words or fewer.
                            Do not return any term from the excluded list.
                            Do not return the target itself, close inflections of the target, antonyms, or words the target would not naturally replace.
                            Use the personal overuse history only as ranking guidance, not as a hard requirement.
                            """
                        )
                    )
                ),
                .user(
                    .init(
                        content: .string(
                            """
                            Target word: \(targetTerm)
                            Source app: \(sourceApp)
                            Context label: \(contextLabel)
                            Personal overuse history: \(overuseSummary)
                            Excluded terms: \(excludedSummary)

                            Produce suggestions that help the user replace overused wording with "\(targetTerm)" in normal writing.
                            """
                        )
                    )
                )
            ],
            model: .gpt4_1_mini,
            maxCompletionTokens: 600,
            responseFormat: .derivedJsonSchema(
                name: "learning-word-suggestions",
                type: GeneratedLearningWordSuggestions.self
            ),
            temperature: 0.3
        )

        let result = try await openAI.chats(query: query)
        guard !Task.isCancelled else {
            throw CancellationError()
        }
        guard let content = result.choices.first?.message.content,
              let data = content.data(using: String.Encoding.utf8) else {
            throw LearningWordGenerationError.emptyResponse
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode(GeneratedLearningWordSuggestions.self, from: data)
        let suggestions = payload.suggestions.map { suggestion in
            LearningWordSuggestion(
                term: suggestion.term,
                useWhen: suggestion.useWhen,
                caution: suggestion.caution,
                matchedPersonalHistory: personalTermSet.contains(Self.normalizeComparableTerm(suggestion.term))
            )
        }

        return rankLearningWordSuggestions(
            sanitizeLearningWordSuggestions(suggestions, targetTerm: targetTerm)
        )
    }

    private func rankLearningWordSuggestions(
        _ suggestions: [LearningWordSuggestion]
    ) -> [LearningWordSuggestion] {
        suggestions
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.matchedPersonalHistory != rhs.element.matchedPersonalHistory {
                    return lhs.element.matchedPersonalHistory && !rhs.element.matchedPersonalHistory
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private func presentLearningTargetLoadingHUD(term: String, anchorRect: CGRect?) {
        NotificationCenter.default.post(
            name: .showLearningTargetHUD,
            object: LearningTargetHUDRequest(
                titleOverride: "Preparing Linked Words",
                result: LearningTargetSaveResult(
                    status: .saved,
                    term: term,
                    ruleID: nil,
                    familyID: nil,
                    message: "Generating linked words for \"\(term)\"...",
                    anchorRect: anchorRect
                ),
                showUndo: false,
                onUndo: nil,
                onEdit: nil
            )
        )
    }

    private func learningWordSavedMessage(term: String, origin: String) -> String {
        origin == "service"
            ? "Saved \"\(term)\" to your learning words."
            : "Saved \"\(term)\" to your learning words from the \(origin)."
    }

    func saveRepair(
        rawSentence: String,
        improvedSentence: String,
        replacementWord: String,
        ruleIDs: [String],
        sourceApp: String,
        reusedSameDay: Bool,
        audioMemoPath: String?
    ) {
        let trimmedRaw = rawSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedImproved = improvedSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty, !trimmedImproved.isEmpty else { return }

        let entry = RepairEntry(
            id: UUID(),
            capturedAt: .now,
            sourceApp: sourceApp,
            rawSentence: trimmedRaw,
            improvedSentence: trimmedImproved,
            ruleIds: ruleIDs,
            replacementWord: replacementWord.trimmingCharacters(in: .whitespacesAndNewlines),
            reusedSameDay: reusedSameDay,
            audioMemoPath: audioMemoPath
        )
        state.repairs.append(entry)
        state.reinforcementEvents.append(
            ReinforcementEvent(
                id: UUID(),
                term: entry.replacementWord.isEmpty ? "repair" : entry.replacementWord,
                kind: .repairCompleted,
                context: lensContextLabel,
                createdAt: .now
            )
        )
        persistState()
        rebuildRules()
    }

    private var liveAvoidRules: [VocabularyRule] {
        rules.filter {
            $0.type == .avoid &&
            $0.active &&
            ($0.family == focusPack.weeklyFamily || $0.pinned || $0.source == .manual)
        }
    }

    private var liveTargetRules: [VocabularyRule] {
        rules.filter {
            $0.type == .target &&
            $0.active &&
            (
                liveTargetTerms.contains($0.normalizedTerm) ||
                $0.pinned ||
                $0.source == .manual ||
                $0.family == focusPack.weeklyFamily
            )
        }
    }

    private var liveTargetTerms: Set<String> {
        Set(focusPack.targetWords.map { $0.lowercased() })
    }

    private func rebuildRules() {
        var mergedRules = seed.rules.map(Self.applyDefaultCasing)
        for index in mergedRules.indices {
            if let override = state.ruleOverrides[mergedRules[index].id] {
                if let active = override.active {
                    mergedRules[index].active = active
                }
                if let priority = override.priority {
                    mergedRules[index].priority = priority
                }
                if let notes = override.notes {
                    mergedRules[index].notes = notes
                }
                if let pinned = override.pinned {
                    mergedRules[index].pinned = pinned
                }
            }
        }
        mergedRules.append(contentsOf: state.manualRules)
        mergedRules.sort { lhs, rhs in
            if lhs.pinned != rhs.pinned {
                return lhs.pinned && !rhs.pinned
            }
            if lhs.priority == rhs.priority {
                if lhs.type == rhs.type {
                    return lhs.term < rhs.term
                }
                return lhs.type.rawValue < rhs.type.rawValue
            }
            return lhs.priority > rhs.priority
        }
        rules = mergedRules
    }

    private func persistState() {
        storageManager.saveState(state)
    }

    private func updateOverride(for ruleID: String, mutate: (inout VocabularyRuleOverride) -> Void) {
        var override = state.ruleOverrides[ruleID] ?? VocabularyRuleOverride()
        mutate(&override)
        state.ruleOverrides[ruleID] = override
        persistState()
        rebuildRules()
    }

    private func recordEvents(for result: WritingCheckResult) {
        let dayKey = Self.dayKey(for: .now)
        let normalizedText = result.inputText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        for match in result.flaggedTerms.prefix(3) {
            let fingerprint = "avoid|\(match.ruleId)|\(dayKey)|\(normalizedText.prefix(120))"
            guard analysisFingerprints.insert(fingerprint).inserted else { continue }
            state.reinforcementEvents.append(
                ReinforcementEvent(
                    id: UUID(),
                    term: match.term,
                    kind: .avoidCaught,
                    context: lensContextLabel,
                    createdAt: .now
                )
            )
        }

        for match in result.rewardedTerms.prefix(2) {
            let fingerprint = "target|\(match.ruleId)|\(dayKey)|\(normalizedText.prefix(120))"
            guard analysisFingerprints.insert(fingerprint).inserted else { continue }
            state.reinforcementEvents.append(
                ReinforcementEvent(
                    id: UUID(),
                    term: match.term,
                    kind: .targetUsedWell,
                    context: lensContextLabel,
                    createdAt: .now
                )
            )
        }

        persistState()
    }

    private func presentLearningTargetHUD(for result: LearningTargetSaveResult) {
        let canEdit = result.status != .invalid && !result.term.isEmpty
        let request = LearningTargetHUDRequest(
            titleOverride: nil,
            result: result,
            showUndo: result.status == .saved,
            onUndo: { [weak self] in
                guard let self, let ruleID = result.ruleID else { return }
                self.undoLearningTarget(ruleID: ruleID, familyID: result.familyID)
                let undoResult = LearningTargetSaveResult(
                    status: .saved,
                    term: result.term,
                    ruleID: nil,
                    familyID: nil,
                    message: "Removed \"\(result.term)\" from your learning words.",
                    anchorRect: result.anchorRect
                )
                NotificationCenter.default.post(
                    name: .showLearningTargetHUD,
                    object: LearningTargetHUDRequest(
                        titleOverride: "Removed from Learning Words",
                        result: undoResult,
                        showUndo: false,
                        onUndo: nil,
                        onEdit: nil
                    )
                )
            },
            onEdit: canEdit ? { [weak self] in
                self?.openLearningTargetEditor(term: result.term, ruleID: result.ruleID, familyID: result.familyID)
            } : nil
        )
        NotificationCenter.default.post(name: .showLearningTargetHUD, object: request)
    }

    private static func loadSeed() -> WritingAwarenessSeed {
        guard let url = Bundle.main.url(forResource: "WritingAwarenessSeed", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return .fallback()
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WritingAwarenessSeed.self, from: data)
        } catch {
            print("⚠️ Failed to decode WritingAwarenessSeed.json: \(error)")
            return .fallback()
        }
    }

    private static func resolveFocusPack(from seed: WritingAwarenessSeed, date: Date) -> FocusPack {
        guard let template = Self.focusTemplate(from: seed, date: date) else {
            return WritingAwarenessSeed.fallback().focusTemplates[0].makePack(for: date)
        }
        return template.makePack(for: Calendar.autoupdatingCurrent.startOfDay(for: date))
    }

    private static func focusTemplate(from seed: WritingAwarenessSeed, date: Date) -> FocusTemplate? {
        guard !seed.focusTemplates.isEmpty else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        let weekOfYear = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let index = abs((weekOfYear + year) % seed.focusTemplates.count)
        return seed.focusTemplates[index]
    }

    private static func applyDefaultCasing(to rule: VocabularyRule) -> VocabularyRule {
        var mutableRule = rule
        mutableRule.term = mutableRule.term.trimmingCharacters(in: .whitespacesAndNewlines)
        return mutableRule
    }

    private func issueSpans(for result: WritingCheckResult) -> [WritingIssueSpan] {
        let suggestionLookup = Dictionary(uniqueKeysWithValues: result.suggestedReplacements.map { ($0.ruleId, $0) })

        let avoidSpans = result.flaggedTerms.map { match in
            let suggestion = suggestionLookup[match.ruleId]
            return WritingIssueSpan(
                id: "avoid:\(match.id)",
                kind: .avoid,
                ruleID: match.ruleId,
                term: match.term,
                rangeLower: match.rangeLower,
                rangeUpper: match.rangeUpper,
                message: suggestion?.message ?? "Use a more precise word here.",
                snippet: match.snippet,
                replacements: suggestion?.replacements ?? []
            )
        }

        let rewardSpans = result.rewardedTerms.map { match in
            WritingIssueSpan(
                id: "reward:\(match.id)",
                kind: .reward,
                ruleID: match.ruleId,
                term: match.term,
                rangeLower: match.rangeLower,
                rangeUpper: match.rangeUpper,
                message: "Strong word choice here.",
                snippet: match.snippet,
                replacements: []
            )
        }

        return (avoidSpans + rewardSpans).sorted { lhs, rhs in
            if lhs.rangeLower == rhs.rangeLower {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return lhs.rangeLower < rhs.rangeLower
        }
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static let maxLearningWordSuggestions = 5

    enum LearningWordGenerationError: Error {
        case apiKeyMissing
        case emptyResponse
    }

    private struct GeneratedLearningWordSuggestions: JSONSchemaConvertible {
        var suggestions: [GeneratedLearningWordSuggestion]

        static var example: GeneratedLearningWordSuggestions {
            GeneratedLearningWordSuggestions(
                suggestions: [
                    GeneratedLearningWordSuggestion(
                        term: "good",
                        useWhen: "Replace a vague positive word with the target when the stronger term fits the claim.",
                        caution: "Skip it when the stronger word would overstate the point."
                    ),
                    GeneratedLearningWordSuggestion(
                        term: "interesting",
                        useWhen: "Use the target when you want a more specific reaction than generic interest.",
                        caution: "Do not force it into casual or neutral sentences."
                    )
                ]
            )
        }
    }

    private struct GeneratedLearningWordSuggestion: Codable, Hashable {
        var term: String
        var useWhen: String
        var caution: String
    }

    private enum LearningTargetNormalizationResult {
        case success(String)
        case failure(String, String)
    }

    private static func normalizeLearningTargetText(_ rawText: String) -> LearningTargetNormalizationResult {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure("Select a word or short phrase first.", "")
        }

        if trimmed.contains(where: \.isNewline) {
            return .failure("Only a single line can be added to learning words.", trimmed)
        }

        let collapsed = trimmed
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let cleaned = stripLearningTargetBoundaryCharacters(from: collapsed)

        guard !cleaned.isEmpty else {
            return .failure("Select a word or short phrase first.", "")
        }

        let words = cleaned.split(separator: " ")
        guard words.count <= 4 else {
            return .failure("Learning words can be up to four words long.", cleaned)
        }

        guard cleaned.count <= 80 else {
            return .failure("Learning words must stay under 80 characters.", cleaned)
        }

        return .success(cleaned)
    }

    private static func makeLearningTargetReplacements(for term: String) -> [VocabularyReplacementOption] {
        [
            VocabularyReplacementOption(
                word: term,
                useWhen: "Use this when it makes the sentence more precise and natural.",
                caution: "Keep it only where it genuinely improves the wording."
            )
        ]
    }

    private static func stripLearningTargetBoundaryCharacters(from value: String) -> String {
        var scalars = Array(value.unicodeScalars)
        let boundaryCharacters = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)

        while let first = scalars.first, boundaryCharacters.contains(first) {
            scalars.removeFirst()
        }
        while let last = scalars.last, boundaryCharacters.contains(last) {
            scalars.removeLast()
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func learningWordSuggestion(from rule: VocabularyRule) -> LearningWordSuggestion {
        let option = rule.replacementOptions.first
        return LearningWordSuggestion(
            term: rule.term,
            useWhen: option?.useWhen ?? rule.notes,
            caution: option?.caution ?? "Skip it if the sentence becomes forced.",
            matchedPersonalHistory: false
        )
    }

    private static func normalizeComparableTerm(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedLearningWordSuggestionTerm(_ value: String) -> String? {
        let collapsed = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let cleaned = stripLearningTargetBoundaryCharacters(from: collapsed)
        guard !cleaned.isEmpty else { return nil }
        let wordCount = cleaned.split(separator: " ").count
        guard wordCount > 0, wordCount <= 4, cleaned.count <= 80 else { return nil }
        return normalizeComparableTerm(cleaned)
    }

    private static func makeLearningWordFamilyID() -> String {
        "manual-learning:\(UUID().uuidString.lowercased())"
    }

    private static func isLearningWordFamily(_ familyID: String) -> Bool {
        familyID.hasPrefix("manual-learning:")
    }

    private static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func matches(for rule: VocabularyRule, in text: String) -> [WritingMatch] {
        let pattern = "(?<![A-Za-z])\(NSRegularExpression.escapedPattern(for: rule.term))(?![A-Za-z])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).enumerated().compactMap { index, match in
            guard match.range.location != NSNotFound else { return nil }
            let snippet = Self.snippet(in: text, range: match.range)
            return WritingMatch(
                id: "\(rule.id):\(index)",
                ruleId: rule.id,
                term: nsText.substring(with: match.range).lowercased(),
                family: rule.family,
                rangeLower: match.range.location,
                rangeUpper: match.range.location + match.range.length,
                snippet: snippet,
                replacement: rule.primaryReplacement
            )
        }
    }

    private static func rewardableMatches(for rule: VocabularyRule, matches: [WritingMatch], wordCount: Int) -> [WritingMatch] {
        guard !matches.isEmpty else { return [] }
        let density = Double(matches.count) / Double(max(1, wordCount))
        if matches.count > 2 || density > 0.06 {
            return []
        }

        if matches.count > 1 {
            let distances = zip(matches, matches.dropFirst()).map { $1.rangeLower - $0.rangeUpper }
            if distances.contains(where: { $0 < 10 }) {
                return []
            }
        }
        return matches
    }

    private static func rewrite(text: String, using result: WritingCheckResult, rules: [VocabularyRule]) -> String {
        let nsText = NSMutableString(string: text)
        let ruleLookup = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
        let replacements = result.flaggedTerms.sorted { $0.rangeLower > $1.rangeLower }

        for match in replacements.prefix(3) {
            guard let rule = ruleLookup[match.ruleId] else { continue }
            let replacement = replacementText(for: rule, matchedTerm: match.term)
            let range = NSRange(location: match.rangeLower, length: match.rangeUpper - match.rangeLower)
            nsText.replaceCharacters(in: range, with: replacement)
        }

        var rewritten = nsText as String
        rewritten = rewritten.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        rewritten = rewritten.replacingOccurrences(of: "\\s+([,.;!?])", with: "$1", options: .regularExpression)
        rewritten = rewritten.replacingOccurrences(of: "\\(\\s+", with: "(", options: .regularExpression)
        rewritten = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
        return rewritten
    }

    private static func replacementText(for rule: VocabularyRule, matchedTerm: String) -> String {
        switch rule.family {
        case "really_very", "kind_of_sort_of":
            return ""
        case "you_know":
            return "for example"
        case "i_think_feel_guess":
            return "the core point is"
        default:
            return rule.primaryReplacement ?? matchedTerm
        }
    }

    private static func snippet(in text: String, range: NSRange, radius: Int = 48) -> String {
        let nsText = text as NSString
        let start = max(0, range.location - radius)
        let end = min(nsText.length, range.location + range.length + radius)
        let excerptRange = NSRange(location: start, length: end - start)
        var excerpt = nsText.substring(with: excerptRange).trimmingCharacters(in: .whitespacesAndNewlines)
        if start > 0 {
            excerpt = "…\(excerpt)"
        }
        if end < nsText.length {
            excerpt = "\(excerpt)…"
        }
        return excerpt
    }

    private var browserNativeHostInstalled: Bool {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let candidateDirectories = [
            homeDirectory.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts"),
            homeDirectory.appendingPathComponent("Library/Application Support/Chromium/NativeMessagingHosts"),
            homeDirectory.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"),
            homeDirectory.appendingPathComponent("Library/Application Support/Microsoft Edge/NativeMessagingHosts"),
            homeDirectory.appendingPathComponent("Library/Application Support/Mozilla/NativeMessagingHosts")
        ]

        return candidateDirectories.contains { directory in
            let manifestURL = directory.appendingPathComponent("studio.orbitlabs.audora.writing.json")
            return FileManager.default.fileExists(atPath: manifestURL.path)
        }
    }
}
