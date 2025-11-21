import SwiftUI

struct MeetingListView: View {
    @StateObject private var viewModel = MeetingListViewModel()
    @ObservedObject var settingsViewModel: SettingsViewModel
    @StateObject private var recordingSessionManager = RecordingSessionManager.shared
    @State private var selectedMeeting: Meeting?
    @State private var navigationPath = NavigationPath()
    @Binding var triggerNewRecording: Bool
    @Binding var triggerOpenSettings: Bool
    
    // Default initializer for use without bindings
    init(settingsViewModel: SettingsViewModel, 
         triggerNewRecording: Binding<Bool> = .constant(false),
         triggerOpenSettings: Binding<Bool> = .constant(false)) {
        self.settingsViewModel = settingsViewModel
        self._triggerNewRecording = triggerNewRecording
        self._triggerOpenSettings = triggerOpenSettings
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with meetings list
            sidebarContent
        } detail: {
            // Detail view with meeting content
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading meetings...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
            }
        }
        .onChange(of: triggerNewRecording) { _, _ in
            // Create new recording when triggered from menu bar
            let newMeeting = viewModel.createNewMeeting()
            selectedMeeting = newMeeting
        }
        .onChange(of: triggerOpenSettings) { _, _ in
            // Navigate to settings when triggered from menu bar
            navigationPath.append("settings")
        }
    }
    
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search meetings...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            
            Divider()
            
            Spacer().frame(height: 12) // Add space before list content

            List(selection: $selectedMeeting) {
                // Only render meeting sections when there are meetings or loading state
                ForEach(groupedMeetings, id: \.day) { dayGroup in
                    Section {
                        ForEach(dayGroup.meetings, id: \.id) { meeting in
                            MeetingRowView(meeting: meeting)
                                .tag(meeting)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let meetingToDelete = dayGroup.meetings[index]
                                viewModel.deleteMeeting(meetingToDelete)
                                // Clear selection if the deleted meeting was selected
                                if selectedMeeting?.id == meetingToDelete.id {
                                    selectedMeeting = nil
                                }
                            }
                        }
                    } header: {
                        Text(dayGroup.day)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                }
            }
            .overlay {
                if viewModel.filteredMeetings.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        viewModel.searchText.isEmpty ? "No Meetings Yet" : "No Results",
                        systemImage: viewModel.searchText.isEmpty ? "mic.slash" : "magnifyingglass",
                        description: Text(viewModel.searchText.isEmpty ? "Start a new meeting to begin transcribing" : "Try a different search term")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Meetings")
    }
    
    private var detailContent: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let selectedMeeting = selectedMeeting {
                    MeetingDetailContentView(meeting: selectedMeeting, onDelete: {
                        // When a meeting is deleted from the detail view, clear the selection
                        self.selectedMeeting = nil
                    })
                    .id(selectedMeeting.id) // Force recreation when selection changes
                } else {
                    ContentUnavailableView(
                        "Select a Meeting",
                        systemImage: "sidebar.leading",
                        description: Text("Choose a meeting from the sidebar to view its details")
                    )
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Spacer()
                    
                    // Auto-recording status indicator
                    if AudioManager.shared.isAutoRecordingEnabled {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform.circle.fill")
                                .foregroundColor(.green)
                            Text("Auto")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .help("Auto-recording enabled - will start/stop with other apps' audio")
                    }

                    Button {
                        navigationPath.append("settings")
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")

                    Button {
                        let newMeeting = viewModel.createNewMeeting()
                        selectedMeeting = newMeeting
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(recordingSessionManager.isRecording)
                    .help(recordingSessionManager.isRecording ? "Cannot create new meeting while recording is active" : "New Meeting")
                }
            }
            .navigationDestination(for: String.self) { path in
                if path == "settings" {
                    SettingsView(viewModel: settingsViewModel, navigationPath: $navigationPath)
                } else if path == "templates" {
                    TemplateListView()
                }
            }
        }
    }
    
    private var groupedMeetings: [DayGroup] {
        let calendar = Calendar.current
        let now = Date()
        
        let grouped = Dictionary(grouping: viewModel.filteredMeetings) { meeting in
            calendar.startOfDay(for: meeting.date)
        }
        
        return grouped.map { (date, meetings) in
            let dayString: String
            
            if calendar.isDateInToday(date) {
                dayString = "Today"
            } else if calendar.isDateInYesterday(date) {
                dayString = "Yesterday"
            } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
                dayString = date.formatted(.dateTime.weekday(.wide))
            } else {
                dayString = date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            }
            
            return DayGroup(day: dayString, date: date, meetings: meetings.sorted { $0.date > $1.date })
        }.sorted { $0.date > $1.date }
    }
}

struct DayGroup {
    let day: String
    let date: Date
    let meetings: [Meeting]
}

struct MeetingRowView: View {
    let meeting: Meeting
    @StateObject private var recordingSessionManager = RecordingSessionManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title or default
            HStack(spacing: 4) {
                if recordingSessionManager.isRecordingMeeting(meeting.id) {
                    Image(systemName: "record.circle")
                        .foregroundColor(.red)
                        .font(.headline)
                }
                Text(meeting.title.isEmpty ? "Untitled meeting" : meeting.title)
                    .font(.headline)
                    .lineLimit(1)
            }
            // Date
            HStack {
                Text(meeting.date, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Meeting Detail Content View
// This is a refactored version of MeetingDetailView that works within the sidebar layout

struct CollapsedTranscriptChunkView: View {
    let chunk: CollapsedTranscriptChunk
    let analytics: SpeechAnalytics?
    let activeSubtab: AnalyticsSubtab?
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Source indicator
            HStack(spacing: 4) {
                Image(systemName: chunk.source.icon)
                    .font(.caption)
                    .foregroundColor(chunk.source == .mic ? .blue : .orange)
                
                Text(chunk.source.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(chunk.source == .mic ? .blue : .orange)
            }
            .frame(width: 50, alignment: .leading)
            
            // Highlighted transcript text
            if let analytics = analytics, activeSubtab == .wordChoice {
                HighlightedText(text: chunk.combinedText, analytics: analytics)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(chunk.combinedText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Highlighted Text View

struct HighlightedText: View {
    let text: String
    let analytics: SpeechAnalytics
    
    var body: some View {
        buildHighlightedText()
    }
    
    private func buildHighlightedText() -> some View {
        // Split text into words
        let words = text.split(separator: " ").map { String($0) }
        
        // Create sets for quick lookup (use the actual words from analytics)
        let fillerWordsSet = Set(analytics.fillerWords.instances.map { $0.word.lowercased() })
        let repeatedWordsSet = Set(analytics.repetitions.repeatedWords.map { $0.word.lowercased() })
        let weakStartersSet = Set(analytics.sentenceStarters.weak.map { $0.word.lowercased() })
        
        return WrappingHStack(alignment: .leading, spacing: 0) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                let cleanWord = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                let highlightType = determineHighlightType(
                    word: cleanWord,
                    index: index,
                    words: words,
                    fillerWordsSet: fillerWordsSet,
                    repeatedWordsSet: repeatedWordsSet,
                    weakStartersSet: weakStartersSet
                )
                
                HStack(spacing: 0) {
                    if index > 0 {
                        Text(" ")
                    }
                    
                    if let type = highlightType {
                        Text(word)
                            .background(type.color.opacity(0.3))
                    } else {
                        Text(word)
                    }
                }
            }
        }
    }
    
    private func determineHighlightType(
        word: String,
        index: Int,
        words: [String],
        fillerWordsSet: Set<String>,
        repeatedWordsSet: Set<String>,
        weakStartersSet: Set<String>
    ) -> HighlightType? {
        // Check for filler words (highest priority)
        if fillerWordsSet.contains(word) {
            return .fillerWord
        }
        // Check for repeated words
        else if repeatedWordsSet.contains(word) {
            return .repeatedWord
        }
        // Check for weak sentence starters
        else if index == 0 || (index > 0 && (words[index-1].hasSuffix(".") || words[index-1].hasSuffix("!") || words[index-1].hasSuffix("?"))) {
            if weakStartersSet.contains(word) {
                return .weakStarter
            }
        }
        
        return nil
    }
    
    enum HighlightType {
        case fillerWord
        case repeatedWord
        case weakStarter
        
        var color: Color {
            switch self {
            case .fillerWord:
                return .blue
            case .repeatedWord:
                return .orange
            case .weakStarter:
                return .yellow
            }
        }
    }
}

// MARK: - Wrapping HStack

struct WrappingHStack: Layout {
    var alignment: Alignment = .leading
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeViews(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrangeViews(proposal: proposal, subviews: subviews)
        
        for (index, position) in arrangement.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(arrangement.sizes[index])
            )
        }
    }
    
    private func arrangeViews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint], sizes: [CGSize]) {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        
        let maxWidth = proposal.width ?? .infinity
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            // Check if we need to wrap to next line
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            sizes.append(size)
            
            currentX += size.width
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX)
        }
        
        let totalHeight = currentY + lineHeight
        return (CGSize(width: totalWidth, height: totalHeight), positions, sizes)
    }
}

// MARK: - Legend Item

struct LegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(color.opacity(0.3))
                .frame(width: 12, height: 12)
                .cornerRadius(2)
            
            Text(label)
                .foregroundColor(.secondary)
        }
    }
}

struct MeetingDetailContentView: View {
    @StateObject private var viewModel: MeetingViewModel
    @StateObject private var recordingSessionManager = RecordingSessionManager.shared
    @State private var showDeleteAlert = false
    let onDelete: () -> Void
    
    init(meeting: Meeting, onDelete: @escaping () -> Void) {
        self._viewModel = StateObject(wrappedValue: MeetingViewModel(meeting: meeting))
        self.onDelete = onDelete
    }
    
    // Computed property to determine if recording button should be disabled
    private var cannotStartRecording: Bool {
        // Disable if another meeting is recording (not this one)
        return recordingSessionManager.isRecording && !recordingSessionManager.isRecordingMeeting(viewModel.meeting.id)
    }
    
    // Helper to get audio file URL - placeholder for now until backend is ready
    private var audioFileURL: URL? {
        // For testing: Load audio file from app bundle
        if let url = Bundle.main.url(forResource: "audora_audio_test1", withExtension: "m4a") {
            return url
        }
        // TODO: Replace with actual audio file path from meeting when backend is ready
        // For now, return nil to show placeholder
        return nil
    }
    
    var body: some View {
        HSplitView {
            // Middle Column: Audio Player + Transcript
            middleColumn
                .frame(minWidth: 400, idealWidth: 500)
            
            // Right Column: Analytics Panel
            rightColumn
                .frame(minWidth: 350, idealWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Delete Meeting", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                viewModel.deleteMeeting()
                onDelete()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this meeting? This action cannot be undone.")
        }
        .onDisappear {
            // Auto-delete empty meetings when leaving, otherwise save
            viewModel.deleteIfEmpty()
        }
    }
    
    // MARK: - Middle Column
    
    private var middleColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with title and controls
            headerSection
            
            // Audio Player (fixed at top)
            AudioPlayerView(audioURL: audioFileURL)
            
            // Transcript Section
            transcriptSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title and Menu
            HStack {
                TextField("Meeting Title", text: $viewModel.meeting.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .textFieldStyle(.plain)
                
                Spacer()
                
                // Ellipsis menu
                Menu {
                    Button("Delete Meeting", role: .destructive) {
                        showDeleteAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundColor(.secondary)
                }
                .labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .menuStyle(BorderlessButtonMenuStyle())
                .frame(width: 20, height: 20)
            }
            
            // Controls: Generate and Recording Buttons
            HStack(spacing: 8) {
                // Generate Button (Dropdown)
                Menu {
                    ForEach(viewModel.templates) { template in
                        Button(template.title) {
                            viewModel.selectedTemplateId = template.id
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.isGeneratingNotes {
                            ProgressView()
                                .scaleEffect(0.4)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.caption)
                        }
                        Text("Generate")
                    }
                    .frame(minWidth: 110, minHeight: 36)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        Group {
                            if viewModel.shouldAnimateGenerateButton {
                                ShimmerOverlay(color: .green)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.meeting.transcript.isEmpty || viewModel.isGeneratingNotes || viewModel.isRecording || viewModel.isStartingRecording)
                .help("Generate enhanced notes using a template")
                
                // Recording Button
                Button(action: {
                    viewModel.toggleRecording()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "record.circle")
                            .foregroundColor(viewModel.isRecording ? .red : .accentColor)
                        Text(viewModel.recordingButtonText)
                    }
                    .frame(minWidth: 110, minHeight: 36)
                    .background(viewModel.isRecording ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        Group {
                            if viewModel.shouldAnimateTranscribeButton {
                                ShimmerOverlay(color: .accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
                .disabled(cannotStartRecording || viewModel.isValidatingKey || viewModel.isStartingRecording)
                .help(cannotStartRecording ? "Another meeting is currently being recorded" : "Start or stop recording for this meeting")
                
                Spacer()
            }
        }
    }
    
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Transcript Header
            HStack {
                Text("Transcript")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            // Transcript Content
            VStack(alignment: .leading, spacing: 8) {
                // Color legend (only show when Word Choice subtab is active)
                if activeAnalyticsSubtab == .wordChoice, viewModel.meeting.analytics != nil {
                    HStack(spacing: 12) {
                        LegendItem(color: .blue, label: "Filler Words")
                        LegendItem(color: .orange, label: "Repeated Words")
                        LegendItem(color: .yellow, label: "Weak Starters")
                    }
                    .font(.caption)
                    .padding(.horizontal, 4)
                }
                
                ScrollView {
                    if viewModel.meeting.collapsedTranscriptChunks.isEmpty {
                        Text("Transcript will appear here...")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .foregroundColor(.secondary)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.meeting.collapsedTranscriptChunks) { chunk in
                                CollapsedTranscriptChunkView(
                                    chunk: chunk,
                                    analytics: viewModel.meeting.analytics,
                                    activeSubtab: activeAnalyticsSubtab
                                )
                            }
                        }
                        .padding()
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Right Column
    
    @State private var activeAnalyticsSubtab: AnalyticsSubtab? = nil
    
    private var rightColumn: some View {
        AnalyticsPanelView(
            analytics: viewModel.meeting.analytics,
            onSubtabChange: { subtab in
                activeAnalyticsSubtab = subtab
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Initialize with Word Choice subtab when analytics are available
            if viewModel.meeting.analytics != nil {
                activeAnalyticsSubtab = .wordChoice
            }
        }
    }
}

// MARK: - Shimmer Overlay
struct ShimmerOverlay: View {
    @State private var animate: Bool = false
    let color: Color
    
    init(color: Color = .green) {
        self.color = color
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.clear, color.opacity(0.1), Color.clear]),
                        startPoint: UnitPoint(x: animate ? 2.5 : -1, y: 0.5),
                        endPoint: UnitPoint(x: animate ? 3.5 : 0, y: 0.5)
                    )
                )
                .frame(width: width, height: height)
                .onAppear {
                    animate = true
                }
                .animation(
                    Animation.linear(duration: 1.5).repeatForever(autoreverses: false),
                    value: animate
                )
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    MeetingListView(settingsViewModel: SettingsViewModel())
} 
