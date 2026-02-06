import CoreAudio
import Foundation
import os.log

/// Monitors when other apps are using the default input device (microphone)
/// Does NOT capture audio - only observes if the microphone is in use
@MainActor
final class MicUsageMonitor {
    private let logger = Logger(
        subsystem: "io.audora",
        category: "MicUsageMonitor"
    )

    enum MicState {
        case active  // Other apps are using the microphone
        case inactive  // No apps using the microphone
    }

    private(set) var micState: MicState = .inactive
    private(set) var isMonitoring = false
    private var defaultInputDeviceID = AudioDeviceID(0)

    // Callback when mic usage state changes
    var onMicStateChanged: ((MicState) -> Void)?

    init() {}

    // MARK: - Public Methods

    func startMonitoring() throws {
        guard !isMonitoring else {
            logger.info("Already monitoring mic usage")
            return
        }

        logger.info("🎤 Starting microphone usage monitoring...")

        // Get default input device
        updateDefaultInputDevice()

        guard defaultInputDeviceID != 0 else {
            throw NSError(
                domain: "MicUsageMonitor",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to get default input device"
                ]
            )
        }

        // Listen for device running state changes
        try addRunningListener()

        // Listen for default input device changes
        try addDefaultInputDeviceListener()

        isMonitoring = true

        // Check initial state
        updateMicState()

        logger.info(
            "✅ Mic monitoring started - will detect when other apps use microphone"
        )
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        logger.info("🛑 Stopping microphone usage monitoring...")

        removeRunningListener()
        removeDefaultInputDeviceListener()

        isMonitoring = false
        micState = .inactive

        logger.info("✅ Mic monitoring stopped")
    }
    
    /// Check if device is currently running without starting monitoring
    func currentIsRunningSomewhere() -> Bool {
        // Update to latest device if needed
        if defaultInputDeviceID == 0 {
            updateDefaultInputDevice()
        }
        let result = isDeviceRunning()
        logger.info("🔍 Device \(self.defaultInputDeviceID) running check: \(result)")
        return result
    }

    // MARK: - Private Methods

    private func updateDefaultInputDevice() {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout.size(ofValue: deviceID))
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size,
            &deviceID
        )

        if status == noErr {
            defaultInputDeviceID = deviceID
            logger.info("Default input device ID: \(deviceID)")
        } else {
            logger.error("Failed to get default input device: \(status)")
        }
    }

    func updateMicState() {
        let newState: MicState = isDeviceRunning() ? .active : .inactive

        if newState != micState {
            micState = newState
            logger.info(
                "Mic usage state changed: \(String(describing: newState))"
            )
            onMicStateChanged?(newState)
        }
    }

    private func isDeviceRunning() -> Bool {
        guard defaultInputDeviceID != 0 else { return false }

        var running: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: running))
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            defaultInputDeviceID,
            &addr,
            0,
            nil,
            &size,
            &running
        )

        return status == noErr && running != 0
    }

    // MARK: - Property Listeners

    private func addRunningListener() throws {
        guard defaultInputDeviceID != 0 else {
            throw NSError(
                domain: "MicUsageMonitor",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid input device ID"]
            )
        }

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectAddPropertyListener(
            defaultInputDeviceID,
            &addr,
            deviceRunningListenerProc,
            Unmanaged.passUnretained(self).toOpaque()
        )

        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func removeRunningListener() {
        guard defaultInputDeviceID != 0 else { return }

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListener(
            defaultInputDeviceID,
            &addr,
            deviceRunningListenerProc,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func addDefaultInputDeviceListener() throws {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            defaultInputDeviceListenerProc,
            Unmanaged.passUnretained(self).toOpaque()
        )

        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func removeDefaultInputDeviceListener() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            defaultInputDeviceListenerProc,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    func handleDefaultInputDeviceChanged() {
        logger.info("Default input device changed")

        // Remove old listener
        removeRunningListener()

        // Update device ID
        updateDefaultInputDevice()

        guard defaultInputDeviceID != 0 else {
            logger.error("Failed to get default input device on device change")
            return
        }

        do {
            try addRunningListener()
            updateMicState()
        } catch {
            logger.error(
                "Failed to add running listener after device change: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - C Callbacks

private func deviceRunningListenerProc(
    _ inObjectID: AudioObjectID,
    _ inNumberAddresses: UInt32,
    _ inAddresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData = inClientData else { return noErr }

    let monitor = Unmanaged<MicUsageMonitor>.fromOpaque(clientData)
        .takeUnretainedValue()

    Task { @MainActor in
        monitor.updateMicState()
    }

    return noErr
}

private func defaultInputDeviceListenerProc(
    _ inObjectID: AudioObjectID,
    _ inNumberAddresses: UInt32,
    _ inAddresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData = inClientData else { return noErr }

    let monitor = Unmanaged<MicUsageMonitor>.fromOpaque(clientData)
        .takeUnretainedValue()

    Task { @MainActor in
        monitor.handleDefaultInputDeviceChanged()
    }

    return noErr
}
