import AppKit
import SwiftUI

class MeetingReminderWindowController: NSObject {
    private var window: NSPanel?
    private var hostingController: NSHostingController<MeetingReminderView>?

    override init() {
        super.init()
        setupWindow()
    }

    private func setupWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 344, height: 100),
            styleMask: [.nonactivatingPanel, .fullSizeContentView], // Minimal style
            backing: .buffered,
            defer: false
        )

        panel.level = .floating // Keep on top
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // View has its own shadow
        panel.isMovableByWindowBackground = false

        self.window = panel
    }

    func show(appName: String, onRecord: @escaping () -> Void, onIgnore: @escaping () -> Void, onSettings: @escaping () -> Void) {
        guard let window = window else { return }

        let view = MeetingReminderView(
            appName: appName,
            onRecord: { [weak self] in
                onRecord()
                self?.hide()
            },
            onIgnore: { [weak self] in
                onIgnore()
                self?.hide()
            },
            onSettings: { [weak self] in
                onSettings()
                self?.hide()
            },
            onDismiss: { [weak self] in
                self?.hide()
            }
        )

        hostingController = NSHostingController(rootView: view)
        window.contentView = hostingController?.view

        // Position in top-right corner
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let windowSize = window.frame.size
            let padding: CGFloat = 20

            let x = screenRect.maxX - windowSize.width - padding
            let y = screenRect.maxY - windowSize.height - padding

            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.orderFront(nil)

        // Optional: Auto-hide after some time?
        // User didn't request it, but it's good practice.
        // For now, let's keep it persistent until action is taken or meeting ends.
    }

    func hide() {
        window?.orderOut(nil)
    }
}
