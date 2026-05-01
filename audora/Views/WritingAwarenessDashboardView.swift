import AppKit
import SwiftUI

struct WritingAwarenessDashboardView: View {
    @ObservedObject private var manager = WritingAwarenessManager.shared
    @ObservedObject private var systemWideWritingMonitor = SystemWideWritingMonitor.shared
    @State private var editorDraft = ManualRuleEditorDraft.blank()
    @State private var learningWordDraft = LearningWordFamilyDraft(
        familyID: nil,
        targetRuleID: nil,
        targetTerm: "",
        suggestions: [],
        suggestedSuggestions: [],
        sourceApp: "Writing Awareness",
        contextLabel: "Writing Awareness",
        origin: "editor",
        anchorRect: nil,
        notice: nil
    )
    @State private var showingRuleEditor = false
    @State private var showingLearningWordEditor = false

    private let columns = [
        GridItem(.flexible(minimum: 220), spacing: 16),
        GridItem(.flexible(minimum: 220), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard
                LazyVGrid(columns: columns, spacing: 16) {
                    preloadCard
                    permissionCard
                    contextBankCard
                    activeRulesCard
                    manualRulesCard
                    ruleLibraryCard
                    repairsCard
                }
            }
            .padding(24)
        }
        .background(WritingCanvasBackground())
        .navigationTitle("Writing Awareness")
        .sheet(isPresented: $showingRuleEditor) {
            ManualRuleEditorView(draft: editorDraft) { draft in
                manager.saveManualRule(
                    id: draft.ruleID,
                    type: draft.type,
                    term: draft.term,
                    replacementWords: draft.replacementWords,
                    contexts: draft.contexts,
                    notes: draft.notes,
                    priority: draft.priority,
                    pinned: draft.pinned
                )
            }
        }
        .sheet(isPresented: $showingLearningWordEditor) {
            LearningWordFamilyEditorView(
                draft: learningWordDraft,
                onRefreshSuggestions: { targetTerm, excludedSuggestions in
                    await manager.refreshLearningWordSuggestionCandidates(
                        targetTerm: targetTerm,
                        sourceApp: learningWordDraft.sourceApp,
                        contextLabel: learningWordDraft.contextLabel,
                        excluding: excludedSuggestions
                    )
                },
                onSave: { draft in
                    manager.commitLearningWordFamily(draft)
                }
            )
        }
        .onAppear {
            openPendingEditorIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLearningTargetEditor)) { _ in
            openPendingEditorIfNeeded()
        }
    }

    private var heroCard: some View {
        WritingSurfaceCard(
            title: "Daily Writing Awareness",
            subtitle: "Local-first coaching for the current weekly focus."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(manager.activeFocusTitle)
                            .font(.system(size: 30, weight: .bold, design: .rounded))

                        Text(manager.focusPack.triggerQuestion)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 10) {
                        Button {
                            WritingLensWindowManager.shared.show(captureSelection: true)
                        } label: {
                            Label("Open Writing Lens", systemImage: "text.viewfinder")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            manager.requestAccessibilityAccess()
                        } label: {
                            Label(
                                manager.isAccessibilityTrusted ? "Accessibility Ready" : "Enable Accessibility",
                                systemImage: manager.isAccessibilityTrusted ? "checkmark.shield" : "hand.raised"
                            )
                        }
                        .buttonStyle(.bordered)

                        Button {
                            if manager.isInputMonitoringTrusted {
                                if systemWideWritingMonitor.isRunning {
                                    systemWideWritingMonitor.stop()
                                } else {
                                    systemWideWritingMonitor.start()
                                }
                            } else {
                                manager.requestInputMonitoringAccess()
                            }
                        } label: {
                            Label(
                                manager.isInputMonitoringTrusted
                                    ? (systemWideWritingMonitor.isRunning ? "Pause Live Coach" : "Resume Live Coach")
                                    : "Enable Input Monitoring",
                                systemImage: manager.isInputMonitoringTrusted ? "waveform.and.magnifyingglass" : "keyboard.badge.eye"
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    WritingMetricTile(value: "\(manager.currentSummary.avoidCaught)", label: "Avoid Catches")
                    WritingMetricTile(value: "\(manager.currentSummary.targetWins)", label: "Target Wins")
                    WritingMetricTile(value: "\(manager.currentSummary.repairsCompleted)", label: "Repairs")
                    WritingMetricTile(value: systemWideWritingMonitor.isRunning ? "Live" : "Paused", label: "Coach")
                }
            }
        }
    }

    private var preloadCard: some View {
        WritingSurfaceCard(
            title: "Daily Preload",
            subtitle: "Keep the active family small so the words stay retrievable."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target words")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    flowChips(manager.focusPack.targetWords, tone: .target)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Banned defaults")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    flowChips(manager.focusPack.bannedTerms, tone: .avoid)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Example rewrite")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(manager.focusPack.exampleRewrite)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                }
            }
        }
    }

    private var permissionCard: some View {
        WritingSurfaceCard(
            title: "System Coverage",
            subtitle: "The live coach can read broadly, but replacement only appears where the focused field exposes writable Accessibility text APIs."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    WritingChip(
                        text: manager.isAccessibilityTrusted ? "Accessibility Ready" : "Accessibility Missing",
                        tone: manager.isAccessibilityTrusted ? .success : .avoid
                    )
                    WritingChip(
                        text: manager.isInputMonitoringTrusted ? "Input Monitoring Ready" : "Input Monitoring Missing",
                        tone: manager.isInputMonitoringTrusted ? .success : .avoid
                    )
                }

                HStack {
                    WritingChip(
                        text: manager.liveCapability.shortLabel,
                        tone: manager.liveCapability.canReplaceSelection ? .success : .neutral
                    )
                    if systemWideWritingMonitor.isRunning {
                        WritingChip(text: "Live Coach Running", tone: .target)
                    } else {
                        WritingChip(text: "Live Coach Paused", tone: .neutral)
                    }
                }

                Text(manager.liveCapability.explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text("Overlay-only fields still get live suggestions and an anchored coach bubble; replaceable fields can accept a direct quick replace.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var contextBankCard: some View {
        let banks = Array(manager.focusContextBanks.prefix(3))
        return WritingSurfaceCard(
            title: "Context Banks",
            subtitle: "Words that fit the contexts where your transcripts spend the most time."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(banks.enumerated()), id: \.element.id) { index, bank in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(bank.context.capitalized)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Spacer()
                            Text("\(bank.noteCount) notes")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        flowChips(bank.words.prefix(4).map(\.word), tone: .neutral)

                        if let example = bank.words.first?.example {
                            Text(example)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if index < banks.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var activeRulesCard: some View {
        WritingSurfaceCard(
            title: "Active Rules",
            subtitle: "Only the focus family, pinned rules, and manual rules run live."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if manager.focusAvoidRules.isEmpty && manager.focusTargetRules.isEmpty {
                    Text("No active rules were resolved for this focus pack.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    if !manager.focusAvoidRules.isEmpty {
                        Text("Avoid")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(manager.focusAvoidRules.prefix(6)) { rule in
                            ruleRow(rule)
                        }
                    }

                    if !manager.focusTargetRules.isEmpty {
                        Divider()
                        Text("Reward")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(manager.focusTargetRules.prefix(6)) { rule in
                            ruleRow(rule)
                        }
                    }
                }
            }
        }
    }

    private var manualRulesCard: some View {
        WritingSurfaceCard(
            title: "Manual Rules",
            subtitle: "Add your own bad-word to better-word pairs without losing them on future corpus refreshes."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(manager.manualRules.count) saved")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        openEditor(with: .blank())
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                if manager.manualRules.isEmpty {
                    Text("No manual rules yet. Add one for a word you want to catch everywhere or a target word you want reinforced.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    let manualRules = manager.manualRules
                    ForEach(Array(manualRules.enumerated()), id: \.element.id) { index, rule in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    WritingChip(text: rule.type == .avoid ? "Avoid" : "Target", tone: rule.type == .avoid ? .avoid : .target)
                                    if manager.isLearningWordRule(rule) {
                                        WritingChip(text: "Learning", tone: .success)
                                    }
                                    Text(rule.term)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                }

                                if !rule.replacementOptions.isEmpty {
                                    flowChips(rule.replacementOptions.map(\.word), tone: .neutral)
                                }

                                if !rule.notes.isEmpty {
                                    Text(rule.notes)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 8) {
                                Button("Edit") {
                                    if manager.isLearningWordRule(rule) {
                                        manager.openLearningTargetEditor(for: rule)
                                    } else {
                                        openEditor(with: ManualRuleEditorDraft(rule: rule))
                                    }
                                }
                                .buttonStyle(.borderless)

                                Button("Delete", role: .destructive) {
                                    if manager.isLearningWordRule(rule) {
                                        manager.deleteLearningWordFamily(
                                            familyID: rule.family,
                                            targetRuleID: rule.type == .target ? rule.id : nil
                                        )
                                    } else {
                                        manager.deleteManualRule(id: rule.id)
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        if index < manualRules.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var ruleLibraryCard: some View {
        let derivedRules = Array(manager.topDerivedRules.prefix(8))
        return WritingSurfaceCard(
            title: "Corpus Rule Library",
            subtitle: "Seeded from the transcript lab and available for pinning or muting."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(derivedRules.enumerated()), id: \.element.id) { index, rule in
                    ruleRow(rule)
                    if index < derivedRules.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var repairsCard: some View {
        let repairs = Array(manager.recentRepairs.prefix(5))
        return WritingSurfaceCard(
            title: "Recent Repairs",
            subtitle: "Saved rewrites and memo-backed repairs from the lens."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if manager.recentRepairs.isEmpty {
                    Text("No repairs saved yet. Capture one weak sentence in the lens and save the improved version.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(repairs.enumerated()), id: \.element.id) { index, repair in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(repair.sourceApp)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(repair.capturedAt, style: .date)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Text(repair.rawSentence)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)

                            Text(repair.improvedSentence)
                                .font(.system(size: 14, weight: .semibold))

                            HStack(spacing: 8) {
                                if !repair.replacementWord.isEmpty {
                                    WritingChip(text: repair.replacementWord, tone: .success)
                                }
                                if repair.reusedSameDay {
                                    WritingChip(text: "Reused same day", tone: .success)
                                }
                            }
                        }

                        if index < repairs.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func ruleRow(_ rule: VocabularyRule) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    WritingChip(text: rule.type == .avoid ? "Avoid" : "Target", tone: rule.type == .avoid ? .avoid : .target)
                    Text(rule.term)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    if rule.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if !rule.replacementOptions.isEmpty {
                    flowChips(rule.replacementOptions.prefix(3).map(\.word), tone: .neutral)
                }

                if !rule.notes.isEmpty {
                    Text(rule.notes)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Button(rule.pinned ? "Unpin" : "Pin") {
                    manager.setRulePinned(rule, pinned: !rule.pinned)
                }
                .buttonStyle(.borderless)

                Button(rule.active ? "Mute" : "Activate") {
                    manager.setRuleActive(rule, active: !rule.active)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func flowChips<S: Sequence>(_ values: S, tone: WritingChip.Tone) -> some View where S.Element == String {
        let items = Array(values)
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items.chunked(into: 3), id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { value in
                            WritingChip(text: value, tone: tone)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func openEditor(with draft: ManualRuleEditorDraft) {
        editorDraft = draft
        showingRuleEditor = true
    }

    private func openLearningWordEditor(with draft: LearningWordFamilyDraft) {
        learningWordDraft = draft
        showingLearningWordEditor = true
    }

    private func openPendingEditorIfNeeded() {
        if let draft = manager.consumePendingLearningWordFamilyDraft() {
            openLearningWordEditor(with: draft)
            return
        }
        guard let draft = manager.consumePendingManualRuleEditorDraft() else { return }
        openEditor(with: draft)
    }
}

private struct ManualRuleEditorView: View {
    let draft: ManualRuleEditorDraft
    let onSave: (ManualRuleEditorDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var type: VocabularyRuleType = .avoid
    @State private var term = ""
    @State private var replacementCSV = ""
    @State private var contextsCSV = ""
    @State private var notes = ""
    @State private var priority = 3
    @State private var pinned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.ruleID == nil ? "New Manual Rule" : "Edit Manual Rule")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Picker("Type", selection: $type) {
                ForEach(VocabularyRuleType.allCases) { value in
                    Text(value.rawValue.capitalized).tag(value)
                }
            }
            .pickerStyle(.segmented)

            WritingAwareTextField(
                text: $term,
                surfaceID: "manual-rule-term",
                placeholder: "Word or phrase",
                contextLabel: "Manual Rule Term"
            )
            .frame(height: 36)

            WritingAwareTextField(
                text: $replacementCSV,
                surfaceID: "manual-rule-replacements",
                placeholder: "Replacement words (comma separated)",
                contextLabel: "Manual Rule Replacements"
            )
            .frame(height: 36)

            WritingAwareTextField(
                text: $contextsCSV,
                surfaceID: "manual-rule-contexts",
                placeholder: "Contexts (comma separated)",
                contextLabel: "Manual Rule Contexts"
            )
            .frame(height: 36)

            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                WritingAwareTextView(
                    text: $notes,
                    surfaceID: "manual-rule-notes",
                    placeholder: "Why does this matter?",
                    contextLabel: "Manual Rule Notes",
                    minHeight: 120,
                    backgroundColor: .controlBackgroundColor,
                    borderColor: .clear,
                    cornerRadius: 16
                )
                    .frame(height: 120)
            }

            HStack {
                Stepper("Priority \(priority)", value: $priority, in: 1...5)
                Spacer()
                Toggle("Pinned", isOn: $pinned)
                    .toggleStyle(.switch)
                    .frame(width: 110)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save Rule") {
                    onSave(
                        ManualRuleEditorDraft(
                            ruleID: draft.ruleID,
                            type: type,
                            term: term,
                            replacementWords: replacementCSV.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
                            contexts: contextsCSV.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
                            notes: notes,
                            priority: priority,
                            pinned: pinned
                        )
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
        .onAppear {
            type = draft.type
            term = draft.term
            replacementCSV = draft.replacementWords.joined(separator: ", ")
            contextsCSV = draft.contexts.joined(separator: ", ")
            notes = draft.notes
            priority = draft.priority
            pinned = draft.pinned
        }
    }
}

private struct LearningWordFamilyEditorView: View {
    let draft: LearningWordFamilyDraft
    let onRefreshSuggestions: (String, [LearningWordSuggestion]) async -> LearningWordSuggestionRefreshResult
    let onSave: (LearningWordFamilyDraft) -> LearningTargetSaveResult

    @Environment(\.dismiss) private var dismiss
    @State private var targetTerm = ""
    @State private var suggestions: [LearningWordSuggestion] = []
    @State private var suggestedSuggestions: [LearningWordSuggestion] = []
    @State private var suggestionNotice: String?
    @State private var isRefreshingSuggestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(draft.isExistingFamily ? "Edit Learning Word" : "Review Learning Word")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            if let notice = draft.notice, !notice.isEmpty {
                Text(notice)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Target word")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                WritingAwareTextField(
                    text: $targetTerm,
                    surfaceID: "learning-word-target",
                    placeholder: "Word or short phrase",
                    contextLabel: "Learning Word Target"
                )
                .frame(height: 36)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("AI suggestions")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        refreshSuggestedSuggestions()
                    } label: {
                        if isRefreshingSuggestions {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        isRefreshingSuggestions ||
                        targetTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                if suggestedSuggestions.isEmpty {
                    Text(suggestionNotice ?? "Refresh to ask AI for candidate overused words.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestedSuggestions) { suggestion in
                                LearningWordSuggestionTagButton(
                                    suggestion: suggestion,
                                    onSelect: {
                                        addSuggestedSuggestion(suggestion)
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            HStack(spacing: 10) {
                WritingChip(text: "Global scope", tone: .success)
                WritingChip(text: draft.sourceApp, tone: .neutral)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Linked overused words")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        suggestions.append(
                            LearningWordSuggestion(
                                term: "",
                                useWhen: "",
                                caution: "",
                                matchedPersonalHistory: false
                            )
                        )
                    } label: {
                        Label("Add Linked Word", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                if suggestions.isEmpty {
                    Text("No linked words yet. Add the vague or overused words you want Audora to catch and redirect to this target.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach($suggestions) { $suggestion in
                                LearningWordSuggestionEditorRow(
                                    suggestion: $suggestion,
                                    onDelete: {
                                        suggestions.removeAll { $0.id == suggestion.id }
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 320)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button(draft.isExistingFamily ? "Save Changes" : "Save Learning Word") {
                    let result = onSave(
                        LearningWordFamilyDraft(
                            familyID: draft.familyID,
                            targetRuleID: draft.targetRuleID,
                            targetTerm: targetTerm,
                            suggestions: suggestions,
                            suggestedSuggestions: suggestedSuggestions,
                            sourceApp: draft.sourceApp,
                            contextLabel: draft.contextLabel,
                            origin: draft.origin,
                            anchorRect: draft.anchorRect,
                            notice: draft.notice
                        )
                    )
                    if result.status != .invalid {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(targetTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onAppear {
            targetTerm = draft.targetTerm
            suggestions = draft.suggestions
            suggestedSuggestions = filterSuggestedSuggestions(
                draft.suggestedSuggestions,
                excluding: draft.suggestions
            )
            suggestionNotice = draft.suggestedSuggestions.isEmpty ? nil : "Click an AI suggestion to add it as a linked overused word."
        }
    }

    private func refreshSuggestedSuggestions() {
        let excludedSuggestions = suggestions + suggestedSuggestions
        let currentTarget = targetTerm
        isRefreshingSuggestions = true

        Task {
            let result = await onRefreshSuggestions(currentTarget, excludedSuggestions)
            await MainActor.run {
                suggestedSuggestions = filterSuggestedSuggestions(
                    result.suggestions,
                    excluding: suggestions
                )
                suggestionNotice = result.notice
                isRefreshingSuggestions = false
            }
        }
    }

    private func addSuggestedSuggestion(_ suggestion: LearningWordSuggestion) {
        let normalizedSuggestion = normalizedSuggestionTerm(suggestion.term)
        guard !normalizedSuggestion.isEmpty,
              !suggestions.contains(where: { normalizedSuggestionTerm($0.term) == normalizedSuggestion }) else {
            return
        }

        suggestions.append(
            LearningWordSuggestion(
                term: suggestion.term.trimmingCharacters(in: .whitespacesAndNewlines),
                useWhen: suggestion.useWhen,
                caution: suggestion.caution,
                matchedPersonalHistory: suggestion.matchedPersonalHistory
            )
        )
        suggestedSuggestions.removeAll { normalizedSuggestionTerm($0.term) == normalizedSuggestion }
    }

    private func filterSuggestedSuggestions(
        _ candidates: [LearningWordSuggestion],
        excluding existingSuggestions: [LearningWordSuggestion]
    ) -> [LearningWordSuggestion] {
        let existingTerms = Set(existingSuggestions.map { normalizedSuggestionTerm($0.term) })
        var seenTerms = Set<String>()

        return candidates.filter { suggestion in
            let normalizedTerm = normalizedSuggestionTerm(suggestion.term)
            guard !normalizedTerm.isEmpty,
                  !existingTerms.contains(normalizedTerm),
                  seenTerms.insert(normalizedTerm).inserted else {
                return false
            }
            return true
        }
    }

    private func normalizedSuggestionTerm(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct LearningWordSuggestionTagButton: View {
    let suggestion: LearningWordSuggestion
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(suggestion.term)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                if suggestion.matchedPersonalHistory {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .foregroundStyle(suggestion.matchedPersonalHistory ? Color.accentColor : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        suggestion.matchedPersonalHistory
                            ? Color.accentColor.opacity(0.12)
                            : Color.primary.opacity(0.07)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct LearningWordSuggestionEditorRow: View {
    @Binding var suggestion: LearningWordSuggestion
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                WritingAwareTextField(
                    text: $suggestion.term,
                    surfaceID: "learning-word-linked-term-\(suggestion.id.uuidString)",
                    placeholder: "Overused word or phrase",
                    contextLabel: "Learning Word Linked Term"
                )
                .frame(height: 36)

                if suggestion.matchedPersonalHistory {
                    WritingChip(text: "Seen from you", tone: .target)
                }

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Use when")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField(
                    "When should Audora suggest the target?",
                    text: $suggestion.useWhen
                )
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Caution")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField(
                    "When should Audora avoid forcing this replacement?",
                    text: $suggestion.caution
                )
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { index in
            Array(self[index ..< Swift.min(index + size, count)])
        }
    }
}
