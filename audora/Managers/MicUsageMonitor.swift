import Foundation
import CoreAudio
import Combine
import AppKit
//import CoreAudioUtils

/// Monitors microphone usage by other applications
final class MicUsageMonitor: ObservableObject {
    @Published var appsUsingMic: Set<String> = [] // Set of Bundle IDs

    private var timer: Timer?
    private let checkInterval: TimeInterval = 2.0

    init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        stopMonitoring()

        // Initial check
        checkMicUsage()

        // Start periodic check
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkMicUsage()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkMicUsage() {
        print("🔍 Checking mic usage...")
        do {
            // Get list of all audio processes
            let processObjects = try AudioObjectID.readProcessList()
            print("✅ Found \(processObjects.count) audio processes")

            var activeBundleIDs: Set<String> = []

            for (index, processObject) in processObjects.enumerated() {
                // Check if process is running audio at all
                let isRunning = true // processObject.readProcessIsRunning()
                let isRunningInput = processObject.readProcessIsRunningInput()

                if isRunning {
                    let bundleID = processObject.readProcessBundleID() ?? "unknown"
                    // Try to get PID for name lookup
                    var name = bundleID
                    if let pid = try? processObject.read(processObject.kAudioProcessPropertyPID, defaultValue: Int32(0)) {
                        if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
                            name = app.localizedName ?? bundleID
                        }
                    }

                    print("🔹 Process \(index): \(name) (\(bundleID)) - Running: \(isRunning), Input: \(isRunningInput)")

                    if isRunningInput {
                        if let bundleID = processObject.readProcessBundleID() {
                            print("🎤 Found active mic user: \(bundleID)")
                            activeBundleIDs.insert(bundleID)
                        }
                    }
                }
            }

            print("🏁 Finished checking processes. Active: \(activeBundleIDs)")

            // Update published property if changed
            if activeBundleIDs != appsUsingMic {
                DispatchQueue.main.async {
                    print("🔄 Updating appsUsingMic: \(activeBundleIDs)")
                    self.appsUsingMic = activeBundleIDs
                }
            } else {
                print("ℹ️ No change in mic usage")
            }

        } catch {
            print("❌ Error checking mic usage: \(error)")
        }
    }
}
