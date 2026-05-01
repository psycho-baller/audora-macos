import AppKit
import SwiftUI

struct WritingLensView: View {
    @ObservedObject private var manager = WritingAwarenessManager.shared
    @ObservedObject private var recorder = VoiceMemoRecorder.shared
    @State private var repairRawSentence = ""
    @State private var repairImprovedSentence = ""
    @State private var replacementWord = ""
    @State private var reusedSameDay = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                inputCard
                feedbackCard
                repairCard
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 720)
        .background(WritingCanvasBackground())
        .onChange(of: manager.lensRewrite) { _, newValue in
            guard !newValue.isEmpty else { return }
            if repairImprovedSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                repairImprovedSentence = newValue
            }
        }
        .onChange(of: manager.lensInputText) { _, newValue in
            if repairRawSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                repairRawSentence = newValue
            }
        }
    }

    private var headerCard: some View {
        WritingSurfaceCard(
            title: "Writing Lens",
            subtitle: "Selected-text coaching with local rule checks and subtle reinforcement."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            WritingChip(text: manager.lensSourceApp, tone: .neutral)
                            WritingChip(text: manager.lensContextLabel, tone: .target)
                            if manager.lensUsedClipboardFallback {
                                WritingChip(text: "Clipboard fallback", tone: .avoid)
                            }
                        }

                        Text(manager.focusPack.triggerQuestion)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
                    Button {
                        manager.captureSelectionIntoLens()
                    } label: {
                        Label("Capture Selection", systemImage: "viewfinder")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        manager.loadClipboardIntoLens()
                    } label: {
                        Label("Use Clipboard", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        manager.analyzeCurrentLensText(recordFeedback: true)
                    } label: {
                        Label("Analyze", systemImage: "waveform.path.ecg.text")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        manager.generateLensRewrite()
                    } label: {
                        Label("Generate Repair", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                    .disabled(manager.lensInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let error = manager.lastCaptureError {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var inputCard: some View {
        WritingSurfaceCard(
            title: "Input",
            subtitle: "Paste text or capture a selection from the frontmost app."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                WritingAwareTextView(
                    text: $manager.lensInputText,
                    surfaceID: "writing-lens-input",
                    placeholder: "Paste text or capture a selection.",
                    contextLabel: "Writing Lens Input",
                    font: .monospacedSystemFont(ofSize: 14, weight: .medium),
                    minHeight: 180,
                    backgroundColor: .textBackgroundColor,
                    borderColor: .clear,
                    cornerRadius: 18,
                    textInsets: NSSize(width: 10, height: 10)
                )
                    .frame(minHeight: 180)
                    .onChange(of: manager.lensInputText) { _, _ in
                        manager.analyzeCurrentLensText(recordFeedback: false)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Highlighted preview")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let result = manager.lensResult {
                            Text("\(Int(result.confidence * 100))% confidence")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HighlightedLensPreview(text: manager.lensInputText, result: manager.lensResult)
                }
            }
        }
    }

    private var feedbackCard: some View {
        WritingSurfaceCard(
            title: "Feedback",
            subtitle: "Flagged crutch words, replacement ideas, and rewarded vocabulary."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if let result = manager.lensResult {
                    if result.flaggedTerms.isEmpty && result.rewardedTerms.isEmpty {
                        Text("No live hits yet. Try selected text with one of the active focus words or banned defaults.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        if !result.suggestedReplacements.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Flagged")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(result.suggestedReplacements) { suggestion in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 8) {
                                            WritingChip(text: suggestion.term, tone: .avoid)
                                            flowChips(suggestion.replacements, tone: .neutral)
                                        }
                                        Text(suggestion.message)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        if !result.rewardedTerms.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Rewarded")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(result.rewardedTerms) { match in
                                    HStack(alignment: .top, spacing: 8) {
                                        WritingChip(text: match.term, tone: .success)
                                        Text(match.snippet)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        if !manager.lensRewrite.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Generated repair")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text(manager.lensRewrite)
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(Color.accentColor.opacity(0.12))
                                    )
                            }
                        }
                    }
                } else {
                    Text("Analyze some text to populate this panel.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var repairCard: some View {
        WritingSurfaceCard(
            title: "Repair Capture",
            subtitle: "Attach a voice memo, save the weak sentence, then save the better one."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button {
                        if recorder.isRecording {
                            _ = recorder.stopRecording()
                        } else {
                            recorder.startRecording()
                        }
                    } label: {
                        Label(recorder.isRecording ? "Stop Memo" : "Record Memo", systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    if let lastRecordedURL = recorder.lastRecordedURL {
                        Text(lastRecordedURL.lastPathComponent)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Use Current Text") {
                        repairRawSentence = manager.lensInputText
                    }
                    .buttonStyle(.bordered)

                    Button("Use Generated Repair") {
                        repairImprovedSentence = manager.lensRewrite.isEmpty ? (manager.lensResult?.rewrittenText ?? "") : manager.lensRewrite
                        if replacementWord.isEmpty {
                            replacementWord = manager.lensResult?.suggestedReplacements.first?.replacements.first ?? manager.focusPack.targetWords.first ?? ""
                        }
                    }
                    .buttonStyle(.bordered)
                }

                if let error = recorder.errorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Weak sentence")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    WritingAwareTextView(
                        text: $repairRawSentence,
                        surfaceID: "writing-repair-raw",
                        placeholder: "Weak sentence",
                        contextLabel: "Repair Raw Sentence",
                        minHeight: 90,
                        backgroundColor: .textBackgroundColor,
                        borderColor: .clear,
                        cornerRadius: 16
                    )
                        .frame(height: 90)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Improved sentence")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    WritingAwareTextView(
                        text: $repairImprovedSentence,
                        surfaceID: "writing-repair-improved",
                        placeholder: "Improved sentence",
                        contextLabel: "Repair Improved Sentence",
                        minHeight: 110,
                        backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.12),
                        borderColor: .clear,
                        cornerRadius: 16
                    )
                        .frame(height: 110)
                }

                HStack(spacing: 12) {
                    WritingAwareTextField(
                        text: $replacementWord,
                        surfaceID: "writing-repair-replacement",
                        placeholder: "Replacement word used",
                        contextLabel: "Repair Replacement Word"
                    )
                    .frame(height: 36)
                    Toggle("Reused later today", isOn: $reusedSameDay)
                        .toggleStyle(.switch)
                }

                HStack {
                    Spacer()
                    Button("Save Repair") {
                        manager.saveRepair(
                            rawSentence: repairRawSentence,
                            improvedSentence: repairImprovedSentence,
                            replacementWord: replacementWord,
                            ruleIDs: Array(Set(manager.lensResult?.flaggedTerms.map(\.ruleId) ?? [])),
                            sourceApp: manager.lensSourceApp,
                            reusedSameDay: reusedSameDay,
                            audioMemoPath: recorder.lastRecordedURL?.path
                        )
                        repairRawSentence = ""
                        repairImprovedSentence = ""
                        replacementWord = ""
                        reusedSameDay = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        repairRawSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        repairImprovedSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func flowChips(_ values: [String], tone: WritingChip.Tone) -> some View {
        HStack(spacing: 8) {
            ForEach(values, id: \.self) { value in
                WritingChip(text: value, tone: tone)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct HighlightedLensPreview: View {
    let text: String
    let result: WritingCheckResult?

    var body: some View {
        ScrollView {
            Text(attributedText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private var attributedText: AttributedString {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return AttributedString("Paste text or capture a selection to inspect it here.") }

        let mutable = NSMutableAttributedString(string: source)
        mutable.addAttributes([
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        ], range: NSRange(location: 0, length: mutable.length))

        if let result {
            for match in result.rewardedTerms {
                let range = NSRange(location: match.rangeLower, length: match.rangeUpper - match.rangeLower)
                guard NSMaxRange(range) <= mutable.length else { continue }
                mutable.addAttributes([
                    .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.2),
                    .foregroundColor: NSColor.systemGreen
                ], range: range)
            }

            for match in result.flaggedTerms {
                let range = NSRange(location: match.rangeLower, length: match.rangeUpper - match.rangeLower)
                guard NSMaxRange(range) <= mutable.length else { continue }
                mutable.addAttributes([
                    .backgroundColor: NSColor.systemOrange.withAlphaComponent(0.22),
                    .foregroundColor: NSColor.systemOrange
                ], range: range)
            }
        }

        return AttributedString(mutable)
    }
}
