import AppKit
import SwiftUI

@MainActor
final class WritingLensWindowManager: NSObject {
    static let shared = WritingLensWindowManager()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<WritingLensView>?
    private var observers: [NSObjectProtocol] = []

    private override init() {
        super.init()
        setupPanel()
        installObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func show(captureSelection: Bool = true) {
        if captureSelection {
            WritingAwarenessManager.shared.captureSelectionIntoLens()
        }
        refreshContent()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showWithClipboard() {
        WritingAwarenessManager.shared.loadClipboardIntoLens()
        show(captureSelection: false)
    }

    private func setupPanel() {
        let rect = NSRect(x: 0, y: 0, width: 620, height: 780)
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "Writing Lens"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.setFrameAutosaveName("WritingLensPanel")
        self.panel = panel
        refreshContent()
    }

    private func refreshContent() {
        guard let panel else { return }
        if hostingController == nil {
            hostingController = NSHostingController(rootView: WritingLensView())
        } else {
            hostingController?.rootView = WritingLensView()
        }
        panel.contentView = hostingController?.view
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: .openWritingLens, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.show(captureSelection: true)
                }
            }
        )
    }
}
