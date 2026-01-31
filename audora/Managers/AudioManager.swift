// AudioManager.swift
// Unified audio manager for microphone and system audio capture

import AVFoundation
import Foundation
import SwiftUI
import OSLog
import Combine
import AppKit

/// Manages audio capture from microphone and system audio and handles real-time transcription via OpenAI
@MainActor
class AudioManager: NSObject, ObservableObject {
    static let shared = AudioManager()

    @Published var transcriptChunks: [TranscriptChunk] = []
    @Published var isRecording = false
    @Published var errorMessage: String?
    @Published var micAudioLevel: Float = 0.0
    @Published var systemAudioLevel: Float = 0.0

    private var audioEngine = AVAudioEngine()
    private var micSocketTask: URLSessionWebSocketTask?
    private var systemSocketTask: URLSessionWebSocketTask?
    private let speechmaticsURL = URL(string: "wss://eu2.rt.speechmatics.com/v2/en")!


    // Unique identifier for the current recording session
    private var sessionID = UUID()

    // ProcessTap properties
    private var processTap: ProcessTap?
    private let audioProcessController = AudioProcessController()
    private let permission = AudioRecordingPermission()
    private let tapQueue = DispatchQueue(label: "io.audora.audiotap", qos: .userInitiated)
    private var isTapActive = false
    private var isRestartingSystemTap = false

    // Add properties near the top, after existing private vars
    private var micRetryCount = 0
    private let maxMicRetries = 3

    // Add current interim transcripts per source
    private var currentInterim: [AudioSource: String] = [.mic: "", .system: ""]

    // Add ping timers to keep WebSocket connections alive
    private var pingTimers: [AudioSource: Timer] = [:]
    private var cancellables = Set<AnyCancellable>()

    // Session refresh timers to prevent 30-minute expiry
    private var sessionRefreshTimers: [AudioSource: Timer] = [:]

    // Add reference to ConvexService
    var convexService: ConvexService? = ConvexService.shared


    private override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                               object: audioEngine,
                                               queue: .main) { [weak self] _ in
            self?.handleAudioEngineConfigurationChange()
        }

        // Activate the process controller to start monitoring audio-producing apps
        audioProcessController.activate()

        // When the list of running applications changes, check if we need to restart the system audio tap
        NSWorkspace.shared.publisher(for: \.runningApplications)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isTapActive else { return }

                print("🎤 Running applications changed, checking if tap restart is needed.")
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    await self.restartSystemAudioTapIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Audio Output Detection

    /// Detects whether the user is currently using headphones or speakers
    /// Returns true if headphones (wired or Bluetooth) are connected
    private func isUsingHeadphones() -> Bool {
        // macOS: Use Core Audio to check the default output device
        do {
            // Get the default output device
            let defaultOutputID = try AudioDeviceID.readDefaultSystemOutputDevice()

            // Check the device's transport type
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var transportType: UInt32 = 0
            var dataSize: UInt32 = UInt32(MemoryLayout<UInt32>.size)
            let err = AudioObjectGetPropertyData(defaultOutputID, &address, 0, nil, &dataSize, &transportType)

            guard err == noErr else {
                print("⚠️ Error reading audio device transport type: \(err)")
                return false
            }

            // Check if the transport type indicates headphones
            switch transportType {
            case kAudioDeviceTransportTypeBluetooth,
                 kAudioDeviceTransportTypeBluetoothLE:
                // Bluetooth devices are likely headphones/earbuds
                print("🎧 Detected Bluetooth headphones")
                return true
            default:
                // For other transport types (USB, BuiltIn, etc.), check device name
                if let deviceName = try? defaultOutputID.getDeviceName() {
                    let name = deviceName.lowercased()
                    // Check for common headphone/headset keywords
                    if name.contains("headphone") ||
                       name.contains("headset") ||
                       name.contains("airpods") ||
                       name.contains("beats") ||
                       name.contains("earbuds") ||
                       name.contains("earpods") {
                        print("🎧 Detected headphones via device name: \(deviceName)")
                        return true
                    }
                }

                print("🔊 Using built-in/external speakers")
                return false
            }
        } catch {
            print("⚠️ Error checking macOS audio output device: \(error)")
            return false
        }
    }

    func startRecording() {
        print("Starting recording...")

        // Bump session ID so any old async callbacks can be ignored
        sessionID = UUID()

        // Clear any previous errors
        DispatchQueue.main.async {
            self.errorMessage = nil
        }

        // Stop any in-progress recording
        stopRecordingInternal()

        // Validate authentication before connecting
        Task {
            // Check auth state
            let authState = await MainActor.run { ConvexService.shared.authState }
            guard case .authenticated = authState else {
                let errorMsg = "Please sign in to start recording."
                print("❌ Authentication required: \(errorMsg)")
                DispatchQueue.main.async {
                    self.errorMessage = errorMsg
                }
                return
            }

            // Proceed with taps after auth check
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Always start microphone - user prioritizes voice transcription
                self.startMicrophoneTap()

                // Check audio output device
                let usingHeadphones = self.isUsingHeadphones()

                if usingHeadphones {
                    print("🎧 Headphones detected - optimal recording setup")
                } else {
                    // Using speakers - warn about potential duplicates but still record
                    print("🔊 Speakers detected - may have some echo/duplicates")
                    print("💡 Connect headphones for best results (prevents echo)")
                }

                // Always start system audio capture
                Task {
                    await self.startSystemAudioTap()
                }
            }
        }
    }



    private func stopRecordingInternal() {
        print("Internal cleanup...")

        // Stop system audio capture
        if isTapActive {
            self.processTap?.invalidate()
            self.processTap = nil
            isTapActive = false
            print("System audio tap invalidated")
        }

        // Stop microphone capture
        cleanupAudioEngine()

        // Close WebSocket
        micSocketTask?.cancel(with: .normalClosure, reason: nil)
        micSocketTask = nil
        systemSocketTask?.cancel(with: .normalClosure, reason: nil)
        systemSocketTask = nil

        // Invalidate ping timers
        pingTimers.values.forEach { $0.invalidate() }
        pingTimers.removeAll()

        // Invalidate session refresh timers
        sessionRefreshTimers.values.forEach { $0.invalidate() }
        sessionRefreshTimers.removeAll()

        // Reset state
        // (isRecording already cleared in stopRecording)

        print("Internal cleanup completed")
    }

    private func restartMicrophone() {
        guard isRecording, micRetryCount < maxMicRetries else { return }

        print("🔄 Restarting microphone capture (attempt \(micRetryCount + 1))")
        micRetryCount += 1

        cleanupAudioEngine()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startMicrophoneTap()
        }
    }

    /// Starts a microphone tap without creating a new OpenAI connection (used when also capturing system audio)
    private func startMicrophoneTap() {
        print("🎤 Starting microphone tap...")

        do {
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                             sampleRate: 24000,
                                             channels: 1,
                                             interleaved: false) else {
                print("❌ Failed to create target audio format for mic tap")
                self.restartMicrophone()
                return
            }

            guard let converter = AVAudioConverter(from: recordingFormat, to: targetFormat) else {
                print("❌ Failed to create audio converter for mic tap")
                self.restartMicrophone()
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self = self else { return }

                // Check for invalid buffer
                guard buffer.frameLength > 0, buffer.floatChannelData != nil else {
                    print("❌ Invalid mic buffer detected - restarting")
                    self.restartMicrophone()
                    return
                }

                // Calculate audio level for visual indicator
                if let ch = buffer.floatChannelData?[0] {
                    let frameCount = Int(buffer.frameLength)
                    let samples = UnsafeBufferPointer(start: ch, count: frameCount)
                    let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(frameCount))

                    // Update the published audio level on main thread
                    DispatchQueue.main.async {
                        self.micAudioLevel = rms
                        AudioLevelManager.shared.updateMicLevel(rms)
                    }
                }

                // Record audio buffer
                AudioRecordingManager.shared.recordMicBuffer(buffer, format: recordingFormat)

                self.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat, source: .mic)
            }

            audioEngine.prepare()
            try audioEngine.start()
            connectToSpeechmatics(source: .mic)
            print("✅ Microphone tap started successfully")
            micRetryCount = 0  // Reset on success

        } catch {
            print("❌ Failed to start microphone tap: \(error)")
            self.restartMicrophone()
        }
    }

    private func cleanupAudioEngine() {
        print("🧹 Cleaning up audio engine...")

        // Stop the engine first
        if audioEngine.isRunning {
            audioEngine.stop()
            print("⏹️ Audio engine stopped")
        }

        // Remove any existing taps on the input node
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        print("🔇 Input tap removed")

        // Reset the audio engine - this removes all connections and taps
        audioEngine.reset()
        print("🔄 Audio engine reset")

        // Create a fresh audio engine to ensure clean state
        audioEngine = AVAudioEngine()
        print("✨ Fresh audio engine created")
    }

    private func startSystemAudioTap(isRestart: Bool = false) async {
        print(isRestart ? "🎧 Restarting system audio tap logic..." : "🎧 Starting system audio tap for the first time...")

        if !isRestart {
            guard await checkSystemAudioPermissions() else {
                let errorMsg = "System audio recording permission denied."
                print("❌ \(errorMsg)")
                self.errorMessage = errorMsg
                return
            }
        }

        // Get all running processes that are producing audio
        let allProcessObjectIDs = audioProcessController.processes.map { $0.objectID }

        // Provide better diagnostics
        print("📊 Found \(allProcessObjectIDs.count) audio-producing process(es)")
        if allProcessObjectIDs.isEmpty {
            print("⚠️ No audio-producing processes found. System audio tap might not capture anything.")
            print("   💡 Make sure an app is playing audio (Zoom, Teams, etc.)")
        } else {
            let processNames = audioProcessController.processes.prefix(3).map { $0.name }
            print("   Processes: \(processNames.joined(separator: ", "))\(audioProcessController.processes.count > 3 ? "..." : "")")
        }

        // Configure the tap for system-wide audio
        let target = TapTarget.systemAudio(processObjectIDs: allProcessObjectIDs)
        let newTap = ProcessTap(target: target)
        newTap.activate()

        // Check for activation errors
        if let tapError = newTap.errorMessage {
            var errorMsg = "Failed to activate system audio tap: \(tapError)"

            // Provide helpful guidance based on error
            if tapError.contains("error 560947818") || tapError.contains("error -536870206") {
                errorMsg += "\n\n💡 This usually means:\n"
                errorMsg += "   1. Screen Recording permission is required\n"
                errorMsg += "   2. Go to System Settings > Privacy & Security > Screen & System Audio Recording\n"
                errorMsg += "   3. Enable Audora in the list\n"
                errorMsg += "   4. Restart the app after granting permission"
            } else if allProcessObjectIDs.isEmpty {
                errorMsg += "\n\n💡 No audio-producing apps detected. Start a meeting app (Zoom, Teams, etc.) first."
            }

            print("❌ \(errorMsg)")
            self.errorMessage = errorMsg
            if !isRestart { stopRecording() }
            return
        }

        self.processTap = newTap
        self.isTapActive = true

        // Start receiving audio data from the tap
        do {
            try startTapIO(newTap)

            if !isRestart {
                connectToSpeechmatics(source: .system)
                self.isRecording = true
                AudioLevelManager.shared.updateRecordingState(true)
            }
            print("✅ System audio tap started successfully (isRestart: \(isRestart))")

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
            print("Process list has changed. Restarting system audio tap.")
            await restartSystemAudioTap()
        } else {
            print("Process list is the same. No restart needed.")
        }
    }

    private func restartSystemAudioTap() async {
        print("🔄 Restarting system audio tap...")

        guard isRecording else {
            print("Recording was stopped, aborting tap restart.")
            return
        }

        isRestartingSystemTap = true
        defer { isRestartingSystemTap = false }

        // 1. Invalidate existing tap
        if isTapActive {
            processTap?.invalidate()
            processTap = nil
            isTapActive = false
            print("System audio tap invalidated for restart.")
        }

        // A small delay to let things settle.
        try? await Task.sleep(for: .milliseconds(250))

        guard self.isRecording else {
            print("Recording was stopped during tap restart. Aborting.")
            return
        }

        // 2. Start a new one, but don't re-connect to OpenAI or change recording state
        await startSystemAudioTap(isRestart: true)
    }

    @MainActor
    private func checkSystemAudioPermissions() async -> Bool {
        if permission.status == .authorized {
            return true
        }

        permission.request()

        // Poll for a short time to see if permission is granted
        for _ in 0..<10 {
            if permission.status == .authorized {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        return permission.status == .authorized
    }

    private func startTapIO(_ tap: ProcessTap) throws {
        guard var streamDescription = tap.tapStreamDescription else {
            throw NSError(domain: "AudioManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get audio format from tap."])
        }

        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw NSError(domain: "AudioManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAudioFormat from tap."])
        }

        try tap.run(on: tapQueue) { [weak self] _, inInputData, _, _, _ in
            guard let self = self else { return }

            // Check if tap is still active before processing
            guard self.isTapActive, self.processTap === tap else {
                // Tap was invalidated, stop processing
                return
            }

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil) else {
                return
            }

            let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                           sampleRate: 24000,
                                           channels: 1,
                                           interleaved: false)!

            guard let converter = AVAudioConverter(from: format, to: targetFormat) else {
                return
            }

            // Calculate audio level for visual indicator
            if let ch = buffer.floatChannelData?[0] {
                let frameCount = Int(buffer.frameLength)
                let samples = UnsafeBufferPointer(start: ch, count: frameCount)
                let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(frameCount))

                // Update the published audio level on main thread
                DispatchQueue.main.async {
                    self.systemAudioLevel = rms
                    AudioLevelManager.shared.updateSystemLevel(rms)
                }
            }

            // Record audio buffer
            AudioRecordingManager.shared.recordSystemBuffer(buffer, format: format)

            self.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat, source: .system)

        } invalidationHandler: { [weak self] invalidatedTap in
            guard let self else { return }
            print("Audio tap was invalidated.")

            // Mark tap as inactive immediately to prevent further processing
            self.isTapActive = false

            // Only restart if this was unexpected and we're still recording
            if !self.isRestartingSystemTap && self.isRecording {
                print("Tap invalidated unexpectedly. Restarting system audio tap.")
                Task { @MainActor in
                    // Small delay to let Core Audio clean up
                    try? await Task.sleep(for: .milliseconds(100))
                    await self.restartSystemAudioTap()
                }
            } else {
                print("Tap invalidated as part of a restart or recording stopped. Not restarting.")
            }
        }
    }

    func stopRecording() {
        // Immediately mark as not recording to prevent stale callbacks
        self.isRecording = false
        AudioLevelManager.shared.updateRecordingState(false)
        print("Stopping recording...")

        // Reset audio levels
        micAudioLevel = 0.0
        systemAudioLevel = 0.0
        AudioLevelManager.shared.updateMicLevel(0.0)
        AudioLevelManager.shared.updateSystemLevel(0.0)

        // Stop system audio capture
        if isTapActive {
            self.processTap?.invalidate()
            self.processTap = nil
            isTapActive = false
            print("System audio tap invalidated")
        }

        // Stop microphone capture
        cleanupAudioEngine()
        micRetryCount = 0

        // Close WebSocket
        micSocketTask?.cancel(with: .normalClosure, reason: nil)
        micSocketTask = nil
        systemSocketTask?.cancel(with: .normalClosure, reason: nil)
        systemSocketTask = nil

        // Invalidate ping timers
        pingTimers.values.forEach { $0.invalidate() }
        pingTimers.removeAll()

        // Invalidate session refresh timers
        sessionRefreshTimers.values.forEach { $0.invalidate() }
        sessionRefreshTimers.removeAll()



        print("Recording stopped")
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat, source: AudioSource) {
        let processBuffer = buffer

        // Convert to target format (24kHz int16 mono) in a single step – AVAudioConverter will handle resampling and downmixing
        let outputFrameCapacity = AVAudioFrameCount(Double(processBuffer.frameLength) * targetFormat.sampleRate / processBuffer.format.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return processBuffer
        }

        guard status == .haveData, error == nil else {
            return
        }

        // Convert to Data for OpenAI
        guard let channelData = outputBuffer.int16ChannelData?[0] else {
            return
        }

        let frameCount = Int(outputBuffer.frameLength)
        let data = Data(bytes: channelData, count: frameCount * 2)

        sendAudioData(data, source: source)
    }

    private func connectToSpeechmatics(source: AudioSource) {
        // Use Convex Service to fetch JWT
        let session = URLSession(configuration: .default)
        var request = URLRequest(url: speechmaticsURL)

        Task { [weak self] in
            guard let self = self else { return }

            do {
                if let convexService = self.convexService {
                    let jwt = try await convexService.getSpeechmaticsJWT()
                    request.addValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
                } else {
                     throw NSError(domain: "AudioManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Convex Service not initialized"])
                }

                await self.establishConnection(request: request, session: session, source: source)

            } catch {
                let errorMsg = "\(ErrorMessage.configurationFailed): \(ErrorHandler.shared.handleError(error))"
                print("❌ \(errorMsg)")
                print("❌ Raw Error Detail: \(error)") // Log raw error for debugging
                await MainActor.run {
                    self.errorMessage = errorMsg
                }
            }
        }
    }

    private func establishConnection(request: URLRequest, session: URLSession, source: AudioSource) async {
        let task = session.webSocketTask(with: request)

        // Add connection monitoring
        task.resume()

        // Set up ping timer to keep connection alive
        pingTimers[source]?.invalidate()
        let pingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let task = source == .mic ? self.micSocketTask : self.systemSocketTask
            guard let socket = task, socket.state == .running else { return }
            socket.sendPing { error in
                if let error = error {
                    print("❌ Ping failed for \(source): \(error)")
                } else {
                    print("🏓 Ping sent for \(source)")
                }
            }
        }
        pingTimers[source] = pingTimer

        // Set up session refresh timer to prevent 30-minute expiry (refresh after 28 minutes)
        sessionRefreshTimers[source]?.invalidate()
        let sessionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 28 * 60.0, repeats: false) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            print("📝 Proactively refreshing session for \(source) to prevent expiry...")
                self.connectToSpeechmatics(source: source)
        }
        sessionRefreshTimers[source] = sessionRefreshTimer

        let thisSession = sessionID
        // Monitor connection state (ignore if session changed or recording stopped)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self, weak task] in
            guard let self = self, self.sessionID == thisSession, self.isRecording else { return }
            guard let task = task, task.state != .running else { return }
            let errorMsg = ErrorMessage.connectionTimeout
            print("❌ \(errorMsg)")
            DispatchQueue.main.async {
                self.errorMessage = errorMsg
            }
        }

        // Send initial configuration for Speechmatics V2
        let config: [String: Any] = [
            "message": "StartRecognition",
            "audio_format": [
                "type": "raw",
                "encoding": "pcm_s16le",
                "sample_rate": 24000
            ],
            "transcription_config": [
                "language": "en",
                "enable_partials": true,
                "max_delay": 2
            ]
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: config)
            if let jsonStr = String(data: jsonData, encoding: .utf8) {
                task.send(.string(jsonStr)) { [weak self] error in
                    if let error = error {
                        guard let self = self, self.sessionID == thisSession else { return }

                        // Ignore cancellation errors, which are expected when stopping a session.
                        if (error as? URLError)?.code == .cancelled {
                            return
                        }

                        let errorMsg = "\(ErrorMessage.configurationFailed): \(ErrorHandler.shared.handleError(error))"
                        print("❌ \(errorMsg)")
                        DispatchQueue.main.async {
                            self.errorMessage = errorMsg
                        }
                    }
                }
            }
        } catch {
            let errorMsg = "\(ErrorMessage.configurationFailed): \(ErrorHandler.shared.handleError(error))"
            print("❌ \(errorMsg)")
            DispatchQueue.main.async {
                self.errorMessage = errorMsg
            }
        }

        switch source {
        case .mic:
            micSocketTask = task
        case .system:
            systemSocketTask = task
        }

        receiveMessage(for: source, sessionID: thisSession)
        print("🌐 Connected to Speechmatics (\(source))")
    }

    private func receiveMessage(for source: AudioSource, sessionID: UUID) {
        let task: URLSessionWebSocketTask? = (source == .mic) ? micSocketTask : systemSocketTask
        task?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.parseRealtimeEvent(text, source: source)
                case .data:
                    break
                @unknown default:
                    break
                }
                // Continue loop for this session
                if let self = self, self.sessionID == sessionID {
                    self.receiveMessage(for: source, sessionID: sessionID)
                }
            case .failure(let error):
                guard let self = self, self.sessionID == sessionID else { return } // Stale callback
                // Ignore errors caused by intentional socket closure after recording stops
                if self.isRecording == false { return }

                let errorMsg = self.handleWebSocketError(error, source: source)
                print("❌ Receive error (\(source)): \(error)")

                // Check if this is a session expiry - if so, don't show as persistent error
                let isSessionExpiry = errorMsg == ErrorMessage.sessionExpired

                if isSessionExpiry {
                    // For session expiry, show temporary message
                    DispatchQueue.main.async {
                        self.errorMessage = errorMsg
                        // Clear the message after a few seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            if self.errorMessage == errorMsg {
                                self.errorMessage = nil
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.errorMessage = errorMsg
                    }

                    // Only attempt reconnect for network errors, not API errors
                    if ErrorHandler.shared.shouldRetry(error) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                            guard let self = self, self.isRecording, self.sessionID == sessionID else { return }
                            self.connectToSpeechmatics(source: source)
                        }
                    }
                }
            }
        }
    }

    private func handleWebSocketError(_ error: Error, source: AudioSource) -> String {
        // Check for session expiry in error description first
        let errorDescription = error.localizedDescription.lowercased()
        if errorDescription.contains("session hit the maximum duration") ||
           errorDescription.contains("session expired") {
            // Handle session expiry by automatically restarting the connection
            print("📝 Session expired for \(source) (WebSocket error), attempting to restart connection...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, self.isRecording else { return }
                self.connectToSpeechmatics(source: source)
            }
            // Return session expired message but don't stop recording
            return ErrorMessage.sessionExpired
        }

        // Check for WebSocket close codes
        if let closeCode = (error as NSError?)?.userInfo["closeCode"] as? Int {
            return ErrorHandler.shared.handleWebSocketCloseCode(closeCode)
        }

        // Use centralized error handler for all other errors
        return ErrorHandler.shared.handleError(error)
    }



    private func parseRealtimeEvent(_ text: String, source: AudioSource) {
        // Parse JSON message
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        guard let messageType = json["message"] as? String else { return }

        switch messageType {
        case "AddTranscript":
            // Handle transcriptions
            guard let metadata = json["metadata"] as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { return }

            var transcriptBuffer = ""
            var isFinal = false

            // Check if this is a final transcript (Speechmatics default is partial unless finalized)
            // Actually Speechmatics V2 sends 'AddTranscript' for both.
            // We use 'is_approximate' or similar fields if available, but usually V2 results are additive/corrections.
            // Simplified: If 'transcript' field exists in metadata, use it? No.
            // Iterate results.

            for result in results {
                if let alternatives = result["alternatives"] as? [[String: Any]],
                   let firstAlt = alternatives.first,
                   let content = firstAlt["content"] as? String {
                     transcriptBuffer += content + " "
                }
            }

            // Cleanup buffer
            transcriptBuffer = transcriptBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if transcriptBuffer.isEmpty { return }

            // Speechmatics V2 sends finalized results when "is_eos" is true?
            // Or look at 'type' in results?
            // For now, treat all AddTranscript as partials updating the current view,
            // unless we determine it's a stabilized segment.
            // To properly match OpenAI's 'delta' vs 'completed', we'd need to track sequence numbers.
            // For simplicity in this migration: treating as STREAMING updates.

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                // For Speechmatics, AddTranscript usually contains new words.
                // However, without complex logic, we might just append?
                // Actually, 'results' contains a list of words.

                // Let's assume we treat it as an update to the current "Interim"
                self.currentInterim[source] = (self.currentInterim[source] ?? "") + " " + transcriptBuffer

                // Update the UI chunk (marking as interim)

                // Remove previous interim chunk
                if let lastIndex = self.transcriptChunks.lastIndex(where: { !$0.isFinal && $0.source == source }) {
                    self.transcriptChunks.remove(at: lastIndex)
                }

                let chunk = TranscriptChunk(
                    timestamp: Date(),
                    source: source,
                    text: self.currentInterim[source] ?? "",
                    isFinal: false // Keep it false until EndOfTranscript or explicit finalization logic
                )
                self.transcriptChunks.append(chunk)
            }

        case "EndOfTranscript":
             // Mark current interim as final
             DispatchQueue.main.async { [weak self] in
                 guard let self = self else { return }

                 let finalText = self.currentInterim[source] ?? ""
                 if finalText.isEmpty { return }

                 // Remove interim
                 self.transcriptChunks.removeAll { !$0.isFinal && $0.source == source }

                 let chunk = TranscriptChunk(
                     timestamp: Date(),
                     source: source,
                     text: finalText,
                     isFinal: true
                 )
                 self.transcriptChunks.append(chunk)
                 self.currentInterim[source] = ""
             }

        case "AudioAdded":
            // Ack
            break

        case "Error":
             if let type = json["type"] as? String, let reason = json["reason"] as? String {
                 print("❌ Speechmatics Error: \(type) - \(reason)")
                 let errorMessage = "Transcription Error: \(reason)"
                 DispatchQueue.main.async {
                     self.errorMessage = errorMessage
                 }
             }

        default:
            print("Unknown Speechmatics message: \(messageType)")
        }
    }



    private func sendMessage(_ message: [String: Any], source: AudioSource) {
        let task: URLSessionWebSocketTask? = (source == .mic) ? micSocketTask : systemSocketTask
        guard let socket = task, socket.state == .running else { return }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if let jsonStr = String(data: jsonData, encoding: .utf8) {
                socket.send(.string(jsonStr)) { error in
                    if let error = error {
                        print("❌ Failed to send message: \(error)")
                    }
                }
            }
        } catch {
             print("❌ Failed to serialize message")
        }
    }

    private func sendAudioData(_ data: Data, source: AudioSource) {
        let task: URLSessionWebSocketTask? = (source == .mic) ? micSocketTask : systemSocketTask

        guard let socket = task, socket.state == .running else { return }

        // Speechmatics accepts raw binary messages
        let thisSession = self.sessionID

        // Just send the data
        socket.send(.data(data)) { [weak self] error in
             if let error = error {
                 guard let self = self, self.sessionID == thisSession else { return }

                 // Ignore cancellation errors
                 if (error as? URLError)?.code == .cancelled {
                     return
                 }
                 print("❌ Send error (\(source)): \(error)")
             }
        }
    }

    // MARK: - Helper Methods

    private func handleAudioEngineConfigurationChange() {
        print("� Audio engine configuration changed - restarting mic")
        restartMicrophone()
    }
}
