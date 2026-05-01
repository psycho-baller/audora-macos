import AVFoundation
import Foundation

@MainActor
final class VoiceMemoRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = VoiceMemoRecorder()

    @Published private(set) var isRecording = false
    @Published private(set) var permissionGranted = false
    @Published private(set) var lastRecordedURL: URL?
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?

    private override init() {
        super.init()
        refreshPermissionStatus()
    }

    func refreshPermissionStatus() {
        permissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func startRecording() {
        errorMessage = nil
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            beginRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    self?.permissionGranted = granted
                    if granted {
                        self?.beginRecording()
                    } else {
                        self?.errorMessage = "Microphone access is required to attach a repair memo."
                    }
                }
            }
        default:
            permissionGranted = false
            errorMessage = "Microphone access is disabled for Audora."
        }
    }

    @discardableResult
    func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        isRecording = false
        return lastRecordedURL
    }

    private func beginRecording() {
        do {
            let destination = WritingAwarenessStorageManager.shared.nextMemoURL()
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            recorder = try AVAudioRecorder(url: destination, settings: settings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = false
            recorder?.record()
            lastRecordedURL = destination
            isRecording = true
            permissionGranted = true
        } catch {
            errorMessage = "Failed to start the memo recorder: \(error.localizedDescription)"
            recorder = nil
            isRecording = false
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isRecording = false
            if !flag {
                self?.errorMessage = "The voice memo did not finish recording successfully."
            }
        }
    }
}
