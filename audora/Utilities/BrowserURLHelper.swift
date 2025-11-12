import Foundation
import AppKit

/// Helper to retrieve the current URL from various web browsers
class BrowserURLHelper {
    
    /// Get the current browser URL or focused app name
    /// - Returns: Domain name from browser URL, or app name if not a browser
    static func getCurrentContext() -> String? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        let bundleIdentifier = frontmostApp.bundleIdentifier ?? ""
        let appName = frontmostApp.localizedName ?? "Unknown App"
        
        // Check if it's a supported browser and get URL
        if let url = getBrowserURL(bundleIdentifier: bundleIdentifier, appName: appName) {
            // Extract domain from URL
            if let domain = extractDomain(from: url) {
                return domain
            }
        }
        
        // If not a browser or URL retrieval failed, return app name
        return appName
    }
    
    /// Get the current URL from a browser using AppleScript
    private static func getBrowserURL(bundleIdentifier: String, appName: String) -> String? {
        let script: String?
        
        switch bundleIdentifier {
        case "com.apple.Safari":
            script = """
            tell application "Safari"
                if (count of windows) > 0 then
                    return URL of current tab of front window
                end if
            end tell
            """
            
        case "com.google.Chrome":
            script = """
            tell application "Google Chrome"
                if (count of windows) > 0 then
                    return URL of active tab of front window
                end if
            end tell
            """
            
        case "com.brave.Browser":
            script = """
            tell application "Brave Browser"
                if (count of windows) > 0 then
                    return URL of active tab of front window
                end if
            end tell
            """
            
        case "com.microsoft.edgemac":
            script = """
            tell application "Microsoft Edge"
                if (count of windows) > 0 then
                    return URL of active tab of front window
                end if
            end tell
            """
            
        case "company.thebrowser.Browser":
            script = """
            tell application "Arc"
                if (count of windows) > 0 then
                    return URL of active tab of front window
                end if
            end tell
            """
            
        case let id where id.contains("zen"):
            // Zen Browser - try multiple approaches as it's Firefox-based
            if let url = tryZenBrowserURL() {
                return url
            }
            return nil
        case "io.github.zen-browser.app", "zen.browser":
            // Zen Browser - try multiple approaches as it's Firefox-based
            if let url = tryZenBrowserURL() {
                return url
            }
            return nil
            
        default:
            // Check if app name contains supported browsers
            let lowerAppName = appName.lowercased()
            if lowerAppName.contains("firefox") {
                script = """
                tell application "Firefox"
                    if (count of windows) > 0 then
                        return URL of active tab of front window
                    end if
                end tell
                """
            } else if lowerAppName.contains("zen") {
                // Try Zen Browser
                if let url = tryZenBrowserURL() {
                    return url
                }
                return nil
            } else {
                return nil
            }
        }
        
        guard let appleScript = script else {
            return nil
        }
        
        return executeAppleScript(appleScript)
    }
    
    /// Try to get URL from Zen Browser using multiple methods
    private static func tryZenBrowserURL() -> String? {
        // Try 1: Standard Zen Browser name
        let script1 = """
        tell application "Zen Browser"
            if (count of windows) > 0 then
                return URL of active tab of front window
            end if
        end tell
        """
        
        if let url = executeAppleScript(script1) {
            return url
        }
        
        // Try 2: System Events approach for Zen Browser
        let script2 = """
        tell application "System Events"
            tell process "Zen Browser"
                if exists (window 1) then
                    set windowName to name of window 1
                    return windowName
                end if
            end tell
        end tell
        """
        
        // This will get the window title which often contains the URL or page title
        // Not ideal but better than nothing
        if let windowTitle = executeAppleScript(script2), !windowTitle.isEmpty {
            // If the window title looks like a URL, return it
            if windowTitle.contains("http") || windowTitle.contains(".com") || windowTitle.contains(".org") {
                return windowTitle
            }
        }
        
        return nil
    }
    
    /// Execute AppleScript and return the result
    private static func executeAppleScript(_ script: String) -> String? {
        var error: NSDictionary?
        
        guard let scriptObject = NSAppleScript(source: script) else {
            return nil
        }
        
        let output = scriptObject.executeAndReturnError(&error)
        
        if let error = error {
            // Only log non-permission errors to reduce noise
            let errorDesc = error.description
            if !errorDesc.contains("not allowed") && !errorDesc.contains("User canceled") {
                print("⚠️ AppleScript error: \(error)")
            }
            return nil
        }
        
        return output.stringValue
    }
    
    /// Extract domain from a URL string
    private static func extractDomain(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        guard let host = url.host else {
            return nil
        }
        
        // Remove "www." prefix if present
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        
        return domain
    }
}
