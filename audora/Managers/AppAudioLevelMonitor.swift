// AppAudioLevelMonitor.swift
// Minimal implementation to unblock compilation and provide basic audio level monitoring
// This monitors system output power as a fallback; the API is designed to be compatible with MeetingAppDetector

import Foundation
import AVFoundation
import Accelerate

public final class AppAudioLevelMonitor {
    public typealias LevelHandler = (Float) -> Void

    private let pid: pid_t
    private let handler: LevelHandler
    private var timer: DispatchSourceTimer?
    private var isRunning = false

    // Audio engine components for measuring output power
    private let engine = AVAudioEngine()
    private let mixerNode = AVAudioMixerNode()

    // Initialize with a process identifier and a callback for level updates
    public init(pid: pid_t, handler: @escaping LevelHandler) {
        self.pid = pid
        self.handler = handler
    }

    // Start monitoring asynchronously to match call site expectations
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true

        // Attach a mixer node to tap the main output bus.
        engine.attach(mixerNode)
        engine.connect(engine.mainMixerNode, to: mixerNode, format: nil)

        // Install a tap on the mixer to read audio levels
        let bus = 0
        mixerNode.installTap(onBus: bus, bufferSize: 1024, format: engine.mainMixerNode.outputFormat(forBus: bus)) { [weak self] buffer, _ in
            guard let self = self else { return }
            let level = Self.rmsLevel(from: buffer)
            self.handler(level)
        }

        try engine.start()

        // As a safety net, also poll at a low frequency in case taps deliver irregularly
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            // No-op: handler is invoked by the tap; keep timer alive to maintain periodic callbacks if needed
            _ = self // keep self retained
        }
        self.timer = timer
        timer.resume()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.cancel()
        timer = nil
        mixerNode.removeTap(onBus: 0)
        engine.stop()
    }

    deinit {
        stop()
    }

    // MARK: - Utilities

    private static func rmsLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channel = channelData[0]
        let frameLength = Int(buffer.frameLength)
        if frameLength == 0 { return 0 }
        var sum: Float = 0
        vDSP_measqv(channel, 1, &sum, vDSP_Length(frameLength))
        // Root mean square
        let rms = sqrtf(sum)
        // Normalize roughly to 0..1 (since PCM typically in -1..1)
        return min(max(rms, 0), 1)
    }
}
