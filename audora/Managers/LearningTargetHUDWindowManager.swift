import AppKit
import SwiftUI

struct LearningTargetHUDRequest {
    let titleOverride: String?
    let result: LearningTargetSaveResult
    let showUndo: Bool
    let onUndo: (() -> Void)?
    let onEdit: (() -> Void)?
}

@MainActor
final class LearningTargetHUDWindowManager: NSObject {
    static let shared = LearningTargetHUDWindowManager()

    private var panel: LearningTargetHUDPanel?
    private var hostingController: NSHostingController<LearningTargetHUDView>?
    private var dismissWorkItem: DispatchWorkItem?
    private var activeRequest: LearningTargetHUDRequest?
    private var observers: [NSObjectProtocol] = []

    private override init() {
        super.init()
        setupPanel()
        installObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func setupPanel() {
        let panel = LearningTargetHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 126),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        self.panel = panel
    }

    private func installObservers() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .showLearningTargetHUD,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let request = notification.object as? LearningTargetHUDRequest else { return }
                Task { @MainActor [weak self] in
                    self?.show(request)
                }
            }
        )
    }

    private func show(_ request: LearningTargetHUDRequest) {
        activeRequest = request
        refreshContent(with: request)
        positionPanel(using: request.result.anchorRect)
        panel?.alphaValue = 1
        panel?.orderFrontRegardless()
        scheduleDismiss()
    }

    private func refreshContent(with request: LearningTargetHUDRequest) {
        guard let panel else { return }
        let view = LearningTargetHUDView(
            request: request,
            onUndo: { [weak self] in
                self?.dismiss()
                request.onUndo?()
            },
            onEdit: { [weak self] in
                self?.dismiss()
                request.onEdit?()
            }
        )

        if hostingController == nil {
            hostingController = NSHostingController(rootView: view)
        } else {
            hostingController?.rootView = view
        }
        panel.contentView = hostingController?.view
    }

    private func scheduleDismiss() {
        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: workItem)
    }

    private func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
        activeRequest = nil
    }

    private func positionPanel(using anchorRect: CGRect?) {
        guard let panel else { return }

        let size = panel.frame.size
        let candidateAnchor = anchorRect ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(candidateAnchor.origin) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let x = min(
            max(candidateAnchor.midX - (size.width / 2), visibleFrame.minX + 16),
            visibleFrame.maxX - size.width - 16
        )

        let preferredAboveY = candidateAnchor.minY - size.height - 12
        let y: CGFloat
        if preferredAboveY >= visibleFrame.minY + 16 {
            y = preferredAboveY
        } else {
            y = min(candidateAnchor.maxY + 12, visibleFrame.maxY - size.height - 16)
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class LearningTargetHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct LearningTargetHUDView: View {
    let request: LearningTargetHUDRequest
    let onUndo: () -> Void
    let onEdit: () -> Void

    private var title: String {
        if let titleOverride = request.titleOverride {
            return titleOverride
        }

        switch request.result.status {
        case .saved:
            return "Saved to Learning Words"
        case .updated:
            return "Updated Learning Words"
        case .alreadyExists:
            return "Already Saved"
        case .invalid:
            return "Couldn't Save"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text(request.result.message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if request.showUndo || request.onEdit != nil {
                HStack(spacing: 8) {
                    if request.showUndo {
                        Button("Undo", action: onUndo)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    if request.onEdit != nil {
                        Button("Edit", action: onEdit)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}
