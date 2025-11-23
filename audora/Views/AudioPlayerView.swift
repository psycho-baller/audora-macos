import SwiftUI
import AVFoundation
import AppKit
import Combine

struct AudioPlayerView: View {
    @StateObject private var playerManager = AudioPlayerManager()
    let audioURL: URL?
    @State private var hoveredButton: String? = nil
    @State private var isHoveringProgressBar = false
    @State private var dragStartProgress: Double = 0
    @State private var fileModificationDate: Date?
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        Group {
            if let audioURL = audioURL {
                audioPlayerContent(audioURL: audioURL)
            } else {
                placeholderContent
            }
        }
        .onChange(of: audioURL) { _ in
            if let url = audioURL {
                updateFileModificationDate(for: url)
                playerManager.loadAudio(url: url)
            } else {
                fileModificationDate = nil
                playerManager.cleanup()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingSaved)) { notification in
            // Reload audio if the file was updated
            if let url = audioURL, FileManager.default.fileExists(atPath: url.path) {
                checkAndReloadIfFileUpdated(url: url)
            }
        }
    }
    
    private func audioPlayerContent(audioURL: URL) -> some View {
        VStack(spacing: 12) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(Color.gray.opacity(isHoveringProgressBar ? 0.3 : 0.2))
                        .frame(height: 4)
                        .cornerRadius(2)
                    
                    // Progress track
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * playerManager.progress, height: 4)
                        .cornerRadius(2)
                    
                    // Invisible overlay for tap-to-seek (behind thumb so thumb gets priority)
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .frame(height: 12)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    // Only seek if this was a tap (minimal movement)
                                    // This allows the thumb drag to work while still enabling tap-to-seek
                                    if abs(value.translation.width) < 5 && abs(value.translation.height) < 5 {
                                        let newProgress = max(0, min(1, value.location.x / geometry.size.width))
                                        playerManager.seek(to: newProgress)
                                    }
                                }
                        )
                    
                    // Draggable thumb (on top, gets priority)
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 12, height: 12)
                        .offset(x: geometry.size.width * playerManager.progress - 6)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    // Capture start progress at the beginning of the drag
                                    if abs(value.translation.width) < 0.1 {
                                        dragStartProgress = playerManager.progress
                                    }
                                    
                                    // Calculate new progress based on start position + translation
                                    let startX = geometry.size.width * dragStartProgress
                                    let newX = startX + value.translation.width
                                    let newProgress = max(0, min(1, newX / geometry.size.width))
                                    playerManager.seek(to: newProgress)
                                }
                        )
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHoveringProgressBar = hovering
                    }
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .frame(height: 12)
            
            // Controls and info
            HStack(spacing: 16) {
                // Skip backward button
                Button(action: {
                    playerManager.skipBackward()
                }) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(Color.gray.opacity(hoveredButton == "skipBackward" ? 0.15 : 0.05))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!playerManager.isReady)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hoveredButton = hovering ? "skipBackward" : nil
                    }
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                
                // Play/Pause button
                Button(action: {
                    // Check if file was updated before toggling playback
                    checkAndReloadIfFileUpdated(url: audioURL)
                    playerManager.togglePlayback()
                }) {
                    Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                        .frame(width: 40, height: 40)
                        .background(Color.blue.opacity(hoveredButton == "playPause" ? 0.1 : 0.05))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!playerManager.isReady)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hoveredButton = hovering ? "playPause" : nil
                    }
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                
                // Skip forward button
                Button(action: {
                    playerManager.skipForward()
                }) {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(Color.gray.opacity(hoveredButton == "skipForward" ? 0.15 : 0.05))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!playerManager.isReady)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hoveredButton = hovering ? "skipForward" : nil
                    }
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                
                Spacer()
                
                // Time display
                Text(playerManager.currentTimeString)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                
                Text("/")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(playerManager.durationString)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                
                // Speed control
                Menu {
                    ForEach([1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button(action: {
                            playerManager.setPlaybackRate(speed)
                        }) {
                            HStack {
                                Text("\(speed, specifier: "%.2f")x")
                                if playerManager.playbackRate == speed {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text("\(playerManager.playbackRate, specifier: "%.2f")x")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(hoveredButton == "speedControl" ? 0.2 : 0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(!playerManager.isReady)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hoveredButton = hovering ? "speedControl" : nil
                    }
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                
                // Folder button
                Button(action: {
                    openAudioFolder(url: audioURL)
                }) {
                    Image(systemName: "folder")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.gray.opacity(hoveredButton == "folder" ? 0.15 : 0.05))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!playerManager.isReady)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hoveredButton = hovering ? "folder" : nil
                    }
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .onAppear {
            updateFileModificationDate(for: audioURL)
            playerManager.loadAudio(url: audioURL)
        }
        .onDisappear {
            playerManager.cleanup()
        }
    }
    
    private var placeholderContent: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.secondary)
                Text("No audio file available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func updateFileModificationDate(for url: URL) {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modificationDate = attributes[.modificationDate] as? Date {
            fileModificationDate = modificationDate
        }
    }
    
    private func checkAndReloadIfFileUpdated(url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let currentModificationDate = attributes[.modificationDate] as? Date else {
            return
        }
        
        // If file was modified since we last checked, reload it
        if let lastKnownDate = fileModificationDate, currentModificationDate > lastKnownDate {
            print("🔄 Audio file updated (was \(lastKnownDate), now \(currentModificationDate)), reloading...")
            fileModificationDate = currentModificationDate
            // Preserve playback state
            let wasPlaying = playerManager.isPlaying
            playerManager.loadAudio(url: url)
            // Resume playback if it was playing
            if wasPlaying {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    playerManager.togglePlayback()
                }
            }
        } else if fileModificationDate == nil {
            // First time checking, just update the date
            fileModificationDate = currentModificationDate
        }
    }
    
    private func openAudioFolder(url: URL) {
        let folderURL = url.deletingLastPathComponent()
        NSWorkspace.shared.open(folderURL)
    }
}

// MARK: - Audio Player Manager

@MainActor
class AudioPlayerManager: ObservableObject {
    @Published var isPlaying = false
    @Published var progress: Double = 0.0
    @Published var currentTime: TimeInterval = 0.0
    @Published var duration: TimeInterval = 0.0
    @Published var playbackRate: Double = 1.0
    @Published var isReady = false
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    
    var currentTimeString: String {
        formatTime(currentTime)
    }
    
    var durationString: String {
        formatTime(duration)
    }
    
    func loadAudio(url: URL) {
        cleanup()
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.enableRate = true
            audioPlayer?.rate = Float(playbackRate)
            
            duration = audioPlayer?.duration ?? 0.0
            isReady = duration > 0
            
            if isReady {
                startTimer()
            }
        } catch {
            print("❌ Failed to load audio: \(error)")
            isReady = false
        }
    }
    
    func togglePlayback() {
        guard let player = audioPlayer else { return }
        
        if isPlaying {
            player.pause()
            stopTimer()
        } else {
            player.play()
            startTimer()
        }
        
        isPlaying = player.isPlaying
    }
    
    func skipBackward() {
        guard let player = audioPlayer else { return }
        let newTime = max(0, player.currentTime - 10)
        player.currentTime = newTime
        updateProgress()
    }
    
    func skipForward() {
        guard let player = audioPlayer else { return }
        let newTime = min(duration, player.currentTime + 10)
        player.currentTime = newTime
        updateProgress()
    }
    
    func seek(to progress: Double) {
        guard let player = audioPlayer else { return }
        let newTime = progress * duration
        player.currentTime = newTime
        updateProgress()
    }
    
    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        audioPlayer?.rate = Float(rate)
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateProgress() {
        guard let player = audioPlayer, duration > 0 else { return }
        currentTime = player.currentTime
        progress = currentTime / duration
        isPlaying = player.isPlaying
        
        // Auto-stop when finished
        if progress >= 1.0 && isPlaying {
            player.pause()
            player.currentTime = 0
            isPlaying = false
            progress = 0
            currentTime = 0
        }
    }
    
    func cleanup() {
        stopTimer()
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        progress = 0
        currentTime = 0
        duration = 0
        isReady = false
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview {
    AudioPlayerView(audioURL: nil)
        .frame(width: 600)
        .padding()
}

#Preview("With Audio") {
    // For preview, you can use a sample audio file path
    AudioPlayerView(audioURL: nil)
        .frame(width: 600)
        .padding()
}

