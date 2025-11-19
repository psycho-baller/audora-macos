# Menu Bar Features

## Overview

Audora provides a comprehensive menu bar interface that allows you to control the app's features without opening the main window. This follows standard macOS design patterns for application menus.

## Menu Structure

### File Menu

#### New Recording (⌘N)
Creates a new recording session immediately. The session title will automatically include the focused app or browser domain name along with the current date and time.

**Example:**
- If focused on Safari browsing `google.com`: "google.com - Nov 12, 12:39 AM"
- If focused on Zoom: "Zoom - Nov 12, 12:39 AM"

---

### Features Menu (New!)

This custom menu provides quick access to Audora's powerful recording features.

#### Auto-Recording (⌘⇧A)
**Toggle:** Enable or disable automatic recording when other apps use audio

When enabled:
- Audora monitors system audio activity
- Automatically starts recording when other apps (Zoom, Teams, etc.) use audio
- Stops recording when those apps stop using audio
- Saves sessions automatically with context-aware titles

**Use Cases:**
- Automatically capture video conference calls
- Record podcast interviews
- Capture game voice chat

**Status:** The checkmark (✓) indicates whether the feature is currently active.

---

#### Mic Following Mode (⌘⇧M)
**Toggle:** Enable or disable microphone usage tracking

When enabled:
- Monitors when other apps access your microphone
- Automatically starts recording when mic is in use
- Detects silence (3+ seconds) and stops recording
- Saves sessions with the focused app/domain name

**Use Cases:**
- Record dictation sessions
- Capture voice memos during work
- Auto-record voice commands

**Status:** The checkmark (✓) indicates whether the feature is currently active.

---

#### Open Settings... (⌘,)
Opens the settings panel where you can configure:
- OpenAI API key
- User blurb (context about yourself)
- System prompt customization
- Note templates
- Feature toggles with detailed explanations

---

### Help Menu

#### Check for Updates... (⌘U)
Checks if a new version of Audora is available via Sparkle updater.

#### Documentation
Opens the online documentation in your default browser.
Link: `https://audora.psycho-baller.com/docs`

#### Report an Issue
Opens the GitHub issues page where you can report bugs or request features.
Link: `https://github.com/psycho-baller/audora/issues`

#### Privacy Policy
Opens the privacy policy page.
Link: `https://audora.psycho-baller.com/privacy`

---

## Keyboard Shortcuts Reference

| Action | Shortcut |
|--------|----------|
| New Recording | ⌘N |
| Toggle Auto-Recording | ⌘⇧A |
| Toggle Mic Following | ⌘⇧M |
| Open Settings | ⌘, |
| Check for Updates | ⌘U |

---

## Technical Implementation

### Architecture

**Menu Bar Integration:**
- Implemented using SwiftUI's `.commands` modifier
- Uses `CommandMenu` for custom menu sections
- Uses `CommandGroup` for modifying existing menus
- Toggles bind directly to `SettingsViewModel`

**State Management:**
- Settings state shared via `@EnvironmentObject`
- Menu toggles update both UserDefaults and AudioManager state
- NotificationCenter coordinates actions between menu and main view

**File Structure:**
```
AudoraApp.swift          - Menu bar definitions
ContentView.swift        - NotificationCenter listeners
MeetingListView.swift    - Action handlers
SettingsViewModel.swift  - State management
```

### Adding New Menu Items

To add a new menu item:

1. **Define the command in `AudoraApp.swift`:**
```swift
CommandMenu("Your Menu") {
    Button("Your Action") {
        NotificationCenter.default.post(name: .init("YourNotification"), object: nil)
    }
    .keyboardShortcut("y", modifiers: .command)
}
```

2. **Add listener in `ContentView.swift`:**
```swift
.onReceive(NotificationCenter.default.publisher(for: .init("YourNotification"))) { _ in
    // Handle the action
}
```

3. **Implement action in target view:**
Handle the state change or perform the action as needed.

---

## User Experience Notes

### Feature Discovery
- All toggles show their current state with checkmarks (✓)
- Keyboard shortcuts are displayed next to menu items
- Tooltips provide additional context
- Settings page includes detailed feature explanations

### Consistency
- Follows macOS Human Interface Guidelines
- Uses standard keyboard shortcut patterns
- Menu items use sentence case
- Help items link to external resources

### Accessibility
- All menu items have keyboard shortcuts
- VoiceOver reads menu state correctly
- High contrast mode supported
- Reduced motion respected

---

## Future Enhancements

Potential menu bar additions:
- **Window** menu for multi-window support
- **Edit** menu for copy/paste in notes
- **View** menu for UI customization
- Recent recordings submenu
- Quick templates selector
- Status bar menu extra (system tray icon)
