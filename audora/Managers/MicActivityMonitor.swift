import Foundation
import CoreAudio
import Combine

/// Monitors all input devices to see if any are "running somewhere".
final class MicActivityMonitor: ObservableObject {
    @Published private(set) var isMicActive: Bool = false

    private var monitoredDeviceIDs: Set<AudioObjectID> = []

    // We need to keep the listener block alive and consistent for removal
    private let listenerBlock: AudioObjectPropertyListenerBlock = { deviceID, _ in
        // We can't access 'self' easily here without a global map or notification.
        // So we post a notification that the specific device changed.
        NotificationCenter.default.post(name: .deviceRunningStateChanged, object: nil)
    }

    init() {
        setupMonitoring()

        // Listen for internal notifications from the C-callback
        NotificationCenter.default.addObserver(forName: .deviceRunningStateChanged, object: nil, queue: .main) { [weak self] _ in
            self?.checkAllDevices()
        }
    }

    deinit {
        removeAllListeners()
    }

    private func setupMonitoring() {
        removeAllListeners()

        do {
            // Get all input devices
            let inputDevices = try AudioObjectID.getAllInputDevices()
            print("🎤 MicActivityMonitor: Found \(inputDevices.count) input devices")

            for device in inputDevices {
                let deviceID = device.id
                monitoredDeviceIDs.insert(deviceID)

                // Add listener for this device
                Self.addRunningListener(deviceID: deviceID, listenerBlock: listenerBlock)

                // Log initial state
                let isRunning = Self.readIsRunning(deviceID: deviceID)
                print("   - Device \(device.name) (\(deviceID)): RunningSomewhere=\(isRunning)")
            }

            checkAllDevices()

        } catch {
            print("❌ MicActivityMonitor: Failed to setup monitoring: \(error)")
        }
    }

    private func removeAllListeners() {
        for deviceID in monitoredDeviceIDs {
            Self.removeRunningListener(deviceID: deviceID, listenerBlock: listenerBlock)
        }
        monitoredDeviceIDs.removeAll()
    }

    private func checkAllDevices() {
        var anyActive = false
        for deviceID in monitoredDeviceIDs {
            if Self.readIsRunning(deviceID: deviceID) {
                anyActive = true
                // print("🎤 Device \(deviceID) is active")
                break // Optimization: if one is active, the global state is active
            }
        }

        if isMicActive != anyActive {
            print("🎤 MicActivityMonitor: Global mic active state changed to: \(anyActive)")
            isMicActive = anyActive
        }
    }

    // MARK: - CoreAudio glue

    private static func readIsRunning(deviceID: AudioObjectID) -> Bool {
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: isRunning))

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &addr,
            0,
            nil,
            &size,
            &isRunning
        )

        if status != noErr {
            return false
        }
        return isRunning != 0
    }

    private static func addRunningListener(
        deviceID: AudioObjectID,
        listenerBlock: @escaping AudioObjectPropertyListenerBlock
    ) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectAddPropertyListenerBlock(deviceID, &addr, nil, listenerBlock)

        if status != noErr {
            print("❌ MicActivityMonitor: Failed to add listener for device \(deviceID): \(status)")
        }
    }

    private static func removeRunningListener(
        deviceID: AudioObjectID,
        listenerBlock: @escaping AudioObjectPropertyListenerBlock
    ) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(deviceID, &addr, nil, listenerBlock)
    }
}

extension Notification.Name {
    static let deviceRunningStateChanged = Notification.Name("deviceRunningStateChanged")
}
