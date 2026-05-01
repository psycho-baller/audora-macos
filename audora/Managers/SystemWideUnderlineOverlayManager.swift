import AppKit
import Combine
import SwiftUI

@MainActor
final class SystemWideUnderlineOverlayManager: ObservableObject {
    static let shared = SystemWideUnderlineOverlayManager()

    @Published private(set) var isShowingInlineUnderlines = false

    private var cancellables = Set<AnyCancellable>()
    private var windows: [String: NSPanel] = [:]

    private init() {
        bind()
    }

    func hideAll() {
        isShowingInlineUnderlines = false
        windows.values.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func bind() {
        let manager = WritingAwarenessManager.shared
        Publishers.CombineLatest(manager.$liveCapture, manager.$liveUnderlinePayload)
            .receive(on: RunLoop.main)
            .sink { [weak self] capture, payload in
                self?.updatePresentation(capture: capture, payload: payload)
            }
            .store(in: &cancellables)
    }

    private func updatePresentation(capture: SelectionCaptureResult?, payload: WritingUnderlinePayload?) {
        guard SystemWideWritingMonitor.shared.isRunning,
              UserDefaultsManager.shared.writingAwarenessEnabled,
              let capture,
              let payload,
              capture.sourceApp != "Audora",
              !capture.isSecureInput,
              capture.capability.canLocateBounds else {
            hideAll()
            return
        }

        let bounds = SelectionCaptureManager.shared.boundsForFocusedRanges(payload.spans.map(\.sourceRange))
        guard !bounds.isEmpty else {
            hideAll()
            return
        }

        let boundsByRange = Dictionary(uniqueKeysWithValues: bounds.map { ($0.sourceRange, $0.rect) })
        let visibleSpans = payload.spans.compactMap { span -> (WritingIssueSpan, CGRect)? in
            guard let rect = boundsByRange[span.sourceRange], rect.width > 0, rect.height > 0 else {
                return nil
            }
            return (span, rect)
        }

        guard !visibleSpans.isEmpty else {
            hideAll()
            return
        }

        let nextKeys = Set(visibleSpans.map { $0.0.id })
        for key in windows.keys where !nextKeys.contains(key) {
            windows[key]?.orderOut(nil)
            windows[key] = nil
        }

        for (span, rect) in visibleSpans {
            let window = windows[span.id] ?? makeWindow(for: span.id)
            update(window: window, span: span, rect: rect, capture: capture)
            window.orderFrontRegardless()
            windows[span.id] = window
        }

        isShowingInlineUnderlines = true
    }

    private func makeWindow(for identifier: String) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.identifier = NSUserInterfaceItemIdentifier(identifier)
        return panel
    }

    private func update(window: NSPanel, span: WritingIssueSpan, rect: CGRect, capture: SelectionCaptureResult) {
        let hitRect = CGRect(x: rect.minX, y: rect.minY - 2, width: max(rect.width, 12), height: max(rect.height, 16))
        window.setFrame(hitRect, display: true)

        let view = SystemWideUnderlineView(span: span) { [weak self] in
            self?.openPopover(for: span, rect: rect, capture: capture)
        }
        window.contentView = NSHostingView(rootView: view)
    }

    private func openPopover(for span: WritingIssueSpan, rect: CGRect, capture: SelectionCaptureResult) {
        let request = WritingIssuePopoverRequest(
            sourceApp: capture.sourceApp,
            contextLabel: capture.contextLabel,
            span: span,
            onReplace: span.kind == .avoid && capture.capability.canReplaceSelection ? { replacement in
                _ = WritingAwarenessManager.shared.replaceLiveSpan(span, with: replacement)
            } : nil,
            onOpenLens: {
                if let capture = WritingAwarenessManager.shared.liveCapture {
                    WritingAwarenessManager.shared.applyCapture(capture, recordFeedback: false)
                }
                WritingLensWindowManager.shared.show(captureSelection: false)
            }
        )
        WritingIssuePopoverWindowManager.shared.show(request: request, anchorRect: rect)
    }
}

private struct SystemWideUnderlineView: View {
    let span: WritingIssueSpan
    let onActivate: () -> Void

    private var color: Color {
        span.kind == .avoid ? Color(red: 0.69, green: 0.34, blue: 0.11) : Color(red: 0.1, green: 0.54, blue: 0.28)
    }

    var body: some View {
        Button(action: onActivate) {
            Rectangle()
                .fill(.clear)
                .overlay(alignment: .bottom) {
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(height: span.kind == .avoid ? 2 : 3)
                        .padding(.bottom, 2)
                }
        }
        .buttonStyle(.plain)
    }
}

