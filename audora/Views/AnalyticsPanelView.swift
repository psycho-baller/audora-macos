import SwiftUI

enum AnalyticsMainTab: String, CaseIterable {
    case analytics = "Analytics"
    case suggestions = "Suggestions"
}

enum AnalyticsSubtab: String, CaseIterable {
    case wordChoice = "Word Choice"
    case delivery = "Delivery"
}

struct AnalyticsPanelView: View {
    let analytics: SpeechAnalytics?
    @State private var selectedMainTab: AnalyticsMainTab = .analytics
    @State private var selectedSubtab: AnalyticsSubtab = .wordChoice
    var onSubtabChange: ((AnalyticsSubtab) -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            if let analytics = analytics {
                // Main tabs
                mainTabBar
                
                Divider()
                
                // Content based on selected tab
                Group {
                    switch selectedMainTab {
                    case .analytics:
                        analyticsContent(analytics: analytics)
                    case .suggestions:
                        suggestionsContent(analytics: analytics)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Analytics Available",
                    systemImage: "chart.bar",
                    description: Text("Analytics will appear here after transcription is complete")
                )
            }
        }
        .onAppear {
            // Initialize subtab callback
            if selectedMainTab == .analytics {
                onSubtabChange?(selectedSubtab)
            }
        }
    }
    
    // MARK: - Main Tab Bar
    
    private var mainTabBar: some View {
        HStack(spacing: 0) {
            ForEach(AnalyticsMainTab.allCases, id: \.self) { tab in
                Button(action: {
                    selectedMainTab = tab
                }) {
                    VStack(spacing: 4) {
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedMainTab == tab ? .semibold : .regular)
                            .foregroundColor(selectedMainTab == tab ? .primary : .secondary)
                        
                        Rectangle()
                            .fill(selectedMainTab == tab ? Color.blue : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    // MARK: - Analytics Content
    
    private func analyticsContent(analytics: SpeechAnalytics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Subtabs (only show for Analytics tab)
                subtabBar
                
                Divider()
                
                // Content based on selected subtab
                Group {
                    switch selectedSubtab {
                    case .wordChoice:
                        wordChoiceContent(analytics: analytics)
                    case .delivery:
                        deliveryContent(analytics: analytics)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Subtab Bar
    
    private var subtabBar: some View {
        HStack(spacing: 16) {
            ForEach(AnalyticsSubtab.allCases, id: \.self) { subtab in
                Button(action: {
                    selectedSubtab = subtab
                    onSubtabChange?(subtab)
                }) {
                    Text(subtab.rawValue)
                        .font(.caption)
                        .fontWeight(selectedSubtab == subtab ? .semibold : .regular)
                        .foregroundColor(selectedSubtab == subtab ? .blue : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedSubtab == subtab ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Word Choice Content
    
    private func wordChoiceContent(analytics: SpeechAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Score Cards
            HStack(spacing: 12) {
                ScoreCard(
                    title: "Clarity",
                    score: analytics.scores.clarity,
                    subtitle: "Based on filler words"
                )
                
                ScoreCard(
                    title: "Conciseness",
                    score: analytics.scores.conciseness,
                    subtitle: "Based on repetitions"
                )
                
                ScoreCard(
                    title: "Confidence",
                    score: analytics.scores.confidence,
                    subtitle: "Based on sentence starters"
                )
            }
            
            // Filler Words
            MetricCard(
                icon: "bubble.left.fill",
                title: "Filler Words",
                color: .blue
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    MetricRow(
                        label: "Total Count",
                        value: "\(analytics.fillerWords.count)"
                    )
                    MetricRow(
                        label: "Per Minute",
                        value: String(format: "%.1f", analytics.fillerWords.ratePerMinute)
                    )
                    
                    if !analytics.fillerWords.instances.isEmpty {
                        Divider()
                            .padding(.vertical, 4)
                        
                        Text("Most Common:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        FlowLayout(spacing: 6) {
                            ForEach(Array(Set(analytics.fillerWords.instances.prefix(5).map { $0.word })), id: \.self) { word in
                                Text(word)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }
            
            // Repeated Words
            if !analytics.repetitions.repeatedWords.isEmpty {
                MetricCard(
                    icon: "repeat",
                    title: "Repeated Words",
                    color: .orange
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(analytics.repetitions.repeatedWords.prefix(5)) { word in
                            MetricRow(
                                label: word.word.capitalized,
                                value: "\(word.count)x"
                            )
                        }
                    }
                }
            }
            
            // Weak Sentence Starters
            if !analytics.sentenceStarters.weak.isEmpty {
                MetricCard(
                    icon: "exclamationmark.triangle.fill",
                    title: "Weak Sentence Starters",
                    color: .yellow
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(analytics.sentenceStarters.weak.prefix(5)) { starter in
                            MetricRow(
                                label: "\"\(starter.word)\"",
                                value: "\(starter.count)x"
                            )
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        Text("Try to vary your sentence starters for better flow")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Delivery Content
    
    private func deliveryContent(analytics: SpeechAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            MetricCard(
                icon: "timer",
                title: "Pacing",
                color: .green
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    MetricRow(
                        label: "Words Per Minute",
                        value: "\(analytics.pacing.wordsPerMinute)"
                    )
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    Text(pacingFeedback(wpm: analytics.pacing.wordsPerMinute))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Suggestions Content
    
    private func suggestionsContent(analytics: SpeechAnalytics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !analytics.weakWords.isEmpty {
                    ForEach(analytics.weakWords.prefix(10)) { weakWord in
                        WeakWordCard(weakWord: weakWord)
                    }
                } else {
                    ContentUnavailableView(
                        "No Suggestions",
                        systemImage: "checkmark.circle",
                        description: Text("Great job! No improvement suggestions at this time.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Helper Methods
    
    private func pacingFeedback(wpm: Int) -> String {
        if wpm < 100 {
            return "Speaking slowly - good for clarity"
        } else if wpm > 160 {
            return "Speaking quickly - consider slowing down"
        } else {
            return "Good speaking pace"
        }
    }
}

// MARK: - Preview

#Preview {
    AnalyticsPanelView(
        analytics: SpeechAnalytics(
            fillerWords: FillerWords(
                count: 15,
                ratePerMinute: 2.5,
                instances: [
                    FillerWordInstance(word: "um", position: 5),
                    FillerWordInstance(word: "like", position: 12),
                    FillerWordInstance(word: "you know", position: 20)
                ]
            ),
            pacing: PacingMetrics(
                wordsPerMinute: 145,
                averagePauseDuration: nil,
                longestPause: nil
            ),
            repetitions: Repetitions(
                repeatedWords: [
                    RepeatedWord(word: "really", count: 5),
                    RepeatedWord(word: "think", count: 4)
                ],
                repeatedPhrases: [
                    RepeatedPhrase(phrase: "i think", count: 3)
                ]
            ),
            sentenceStarters: SentenceStarters(
                total: 20,
                weak: [
                    WeakStarter(word: "so", count: 3),
                    WeakStarter(word: "well", count: 2)
                ]
            ),
            weakWords: [
                WeakWordInstance(
                    word: "just",
                    sentence: "I just wanted to say that this is really important.",
                    suggestion: "I wanted to say that this is important."
                )
            ],
            scores: AnalyticsScores(
                clarity: 75,
                conciseness: 68,
                confidence: 82
            )
        )
    )
    .frame(width: 400, height: 800)
}

