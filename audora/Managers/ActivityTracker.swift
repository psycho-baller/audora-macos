import AVFoundation
import Accelerate
import Foundation

/// Tracks audio activity to detect silence periods
final class ActivityTracker {
    private let silenceThreshold: Float = 0.015    // RMS threshold for silence (higher = less sensitive)
    private let minDb: Float = -35.0               // dB threshold (higher = less sensitive)
    private let queue = DispatchQueue(label: "io.audora.ActivityTracker")
    
    private var lastAudioActivity: TimeInterval = 0
    private var lastTranscriptActivity: TimeInterval = 0
    private var hasReceivedFirstBuffer = false
    private var lastLogTime: TimeInterval = 0
    
    /// Process audio buffer to detect activity
    func onAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            if frameCount == 0 { return }
            
            // Mark first buffer as baseline
            if !self.hasReceivedFirstBuffer {
                self.hasReceivedFirstBuffer = true
                self.lastAudioActivity = CACurrentMediaTime()
            }
            
            var rms: Float = 0
            vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))
            let db = 20 * log10(max(rms, 1e-9))
            
            let isActive = rms > self.silenceThreshold || db > self.minDb
            let now = CACurrentMediaTime()
            
            if isActive {
                self.lastAudioActivity = now
                
                // Log activity at most once per second
                if now - self.lastLogTime > 1.0 {
                    self.lastLogTime = now
                    print("🔊 Audio activity: RMS=\(String(format: "%.6f", rms)), dB=\(String(format: "%.1f", db))")
                }
            }
        }
    }
    
    /// Mark transcript activity (when receiving STT tokens)
    func onTranscriptActivity() {
        queue.async { [weak self] in
            self?.lastTranscriptActivity = CACurrentMediaTime()
            print("📝 Transcript activity detected")
        }
    }
    
    /// Get seconds since last activity (audio or transcript)
    func secondsSinceLastActivity() -> TimeInterval {
        queue.sync {
            let now = CACurrentMediaTime()
            let last = max(lastAudioActivity, lastTranscriptActivity)
            
            // If no activity recorded yet (timestamps still 0), return a large value
            if last == 0 {
                return 999999
            }
            
            return now - last
        }
    }
    
    /// Reset activity tracking (e.g., when starting recording)
    func reset() {
        queue.async { [weak self] in
            let now = CACurrentMediaTime()
            self?.lastAudioActivity = now
            self?.lastTranscriptActivity = now
        }
    }
}
