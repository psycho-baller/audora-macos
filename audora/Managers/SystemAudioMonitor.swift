import Foundation
import CoreAudio
import os.log

/// Monitors system audio output to detect when other apps are using audio
/// Does NOT capture audio - only observes the system audio state
@MainActor
class SystemAudioMonitor {
    private let logger = Logger(subsystem: "io.audora", category: "SystemAudioMonitor")
    
    enum AudioState {
        case active    // Other apps are using audio
        case inactive  // No apps using audio
    }
    
    private(set) var audioState: AudioState = .inactive
    private(set) var isMonitoring = false
    private var outputDeviceID: AudioObjectID = .invalid
    
    // Callback when audio state changes
    var onAudioStateChanged: ((AudioState) -> Void)?
    
    init() {}
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        guard !isMonitoring else {
            logger.info("Already monitoring")
            return
        }
        
        logger.info("🎧 Starting system audio monitoring...")
        
        // Get default output device
        guard let deviceID = AudioObjectID.readDefaultSystemOutputDevice() else {
            logger.error("Failed to get default audio output device")
            return
        }
        outputDeviceID = deviceID
        
        // Listen for device running state changes
        do {
            try addDeviceRunningListener()
            // Listen for default device changes (e.g., switching audio output)
            try addDefaultDeviceChangeListener()
        } catch {
            logger.error("Failed to add property listeners: \(error.localizedDescription)")
            return
        }
        
        isMonitoring = true
        
        // Check initial state
        updateAudioState()
        
        logger.info("✅ Monitoring started - will detect when other apps use audio")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        logger.info("🛑 Stopping system audio monitoring...")
        
        removeDeviceRunningListener()
        removeDefaultDeviceChangeListener()
        
        isMonitoring = false
        audioState = .inactive
        
        logger.info("✅ Monitoring stopped")
    }
    
    // MARK: - Private Methods
    
    func updateAudioState() {
        let newState: AudioState = isDeviceRunning() ? .active : .inactive
        
        if newState != audioState {
            audioState = newState
            logger.info("System audio state changed: \(String(describing: newState))")
            onAudioStateChanged?(newState)
        }
    }
    
    private func isDeviceRunning() -> Bool {
        guard outputDeviceID.isValid else { return false }
        
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            outputDeviceID,
            &address,
            0,
            nil,
            &size,
            &running
        )
        
        return status == noErr && running != 0
    }
    
    // MARK: - Property Listeners
    
    private func addDeviceRunningListener() throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectAddPropertyListener(
            outputDeviceID,
            &address,
            deviceRunningListenerProc,
            Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
    
    private func removeDeviceRunningListener() {
        guard outputDeviceID.isValid else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListener(
            outputDeviceID,
            &address,
            deviceRunningListenerProc,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }
    
    private func addDefaultDeviceChangeListener() throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            defaultDeviceListenerProc,
            Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
    
    private func removeDefaultDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            defaultDeviceListenerProc,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }
    
    func handleDefaultDeviceChanged() {
        logger.info("Default audio device changed")
        
        // Remove old listener
        removeDeviceRunningListener()
        
        // Update device ID
        guard let deviceID = AudioObjectID.readDefaultSystemOutputDevice() else {
            logger.error("Failed to get default audio output device on device change")
            return
        }
        outputDeviceID = deviceID
        do {
            try addDeviceRunningListener()
            updateAudioState()
        } catch {
            logger.error("Failed to add device running listener: \(error.localizedDescription)")
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
    
    let monitor = Unmanaged<SystemAudioMonitor>.fromOpaque(clientData).takeUnretainedValue()
    
    Task { @MainActor in
        monitor.updateAudioState()
    }
    
    return noErr
}

private func defaultDeviceListenerProc(
    _ inObjectID: AudioObjectID,
    _ inNumberAddresses: UInt32,
    _ inAddresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData = inClientData else { return noErr }
    
    let monitor = Unmanaged<SystemAudioMonitor>.fromOpaque(clientData).takeUnretainedValue()
    
    Task { @MainActor in
        monitor.handleDefaultDeviceChanged()
    }
    
    return noErr
}

// MARK: - AudioObjectID Extension

extension AudioObjectID {
    static let invalid = AudioObjectID(kAudioObjectUnknown)
    
//    var isValid: Bool {
//        return self != .invalid
//    }
    
    static func readDefaultSystemOutputDevice() -> AudioObjectID? {
        var deviceID: AudioObjectID = .invalid
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        
        guard status == noErr else {
            return nil
        }
        
        return deviceID
    }
}

