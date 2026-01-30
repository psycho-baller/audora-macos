// LocalAudioManager.swift
// Fixed streaming implementation for WhisperKit

import AVFoundation
import Foundation
import SwiftUI
import OSLog
import Combine
import AppKit
import RunAnywhere
import WhisperKitTranscription

@MainActor
class LocalAudioManager: NSObject, ObservableObject {
    static let shared = LocalAudioManager()

    @Published var transcriptChunks: [TranscriptChunk] = []
    @Published var isRecording = false
    @Published var errorMessage: String?
    @Published var micAudioLevel: Float = 0.0
    @Published var systemAudioLevel: Float = 0.0

    private var audioEngine = AVAudioEngine()
    private let whisperKitService = WhisperKitService()
    
    // Audio streaming - with buffer accumulators
    private var micAudioStream: AsyncStream<VoiceAudioChunk>.Continuation?
    private var systemAudioStream: AsyncStream<VoiceAudioChunk>.Continuation?
    private var micTranscriptionTask: Task<Void, Never>?
    private var systemTranscriptionTask: Task<Void, Never>?
    
    // ✅ NEW: Audio accumulators for batching
    private var micAccumulator: [Float] = []
    private var systemAccumulator: [Float] = []
    private let chunkSize = 48000 // 1 second at 16kHz
    private var sequenceNumber = 0

    private var sessionID = UUID()

    // ProcessTap properties
    private var processTap: ProcessTap?
    private let audioProcessController = AudioProcessController()
    private let permission = AudioRecordingPermission()
    private let tapQueue = DispatchQueue(label: "io.audora.localaudio", qos: .userInitiated)
    private var isTapActive = false
    private var isRestartingSystemTap = false

    private var micRetryCount = 0
    private let maxMicRetries = 3

    private var cancellables = Set<AnyCancellable>()

    // Auto-Recording & Mic Following properties
    @Published var isAutoRecordingEnabled = false
    private var audioMonitor: SystemAudioMonitor?
    private var autoStartDelay: Timer?
    private var autoStopDelay: Timer?
    private let startDelayTime: TimeInterval = 0.5
    private let stopDelayTime: TimeInterval = 3.0

    @Published var isMicFollowingEnabled = false
    private var micMonitor: MicUsageMonitor?
    private var micFollowStartDelay: Timer?
    private var activityTracker: ActivityTracker?
    private var silenceProbeTimer: Timer?
    private var isRecordingDueToMicFollowing = false
    private var currentMicFollowingSession: TranscriptionSession?
    private let micFollowStartDelayTime: TimeInterval = 0.5
    private let silenceWindow: TimeInterval = 3.0
    private let probeInterval: TimeInterval = 1.0

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                               object: audioEngine,
                                               queue: .main) { [weak self] _ in
            self?.handleAudioEngineConfigurationChange()
        }

        audioProcessController.activate()

        NSWorkspace.shared.publisher(for: \.runningApplications)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isRecording, !self.isRestartingSystemTap else { return }
                Task {
                    await self.restartSystemAudioTapIfNeeded()
                }
            }
            .store(in: &cancellables)
        
        // Initialize WhisperKit service
        Task {
            do {
                try await whisperKitService.initialize(modelPath: nil)
                print("✅ WhisperKit service initialized")
            } catch {
                print("❌ Failed to initialize WhisperKit: \(error)")
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func startRecording() {
        print("🎙️ Starting streaming recording...")

        sessionID = UUID()
        errorMessage = nil
        stopRecordingInternal()

        guard whisperKitService.isReady else {
            print("❌ WhisperKit not ready")
            self.errorMessage = "Local transcription service not ready. Please try again."
            return
        }

        // Start microphone capture
        startMicrophoneTap()
        
        // Start system audio capture
        Task {
            await self.startSystemAudioTap()
        }
    }

    private func stopRecordingInternal() {
        print("🧹 Internal cleanup...")

        if isTapActive {
            self.processTap?.invalidate()
            self.processTap = nil
            isTapActive = false
        }

        cleanupAudioEngine()

        // Cancel transcription tasks
        micTranscriptionTask?.cancel()
        micTranscriptionTask = nil
        systemTranscriptionTask?.cancel()
        systemTranscriptionTask = nil
        
        // Finish audio streams
        micAudioStream?.finish()
        micAudioStream = nil
        systemAudioStream?.finish()
        systemAudioStream = nil
        
        // Clear accumulators
        micAccumulator.removeAll()
        systemAccumulator.removeAll()
        sequenceNumber = 0

        print("✅ Internal cleanup completed")
    }

    private func startMicrophoneTap() {
        print("🎤 Starting microphone tap...")
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else {
            print("⚠️ Hardware not ready, retrying...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.startMicrophoneTap() }
            return
        }

        do {
            guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
                print("❌ Failed to create target format")
                return
            }
            
            guard let converter = AVAudioConverter(from: recordingFormat, to: targetFormat) else {
                print("❌ Failed to create converter")
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self = self else { return }

                // Calculate audio level
                if let ch = buffer.floatChannelData?[0] {
                    let frameCount = Int(buffer.frameLength)
                    let samples = UnsafeBufferPointer(start: ch, count: frameCount)
                    let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(frameCount))

                    DispatchQueue.main.async {
                        self.micAudioLevel = rms
                        AudioLevelManager.shared.updateMicLevel(rms)
                    }
                }

                self.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat, source: .mic)
            }

            audioEngine.prepare()
            try audioEngine.start()
            
            // Start transcription stream
            startLocalTranscription(source: .mic)
            
            print("✅ Microphone tap started")

        } catch {
            print("❌ Engine error: \(error)")
        }
    }
    
    private func cleanupAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.reset()
    }

    private func startSystemAudioTap(isRestart: Bool = false) async {
        print("🎧 Starting system audio tap...")
        
        if !isRestart {
            guard await checkSystemAudioPermissions() else {
                self.errorMessage = "System audio recording permission denied."
                return
            }
        }
        
        let allProcessObjectIDs = audioProcessController.processes.map { $0.objectID }
        let target = TapTarget.systemAudio(processObjectIDs: allProcessObjectIDs)
        let newTap = ProcessTap(target: target)
        newTap.activate()
        
        if let tapError = newTap.errorMessage {
            self.errorMessage = "Failed to activate system audio tap: \(tapError)"
            if !isRestart { stopRecording() }
            return
        }
        
        self.processTap = newTap
        self.isTapActive = true
        
        do {
            try startTapIO(newTap)
            
            if !isRestart {
                startLocalTranscription(source: .system)
                self.isRecording = true
                AudioLevelManager.shared.updateRecordingState(true)
                self.startAudioMonitoringIfNeeded()
            }
            print("✅ System audio tap started")
            
        } catch {
            self.errorMessage = "Failed to start system audio tap IO: \(error.localizedDescription)"
            newTap.invalidate()
            self.isTapActive = false
            if !isRestart { stopRecording() }
        }
    }

    private func restartSystemAudioTapIfNeeded() async {
        let newProcessObjectIDs = Set(audioProcessController.processes.map { $0.objectID })
        let currentProcessObjectIDs: Set<AudioObjectID>

        if case .systemAudio(let processObjectIDs) = self.processTap?.target {
            currentProcessObjectIDs = Set(processObjectIDs)
        } else {
            currentProcessObjectIDs = []
        }

        if newProcessObjectIDs != currentProcessObjectIDs {
            await restartSystemAudioTap()
        }
    }

    private func restartSystemAudioTap() async {
        guard isRecording else { return }

        isRestartingSystemTap = true
        defer { isRestartingSystemTap = false }

        if isTapActive {
            processTap?.invalidate()
            processTap = nil
            isTapActive = false
        }

        try? await Task.sleep(for: .milliseconds(250))
        guard self.isRecording else { return }

        await startSystemAudioTap(isRestart: true)
    }

    @MainActor
    private func checkSystemAudioPermissions() async -> Bool {
        if permission.status == .authorized {
            return true
        }

        permission.request()

        for _ in 0..<10 {
            if permission.status == .authorized {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        return permission.status == .authorized
    }

    private func startTapIO(_ tap: ProcessTap) throws {
        guard var streamDescription = tap.tapStreamDescription else {
            throw NSError(domain: "LocalAudioManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get audio format from tap."])
        }

        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw NSError(domain: "LocalAudioManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAudioFormat from tap."])
        }

        try tap.run(on: tapQueue) { [weak self] _, inInputData, _, _, _ in
            guard let self = self,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil) else {
                return
            }

            let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                           sampleRate: 16000,
                                           channels: 1,
                                           interleaved: false)!

            guard let converter = AVAudioConverter(from: format, to: targetFormat) else {
                return
            }

            // Calculate audio level
            if let ch = buffer.floatChannelData?[0] {
                let frameCount = Int(buffer.frameLength)
                let samples = UnsafeBufferPointer(start: ch, count: frameCount)
                let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(frameCount))

                DispatchQueue.main.async {
                    self.systemAudioLevel = rms
                    AudioLevelManager.shared.updateSystemLevel(rms)
                }
            }

            self.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat, source: .system)

        } invalidationHandler: { [weak self] _ in
            guard let self = self else { return }

            if !self.isRestartingSystemTap {
                Task {
                    await self.restartSystemAudioTap()
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        self.isRecording = false
        AudioLevelManager.shared.updateRecordingState(false)
        print("⏹️ Stopping recording...")

        if isTapActive {
            self.processTap?.invalidate()
            self.processTap = nil
            isTapActive = false
        }
        
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        // ✅ Flush any remaining audio before finishing streams
        flushAccumulatedAudio(source: .mic)
        flushAccumulatedAudio(source: .system)

        // Finish the streams
        micAudioStream?.finish()
        systemAudioStream?.finish()

        micTranscriptionTask = nil
        systemTranscriptionTask = nil
        micAudioStream = nil
        systemAudioStream = nil

        micAudioLevel = 0.0
        systemAudioLevel = 0.0
        AudioLevelManager.shared.updateMicLevel(0.0)
        AudioLevelManager.shared.updateSystemLevel(0.0)

        if isRecordingDueToMicFollowing {
            isRecordingDueToMicFollowing = false
            stopSilenceProbeTimer()
            activityTracker = nil
        }

        print("✅ Recording stopped")
    }

    // ✅ NEW: Process audio buffer with accumulation
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat, source: AudioSource) {
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status == .haveData, error == nil else {
            return
        }

        guard let channelData = outputBuffer.floatChannelData?[0] else {
            return
        }

        let frameCount = Int(outputBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        // Add to accumulator
        if source == .mic {
            micAccumulator.append(contentsOf: samples)
            
            // Send when we have enough (1 second chunks)
            if micAccumulator.count >= chunkSize {
                sendAccumulatedAudio(source: .mic)
            }
        } else {
            systemAccumulator.append(contentsOf: samples)
            
            // Send when we have enough (1 second chunks)
            if systemAccumulator.count >= chunkSize {
                sendAccumulatedAudio(source: .system)
            }
        }
    }

    // ✅ NEW: Send accumulated audio as chunk
    private func sendAccumulatedAudio(source: AudioSource) {
        let samples = source == .mic ? micAccumulator : systemAccumulator
        
        guard !samples.isEmpty else { return }
        
        let chunk = VoiceAudioChunk(
            samples: samples,
            timestamp: Date().timeIntervalSince1970,
            sampleRate: 16000,
            channels: 1,
            sequenceNumber: sequenceNumber,
            isFinal: false
        )
        
        sequenceNumber += 1
        
        if source == .mic {
            if let stream = micAudioStream {
                print("📤 [Mic] Sending \(samples.count) samples (\(Float(samples.count)/16000.0)s)")
                stream.yield(chunk)
            }
            micAccumulator.removeAll()
        } else {
            if let stream = systemAudioStream {
                print("📤 [System] Sending \(samples.count) samples (\(Float(samples.count)/16000.0)s)")
                stream.yield(chunk)
            }
            systemAccumulator.removeAll()
        }
    }

    // ✅ NEW: Flush remaining audio when stopping
    private func flushAccumulatedAudio(source: AudioSource) {
        let samples = source == .mic ? micAccumulator : systemAccumulator
        
        guard samples.count > 1600 else { return } // Only flush if we have meaningful audio (>0.1s)
        
        let chunk = VoiceAudioChunk(
            samples: samples,
            timestamp: Date().timeIntervalSince1970,
            sampleRate: 16000,
            channels: 1,
            sequenceNumber: sequenceNumber,
            isFinal: true  // Mark as final
        )
        
        sequenceNumber += 1
        
        if source == .mic {
            micAudioStream?.yield(chunk)
            micAccumulator.removeAll()
        } else {
            systemAudioStream?.yield(chunk)
            systemAccumulator.removeAll()
        }
    }

    // ✅ FIXED: Detached task for transcription
    private func startLocalTranscription(source: AudioSource) {
        print("🎯 Starting transcription for \(source)...")
        
        let (stream, continuation) = AsyncStream<VoiceAudioChunk>.makeStream()
        
        if source == .mic {
            micAudioStream = continuation
        } else {
            systemAudioStream = continuation
        }
        
        // ✅ Use detached task to avoid main actor blocking
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let options = STTOptions(language: "en")
            
            // Define the noise tokens Whisper commonly returns
            let noiseTokens = ["[BLANK_AUDIO]", "[SILENCE]", "[NOISE]", "[MUSIC]", "[LAUGHTER]"]
            
            print("🧠 [AI Loop] Started for \(source)")
            
            do {
                guard let whisperKitService = await self?.whisperKitService else { return }
                
                for try await segment in whisperKitService.transcribeStream(audioStream: stream, options: options) {
                    let originalText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // ✅ Check if the text contains any noise tokens
                    let isNoise = noiseTokens.contains { token in
                        originalText.localizedCaseInsensitiveContains(token)
                    }
                    
                    // Only proceed if it's not noise and not empty
                    if !originalText.isEmpty && !isNoise {
                        print("📥 [AI] \(source): \(originalText)")
                        
                        guard let self = self else { return }
                        await self.handleTranscriptionSegment(segment, source: source)
                    } else {
                        print("🗑️ [AI] \(source) Ignored noise/empty: \(originalText)")
                    }
                }
                print("🏁 [AI Loop] Ended for \(source)")
            } catch {
                if !Task.isCancelled {
                    print("❌ [AI Loop] Error for \(source): \(error)")
                }
            }
        }
        
        if source == .mic {
            micTranscriptionTask = task
        } else {
            systemTranscriptionTask = task
        }
        
        print("✅ Transcription setup complete for \(source)")
    }
    
    @MainActor
    private func handleTranscriptionSegment(_ segment: STTSegment, source: AudioSource) {
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !text.isEmpty else { return }
        
        let sourceLabel = source == .mic ? "🎙️ MIC" : "🖥️ SYS"
        
        if segment.confidence > 0.9 {
            print("\(sourceLabel) [FINAL]: \(text)")

            self.transcriptChunks.removeAll { !$0.isFinal && $0.source == source }
            
            let chunk = TranscriptChunk(
                timestamp: Date(),
                source: source,
                text: text,
                isFinal: true
            )
            self.transcriptChunks.append(chunk)
            self.activityTracker?.onTranscriptActivity()
            
        } else {
            print("\(sourceLabel) [INTERIM]: \(text)")
            
            self.transcriptChunks.removeAll { !$0.isFinal && $0.source == source }
            
            let chunk = TranscriptChunk(
                timestamp: Date(),
                source: source,
                text: text,
                isFinal: false
            )
            self.transcriptChunks.append(chunk)
        }
    }

    private func handleAudioEngineConfigurationChange() {
        print("🔔 Audio configuration changed")
        if micRetryCount < maxMicRetries {
            micRetryCount += 1
            cleanupAudioEngine()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startMicrophoneTap()
            }
        }
    }

    // MARK: - Auto-Recording & Mic Following
    // (Keep your existing implementations...)
    
    func enableAutoRecording() {
        guard !isAutoRecordingEnabled else { return }
        isAutoRecordingEnabled = true
        audioMonitor = SystemAudioMonitor()
        audioMonitor?.onAudioStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.handleSystemAudioStateChange(state)
            }
        }
    }

    private func startAudioMonitoringIfNeeded() {
        guard isAutoRecordingEnabled, let monitor = audioMonitor else { return }
        guard !monitor.isMonitoring else { return }
        try? monitor.startMonitoring()
    }

    func disableAutoRecording() {
        guard isAutoRecordingEnabled else { return }
        audioMonitor?.stopMonitoring()
        audioMonitor = nil
        autoStartDelay?.invalidate()
        autoStartDelay = nil
        autoStopDelay?.invalidate()
        autoStopDelay = nil
        isAutoRecordingEnabled = false
    }

    private func handleSystemAudioStateChange(_ state: SystemAudioMonitor.AudioState) {
        switch state {
        case .active:
            handleOtherAppStartedAudio()
        case .inactive:
            handleOtherAppStoppedAudio()
        }
    }

    private func handleOtherAppStartedAudio() {
        print("🎵 Audio detected")

        autoStopDelay?.invalidate()
        autoStopDelay = nil

        guard !isRecording else { return }

        autoStartDelay?.invalidate()
        autoStartDelay = Timer.scheduledTimer(withTimeInterval: startDelayTime, repeats: false) { [weak self] _ in
            guard let self = self, self.isAutoRecordingEnabled else { return }

            if self.audioMonitor?.audioState == .active && !self.isRecording {
                print("🎙️ Auto-starting recording...")
                self.startRecording()
            }
        }
    }

    private func handleOtherAppStoppedAudio() {
        print("🔇 Audio stopped")

        autoStartDelay?.invalidate()
        autoStartDelay = nil

        guard isRecording else { return }

        autoStopDelay?.invalidate()
        autoStopDelay = Timer.scheduledTimer(withTimeInterval: stopDelayTime, repeats: false) { [weak self] _ in
            guard let self = self, self.isAutoRecordingEnabled else { return }

            if self.audioMonitor?.audioState == .inactive && self.isRecording {
                print("⏹️ Auto-stopping recording...")
                self.stopRecording()
            }
        }
    }

    // MARK: - Mic Following Methods

    func enableMicFollowing() {
        guard !isMicFollowingEnabled else { return }
        print("🎯 Enabling mic following (local)...")
        isMicFollowingEnabled = true

        micMonitor = MicUsageMonitor()
        micMonitor?.onMicStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.handleMicUsageStateChange(state)
            }
        }

        do {
            try micMonitor?.startMonitoring()
            print("✅ Mic following enabled (local)")
        } catch {
            print("❌ Failed to start mic monitoring: \(error)")
            errorMessage = "Failed to enable mic following: \(error.localizedDescription)"
            isMicFollowingEnabled = false
            micMonitor = nil
        }
    }

    func disableMicFollowing() {
        guard isMicFollowingEnabled else { return }
        print("🛑 Disabling mic following (local)...")

        micMonitor?.stopMonitoring()
        micMonitor = nil

        micFollowStartDelay?.invalidate()
        micFollowStartDelay = nil
        stopSilenceProbeTimer()

        activityTracker = nil

        if isRecording && isRecordingDueToMicFollowing {
            isRecordingDueToMicFollowing = false
            stopRecording()
        }

        isMicFollowingEnabled = false
        print("✅ Mic following disabled")
    }

    private func handleMicUsageStateChange(_ state: MicUsageMonitor.MicState) {
        switch state {
        case .active:
            handleOtherAppStartedMic()
        case .inactive:
            handleOtherAppStoppedMic()
        }
    }

    private func handleOtherAppStartedMic() {
        print("🎤 Mic usage detected")

        guard !isRecording else { return }

        micFollowStartDelay?.invalidate()
        micFollowStartDelay = Timer.scheduledTimer(withTimeInterval: micFollowStartDelayTime, repeats: false) { [weak self] _ in
            guard let self = self, self.isMicFollowingEnabled else { return }

            if self.micMonitor?.micState == .active && !self.isRecording {
                print("🎙️ Auto-starting mic recording...")
                self.isRecordingDueToMicFollowing = true
                self.activityTracker = ActivityTracker()
                self.createMicFollowingSession()
//                self.startMicrophoneOnlyRecording()
                self.startSilenceProbeTimer()
            }
        }
    }

    private func startSilenceProbeTimer() {
        silenceProbeTimer?.invalidate()
        silenceProbeTimer = Timer.scheduledTimer(withTimeInterval: probeInterval, repeats: true) { [weak self] _ in
            self?.probeForSilenceAndCheck()
        }
    }

    private func stopSilenceProbeTimer() {
        silenceProbeTimer?.invalidate()
        silenceProbeTimer = nil
    }

    private func probeForSilenceAndCheck() {
        guard let monitor = micMonitor, let tracker = activityTracker else { return }
        guard isRecording && isRecordingDueToMicFollowing else { return }

        let idleFor = tracker.secondsSinceLastActivity()

        if idleFor < silenceWindow {
            return
        }

        let wasRunning = audioEngine.isRunning
        if wasRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }

            let someoneElseUsing = monitor.currentIsRunningSomewhere()

            if someoneElseUsing {
                if wasRunning {
                    self.startMicrophoneTap()
                    tracker.reset()
                }
            } else {
                self.stopMicFollowingRecording()
            }
        }
    }

    private func stopMicFollowingRecording() {
        saveMicFollowingSession()
        stopSilenceProbeTimer()
        activityTracker = nil
        isRecordingDueToMicFollowing = false
        currentMicFollowingSession = nil
        stopRecording()
    }

    private func createMicFollowingSession() {
        let context = BrowserURLHelper.getCurrentContext()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, h:mm a"
        let formattedDate = dateFormatter.string(from: Date())
        
        let title: String
        if let contextName = context {
            title = "\(contextName) - \(formattedDate)"
        } else {
            title = "Recording - \(formattedDate)"
        }
        
        let session = TranscriptionSession(
            date: Date(),
            title: title,
            source: .micFollowing
        )
        currentMicFollowingSession = session
    }

    private func saveMicFollowingSession() {
        guard var session = currentMicFollowingSession else { return }

        session.transcriptChunks = transcriptChunks.filter { $0.isFinal }

        guard !session.transcriptChunks.isEmpty else { return }

        if let firstChunk = session.transcriptChunks.first,
           let lastChunk = session.transcriptChunks.last {
            let durationSeconds = lastChunk.timestamp.timeIntervalSince(firstChunk.timestamp)
            let durationMinutes = max(durationSeconds / 60.0, 0.1)

            if let analytics = AnalyticsCalculator.analyzeTranscript(
                chunks: session.transcriptChunks,
                durationMinutes: durationMinutes
            ) {
                session.analytics = analytics
            }
        }

        NotificationCenter.default.post(
            name: NSNotification.Name("SaveTranscriptionSession"),
            object: nil,
            userInfo: ["session": session]
        )
    }

    private func handleOtherAppStoppedMic() {
        // Handled by silence detection probe
    }
}

// MARK: - Simple VAD Implementation
class SimpleVAD {
    private let energyThreshold: Float = 0.005
    
    func isSpeech(samples: [Int16]) -> Bool {
        guard !samples.isEmpty else { return false }
        
        let floatSamples = samples.map { Float($0) / Float(Int16.max) }
        let energy = sqrt(floatSamples.map { $0 * $0 }.reduce(0, +) / Float(floatSamples.count))
        
        return energy > energyThreshold
    }
}
