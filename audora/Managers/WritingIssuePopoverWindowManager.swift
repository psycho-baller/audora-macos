import AppKit
import SwiftUI

struct WritingIssuePopoverRequest {
    var sourceApp: String
    var contextLabel: String
    var span: WritingIssueSpan
    var onReplace: ((String) -> Void)?
    var onOpenLens: (() -> Void)?
}

@MainActor
final class WritingIssuePopoverWindowManager {
    static let shared = WritingIssuePopoverWindowManager()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<WritingIssuePopoverView>?
    private var activeRequest: WritingIssuePopoverRequest?

    private init() {
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
        panel.hidesOnDeactivate = false
        self.panel = panel
    }

    func show(request: WritingIssuePopoverRequest, anchorRect: CGRect) {
        activeRequest = request
        refreshContent()
        positionPanel(using: anchorRect)
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func refreshContent() {
        guard let panel, let activeRequest else { return }
        let view = WritingIssuePopoverView(
            request: activeRequest,
            onClose: { [weak self] in
                self?.hide()
            }
        )

        if hostingController == nil {
            hostingController = NSHostingController(rootView: view)
        } else {
            hostingController?.rootView = view
        }
        panel.contentView = hostingController?.view
    }

    private func positionPanel(using anchorRect: CGRect) {
        guard let panel else { return }
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.intersects(anchorRect) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let proposedX = min(anchorRect.midX - (size.width / 2), visibleFrame.maxX - size.width - 16)
        let clampedX = max(visibleFrame.minX + 16, proposedX)
        let proposedY = max(
            visibleFrame.minY + 16,
            min(anchorRect.minY - size.height - 12, visibleFrame.maxY - size.height - 16)
        )

        panel.setFrameOrigin(NSPoint(x: clampedX, y: proposedY))
    }
}

private struct WritingIssuePopoverView: View {
    let request: WritingIssuePopoverRequest
    let onClose: () -> Void

    private var eyebrow: String {
        request.span.kind == .avoid ? "Avoid" : "Reward"
    }

    private var title: String {
        request.span.kind == .avoid ? "\"\(request.span.term)\" needs a sharper substitute" : "\"\(request.span.term)\" is working"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.sourceApp)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(request.contextLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }

            Text(eyebrow)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)

            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))

            Text(request.span.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if !request.span.snippet.isEmpty {
                Text(request.span.snippet)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            if let onReplace = request.onReplace, !request.span.replacements.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(request.span.replacements.prefix(3), id: \.self) { replacement in
                        Button {
                            onReplace(replacement)
                            onClose()
                        } label: {
                            Text("Replace with \"\(replacement)\"")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }

            HStack {
                if let onOpenLens = request.onOpenLens {
                    Button("Open Lens") {
                        onOpenLens()
                        onClose()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button(request.span.kind == .avoid ? "Dismiss" : "Close") {
                    onClose()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
    }
}

