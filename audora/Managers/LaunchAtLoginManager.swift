import Foundation
import ServiceManagement

class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private init() {}

    func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login: \(error)")
            }
        } else {
            // Fallback for older macOS versions (deprecated API)
            let success = SMLoginItemSetEnabled("io.audora.Audora-Helper" as CFString, enabled)
            if !success {
                 print("Failed to update launch at login (SMLoginItemSetEnabled)")
            }
        }
    }
}
