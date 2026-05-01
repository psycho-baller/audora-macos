import SwiftUI

struct WritingCoachView: View {
    @ObservedObject private var manager = WritingAwarenessManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(manager.liveCapture?.sourceApp ?? "Live Coach")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(manager.liveCapture?.contextLabel ?? "Focused text")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                WritingChip(
                    text: manager.liveCapability.shortLabel,
                    tone: manager.liveCapability.canReplaceSelection ? .success : .neutral
                )
                Button {
                    if let capture = manager.liveCapture {
                        manager.applyCapture(capture, recordFeedback: false)
                    }
                    WritingLensWindowManager.shared.show(captureSelection: false)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
            }

            if let liveResult = manager.liveResult {
                if let flagged = liveResult.suggestedReplacements.first {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Avoid")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        HStack(spacing: 8) {
                            WritingChip(text: flagged.term, tone: .avoid)
                            ForEach(flagged.replacements.prefix(2), id: \.self) { replacement in
                                WritingChip(text: replacement, tone: .neutral)
                            }
                        }
                    }
                }

                if let rewarded = liveResult.rewardedTerms.first {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reward")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        HStack(spacing: 8) {
                            WritingChip(text: rewarded.term, tone: .success)
                            Text("Strong specificity here")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let snippet = liveResult.flaggedTerms.first?.snippet ?? liveResult.rewardedTerms.first?.snippet {
                    Text(snippet)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }

            Text(manager.liveCapability.explanation)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let liveActionMessage = manager.liveActionMessage {
                Text(liveActionMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(manager.liveCapability.canReplaceSelection ? .green : .secondary)
            }

            HStack(spacing: 10) {
                if manager.liveCapability.canReplaceSelection,
                   manager.liveResult?.suggestedReplacements.first?.replacements.first != nil {
                    Button("Quick Replace") {
                        manager.replaceTopLiveSuggestion()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if manager.liveCapability.canReplaceSelection {
                    Button("Open Lens") {
                        if let capture = manager.liveCapture {
                            manager.applyCapture(capture, recordFeedback: false)
                        }
                        WritingLensWindowManager.shared.show(captureSelection: false)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Open Lens") {
                        if let capture = manager.liveCapture {
                            manager.applyCapture(capture, recordFeedback: false)
                        }
                        WritingLensWindowManager.shared.show(captureSelection: false)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Hide") {
                    WritingCoachWindowManager.shared.hide()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
    }
}
