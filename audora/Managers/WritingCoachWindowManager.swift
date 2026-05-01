import AppKit
import Combine
import SwiftUI

@MainActor
final class WritingCoachWindowManager: NSObject {
    static let shared = WritingCoachWindowManager()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<WritingCoachView>?
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        setupPanel()
        bind()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func setupPanel() {
        let rect = NSRect(x: 0, y: 0, width: 300, height: 220)
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        self.panel = panel
        refreshContent()
    }

    private func bind() {
        let manager = WritingAwarenessManager.shared
        Publishers.CombineLatest(manager.$liveCapture, manager.$liveResult)
            .receive(on: RunLoop.main)
            .sink { [weak self] capture, result in
                self?.updatePresentation(capture: capture, result: result)
            }
            .store(in: &cancellables)
    }

    private func updatePresentation(capture: SelectionCaptureResult?, result: WritingCheckResult?) {
        guard SystemWideWritingMonitor.shared.isRunning,
              UserDefaultsManager.shared.writingAwarenessEnabled,
              let capture,
              capture.sourceApp != "Audora",
              let result,
              !SystemWideUnderlineOverlayManager.shared.isShowingInlineUnderlines else {
            hide()
            return
        }

        let hasHits = !result.flaggedTerms.isEmpty || !result.rewardedTerms.isEmpty
        guard hasHits else {
            hide()
            return
        }

        refreshContent()
        positionPanel(using: capture.selectionBounds ?? capture.elementFrame)
        panel?.orderFrontRegardless()
    }

    private func refreshContent() {
        guard let panel else { return }
        if hostingController == nil {
            hostingController = NSHostingController(rootView: WritingCoachView())
        } else {
            hostingController?.rootView = WritingCoachView()
        }
        panel.contentView = hostingController?.view
    }

    private func positionPanel(using anchorRect: CGRect?) {
        guard let panel else { return }

        let size = panel.frame.size
        guard let anchorRect else {
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                panel.setFrameOrigin(
                    NSPoint(
                        x: frame.maxX - size.width - 24,
                        y: frame.maxY - size.height - 24
                    )
                )
            }
            return
        }

        let screen = NSScreen.screens.first { $0.frame.intersects(anchorRect) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let proposedX = min(anchorRect.maxX + 12, visibleFrame.maxX - size.width - 16)
        let proposedY = max(visibleFrame.minY + 16, min(anchorRect.minY - size.height - 12, visibleFrame.maxY - size.height - 16))

        panel.setFrameOrigin(NSPoint(x: proposedX, y: proposedY))
    }
}
