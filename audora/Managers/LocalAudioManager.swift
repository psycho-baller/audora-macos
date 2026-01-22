// LocalAudioManager.swift
// On-device audio manager using RunAnywhere SDK for local transcription

import AVFoundation
import Foundation
import SwiftUI
import OSLog
import Combine
import AppKit
import RunAnywhere
import WhisperKitTranscription

/// Manages audio capture and on-device transcription using RunAnywhere SDK
@MainActor
class LocalAudioManager: NSObject, ObservableObject {
    static let shared = LocalAudioManager()

    @Published var transcriptChunks: [TranscriptChunk] = []
    @Published var isRecording = false
    @Published var errorMessage: String?
    @Published var micAudioLevel: Float = 0.0
    @Published var systemAudioLevel: Float = 0.0

    private var audioEngine = AVAudioEngine()
    private var voicePipeline: ModularVoicePipeline?
    
    // Unique identifier for the current recording session
    private var sessionID = UUID()

    // ProcessTap properties for system audio
    private var processTap: ProcessTap?
    private let audioProcessController = AudioProcessController()
    private let permission = AudioRecordingPermission()
    private let tapQueue = DispatchQueue(label: "io.audora.localtap", qos: .userInitiated)
    private var isTapActive = false
    private var isRestartingSystemTap = false

    // Retry mechanism
    private var micRetryCount = 0
    private let maxMicRetries = 3

    // Buffer for accumulating audio for transcription
    private var micAudioBuffer: [Int16] = []
    private var systemAudioBuffer: [Int16] = []
    private let bufferSizeThreshold = 48000 // ~2 seconds at 24kHz
    
    // VAD for detecting speech
    private var vadDetector: SimpleVAD?
    private var isSpeaking = false
    private var silenceFrames = 0
    private let silenceThreshold = 20 // frames of silence before processing
    
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Auto-Recording Properties
    @Published var isAutoRecordingEnabled = false
    private var audioMonitor: SystemAudioMonitor?
    private var autoStartDelay: Timer?
    private var autoStopDelay: Timer?
    private let startDelayTime: TimeInterval = 0.5
    private let stopDelayTime: TimeInterval = 3.0

    // MARK: - Mic Following Properties
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
        
        // Initialize VAD
        vadDetector = SimpleVAD()
        
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            self?.handleAudioEngineConfigurationChange()
        }

        audioProcessController.activate()

        NSWorkspace.shared.publisher(for: \.runningApplications)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isTapActive else { return }
                Task {
                    await self.restartSystemAudioTapIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func startRecording() {
        print("🎙️ Starting local recording...")

        // Start a new session
        sessionID = UUID()
        errorMessage = nil

        // Stop any previous recording cleanly
        stopRecordingInternal()

        // Start audio taps for microphone and system audio
        startMicrophoneTap()
        
        Task {
            await startSystemAudioTap()
        }
    }

    private func startMicrophoneOnlyRecording() {
        print("🎤 Starting microphone-only local recording...")
        
        sessionID = UUID()
        
        DispatchQueue.main.async {
            self.errorMessage = nil
        }

        stopRecordingInternal()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.startMicrophoneTap()
            self.isRecording = true
            AudioLevelManager.shared.updateRecordingState(true)
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
        
        // Process any remaining audio in buffers
        processRemainingAudio()

        print("✅ Internal cleanup completed")
    }

    private func restartMicrophone() {
        guard isRecording, micRetryCount < maxMicRetries else { return }

        print("🔄 Restarting microphone (attempt \(micRetryCount + 1))")
        micRetryCount += 1

        cleanupAudioEngine()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startMicrophoneTap()
        }
    }

    private func startMicrophoneTap() {
        print("🎤 Starting local microphone tap...")

        do {
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16000, // WhisperKit uses 16kHz
                channels: 1,
                interleaved: false
            ) else {
                print("❌ Failed to create target format")
                self.restartMicrophone()
                return
            }

            guard let converter = AVAudioConverter(from: recordingFormat, to: targetFormat) else {
                print("❌ Failed to create audio converter")
                self.restartMicrophone()
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self = self else { return }

                guard buffer.frameLength > 0, buffer.floatChannelData != nil else {
                    print("❌ Invalid mic buffer - restarting")
                    self.restartMicrophone()
                    return
                }

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

                self.activityTracker?.onAudioBuffer(buffer)
                self.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat, source: .mic)
            }

            audioEngine.prepare()
            try audioEngine.start()
            print("✅ Local microphone tap started")
            micRetryCount = 0

        } catch {
            print("❌ Failed to start mic tap: \(error)")
            self.restartMicrophone()
        }
    }

    private func cleanupAudioEngine() {
        print("🧹 Cleaning up audio engine...")

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.reset()
        audioEngine = AVAudioEngine()
        
        print("✨ Fresh audio engine created")
    }

    private func startSystemAudioTap(isRestart: Bool = false) async {
        print(isRestart ? "🎧 Restarting system audio tap..." : "🎧 Starting system audio tap...")

        if !isRestart {
            guard await checkSystemAudioPermissions() else {
                let errorMsg = "System audio recording permission denied."
                print("❌ \(errorMsg)")
                self.errorMessage = errorMsg
                return
            }
        }

        let allProcessObjectIDs = audioProcessController.processes.map { $0.objectID }
        if allProcessObjectIDs.isEmpty {
            print("⚠️ No audio-producing processes found")
        }

        let target = TapTarget.systemAudio(processObjectIDs: allProcessObjectIDs)
        let newTap = ProcessTap(target: target)
        newTap.activate()

        if let tapError = newTap.errorMessage {
            let errorMsg = "Failed to activate system audio tap: \(tapError)"
            print("❌ \(errorMsg)")
            self.errorMessage = errorMsg
            if !isRestart { stopRecording() }
            return
        }

        self.processTap = newTap
        self.isTapActive = true

        do {
            try startTapIO(newTap)

            if !isRestart {
                self.isRecording = true
                AudioLevelManager.shared.updateRecordingState(true)
                self.startAudioMonitoringIfNeeded()
            }
            print("✅ System audio tap started")

        } catch {
            let errorMsg = "Failed to start system audio tap IO: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            self.errorMessage = errorMsg
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
            print("🔄 Process list changed, restarting tap")
            await restartSystemAudioTap()
        }
    }

    private func restartSystemAudioTap() async {
        print("🔄 Restarting system audio tap...")

        guard isRecording else {
            print("⚠️ Recording stopped, aborting restart")
            return
        }

        isRestartingSystemTap = true
        defer { isRestartingSystemTap = false }

        if isTapActive {
            processTap?.invalidate()
            processTap = nil
            isTapActive = false
        }

        try? await Task.sleep(for: .milliseconds(250))

        guard self.isRecording else {
            print("⚠️ Recording stopped during restart")
            return
        }

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
            throw NSError(domain: "LocalAudioManager", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to get audio format"])
        }

        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw NSError(domain: "LocalAudioManager", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAudioFormat"])
        }

        try tap.run(on: tapQueue) { [weak self] _, inInputData, _, _, _ in
            guard let self = self,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil) else {
                return
            }

            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            )!

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
            guard let self else { return }
            print("⚠️ Audio tap invalidated")

            if !self.isRestartingSystemTap {
                print("🔄 Unexpected invalidation, restarting")
                Task {
                    await self.restartSystemAudioTap()
                }
            }
        }
    }

    func stopRecording() {
        self.isRecording = false
        AudioLevelManager.shared.updateRecordingState(false)
        print("⏹️ Stopping local recording...")

        micAudioLevel = 0.0
        systemAudioLevel = 0.0
        AudioLevelManager.shared.updateMicLevel(0.0)
        AudioLevelManager.shared.updateSystemLevel(0.0)

        if isTapActive {
            self.processTap?.invalidate()
            self.processTap = nil
            isTapActive = false
        }

        cleanupAudioEngine()
        micRetryCount = 0
        
        // Process remaining audio
        processRemainingAudio()

        if isRecordingDueToMicFollowing {
            isRecordingDueToMicFollowing = false
            stopSilenceProbeTimer()
            activityTracker = nil
        }

        print("✅ Local recording stopped")
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, 
                                   targetFormat: AVAudioFormat, source: AudioSource) {
        // Convert to target format
        let outputFrameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate
        )
        
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

        guard let channelData = outputBuffer.int16ChannelData?[0] else {
            return
        }

        let frameCount = Int(outputBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        // Add to appropriate buffer
        switch source {
        case .mic:
            micAudioBuffer.append(contentsOf: samples)
            
            // Check VAD and process when we have enough data
            if let vad = vadDetector {
                let isSpeechDetected = vad.isSpeech(samples: samples)
                
                if isSpeechDetected {
                    isSpeaking = true
                    silenceFrames = 0
                } else if isSpeaking {
                    silenceFrames += 1
                    
                    // If we've had enough silence, process the accumulated audio
                    if silenceFrames >= silenceThreshold {
                        processAccumulatedAudio(source: .mic)
                        isSpeaking = false
                        silenceFrames = 0
                    }
                }
            }
            
            // Also process if buffer is too large
            if micAudioBuffer.count >= bufferSizeThreshold * 5 {
                processAccumulatedAudio(source: .mic)
            }
            
        case .system:
            systemAudioBuffer.append(contentsOf: samples)
            
            // Process system audio in larger chunks (every 3 seconds)
            if systemAudioBuffer.count >= bufferSizeThreshold * 3 {
                processAccumulatedAudio(source: .system)
            }
        }
    }

    private func processAccumulatedAudio(source: AudioSource) {
        let buffer = source == .mic ? micAudioBuffer : systemAudioBuffer
        
        guard !buffer.isEmpty else { return }
        
        // Create audio data
        let audioData = Data(bytes: buffer, count: buffer.count * 2)
        
        // Transcribe using RunAnywhere
        Task {
            do {
                let result = try await transcribeAudio(audioData, source: source)
                
                if !result.isEmpty {
                    await MainActor.run {
                        let chunk = TranscriptChunk(
                            timestamp: Date(),
                            source: source,
                            text: result,
                            isFinal: true
                        )
                        self.transcriptChunks.append(chunk)
                        self.activityTracker?.onTranscriptActivity()
                    }
                }
            } catch {
                print("❌ Transcription error: \(error)")
            }
        }
        
        // Clear the buffer
        if source == .mic {
            micAudioBuffer.removeAll()
        } else {
            systemAudioBuffer.removeAll()
        }
    }

    private func processRemainingAudio() {
        if !micAudioBuffer.isEmpty {
            processAccumulatedAudio(source: .mic)
        }
        if !systemAudioBuffer.isEmpty {
            processAccumulatedAudio(source: .system)
        }
    }

    private func transcribeAudio(_ audioData: Data, source: AudioSource) async throws -> String {
        print("📋 Audio Data: \(audioData.count) bytes")
        
        guard !audioData.isEmpty else {
            print("❌ Empty audio data")
            return ""
        }

        // Create proper audio format for WhisperKit
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,  // WhisperKit expects Float32
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            print("❌ Failed to create audio format")
            return ""
        }

        // Convert Int16 samples to Float32
        let sampleCount = audioData.count / 2  // Int16 = 2 bytes per sample
        var int16Samples = [Int16](repeating: 0, count: sampleCount)
        _ = int16Samples.withUnsafeMutableBytes { audioData.copyBytes(to: $0) }
        
        // Normalize to Float32 [-1.0, 1.0]
        let floatSamples = int16Samples.map { Float($0) / Float(Int16.max) }
        
        print("🎵 Audio stats - samples: \(floatSamples.count), duration: \(Float(floatSamples.count) / 16000.0)s")
        
        // Check if audio has actual content
        let maxAmplitude = floatSamples.map { abs($0) }.max() ?? 0.0
        let rms = sqrt(floatSamples.map { $0 * $0 }.reduce(0, +) / Float(floatSamples.count))
        print("🎵 Audio energy - max: \(maxAmplitude), rms: \(rms)")
        
        if rms < 0.001 {
            print("⚠️ Audio too quiet, skipping transcription")
            return ""
        }

        // Create audio buffer
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(floatSamples.count)) else {
            print("❌ Failed to create audio buffer")
            return ""
        }
        
        buffer.frameLength = buffer.frameCapacity
        if let channelData = buffer.floatChannelData?[0] {
            channelData.initialize(from: floatSamples, count: floatSamples.count)
        }

        // Convert buffer to Data that WhisperKit expects
        let properAudioData = Data(bytes: buffer.floatChannelData![0],
                                   count: Int(buffer.frameLength) * MemoryLayout<Float>.size)

        // Setup WhisperKit
        let config = STTConfiguration(modelId: "whisper-base")
        guard let sttService = try await WhisperKitServiceProvider.shared.createSTTService(configuration: config) as? WhisperKitService else {
            throw VoiceError.serviceNotInitialized
        }
        
        if !sttService.isReady {
            print("🔧 Initializing WhisperKit...")
            try await sttService.initialize(modelPath: nil)
        }

        let options = STTOptions()
        print("🚀 Transcribing...")
        
        let result = try await sttService.transcribe(audioData: properAudioData, options: options)
        
        if result.transcript.isEmpty {
            print("⚠️ Empty transcript returned")
        } else {
            print("✅ Transcript: \"\(result.transcript)\"")
        }
        
        return result.transcript
    }

    private func handleAudioEngineConfigurationChange() {
        print("🔔 Audio configuration changed")
        restartMicrophone()
    }

    // MARK: - Auto-Recording Methods

    func enableAutoRecording() {
        guard !isAutoRecordingEnabled else { return }
        print("🎯 Enabling auto-recording (local)...")
        isAutoRecordingEnabled = true

        audioMonitor = SystemAudioMonitor()
        audioMonitor?.onAudioStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.handleSystemAudioStateChange(state)
            }
        }

        print("✅ Auto-recording enabled (local)")
    }

    private func startAudioMonitoringIfNeeded() {
        guard isAutoRecordingEnabled, let monitor = audioMonitor else { return }
        guard !monitor.isMonitoring else { return }

        print("🎧 Starting audio monitoring...")
        do {
            try monitor.startMonitoring()
            print("✅ Audio monitoring active")
        } catch {
            print("❌ Failed to start monitoring: \(error)")
            errorMessage = "Failed to start audio monitoring: \(error.localizedDescription)"
        }
    }

    func disableAutoRecording() {
        guard isAutoRecordingEnabled else { return }
        print("🛑 Disabling auto-recording (local)...")

        audioMonitor?.stopMonitoring()
        audioMonitor = nil

        autoStartDelay?.invalidate()
        autoStartDelay = nil
        autoStopDelay?.invalidate()
        autoStopDelay = nil

        isAutoRecordingEnabled = false
        print("✅ Auto-recording disabled")
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
                self.startMicrophoneOnlyRecording()
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
