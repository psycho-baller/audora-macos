# Browser URL Helper

## Overview
The `BrowserURLHelper` utility automatically detects the current browser tab's domain name to create more contextual session titles.

## Supported Browsers
- **Safari** (`com.apple.Safari`)
- **Google Chrome** (`com.google.Chrome`)
- **Brave Browser** (`com.brave.Browser`)
- **Microsoft Edge** (`com.microsoft.edgemac`)
- **Arc Browser** (`company.thebrowser.Browser`)
- **Zen Browser** (Firefox-based, detected by bundle ID or app name)
- **Firefox** (detected by app name)

## How It Works

1. **Detect Active Browser**: Uses `NSWorkspace.shared.frontmostApplication` to identify the focused app
2. **Execute AppleScript**: Runs browser-specific AppleScript to get the current tab URL
3. **Extract Domain**: Parses the URL and extracts just the domain (e.g., `google.com`)
4. **Fallback**: If not a browser or URL unavailable, returns the app name

## Example Outputs

### Browser Tabs
```
google.com - Nov 12, 12:06 AM
github.com - Nov 12, 12:06 AM
youtube.com - Nov 12, 12:06 AM
stackoverflow.com - Nov 12, 12:06 AM
```

### Non-Browser Apps
```
Zoom - Nov 12, 12:06 AM
Slack - Nov 12, 12:06 AM
Microsoft Teams - Nov 12, 12:06 AM
```

## Permissions Required

### First-Time Setup
When the app first tries to get a browser URL, macOS will prompt:

> "Audora would like to control [Browser Name]"
> 
> [ ] Allow
> [ ] Don't Allow

The user must click **"Allow"** for each browser they want to support.

### Manual Permission Grant
If denied initially, users can grant permission in:
**System Settings → Privacy & Security → Automation → Audora**

## Error Handling

- **Permission Denied**: Falls back to app name only
- **No Browser Windows**: Falls back to app name
- **AppleScript Timeout**: Falls back to app name
- **Invalid URL**: Falls back to app name

## Performance

- **AppleScript Execution**: ~50-150ms per call
- **Cached per session**: Results are not cached; called once per recording session
- **Non-blocking**: Executed synchronously but only during session creation

## Privacy

- **Local Only**: All URL detection happens locally on the user's machine
- **No Data Collection**: URLs are never sent to external servers
- **User Control**: Users can deny automation permissions at any time

## Adding New Browsers

To add support for a new browser:

1. Get the bundle identifier: `osascript -e 'id of app "BrowserName"'`
2. Add a new case in `getBrowserURL()` with the appropriate AppleScript
3. Test the AppleScript in Script Editor first

### Example AppleScript Template
```applescript
tell application "BrowserName"
    if (count of windows) > 0 then
        return URL of active tab of front window
    end if
end tell
```
