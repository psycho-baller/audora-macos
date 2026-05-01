import AppKit
import SwiftUI

struct WritingAwareTextConfiguration {
    var surfaceID: String
    var placeholder: String
    var contextLabel: String
    var font: NSFont
    var singleLine: Bool
    var minHeight: CGFloat
    var backgroundColor: NSColor
    var borderColor: NSColor
    var cornerRadius: CGFloat
    var textInsets: NSSize
}

struct WritingAwareTextField: NSViewRepresentable {
    @Binding var text: String

    let surfaceID: String
    var placeholder: String
    var contextLabel: String
    var font: NSFont
    var backgroundColor: NSColor
    var borderColor: NSColor
    var cornerRadius: CGFloat
    var textInsets: NSSize

    init(
        text: Binding<String>,
        surfaceID: String,
        placeholder: String = "",
        contextLabel: String = "Audora",
        font: NSFont = .systemFont(ofSize: 14, weight: .medium),
        backgroundColor: NSColor = .textBackgroundColor,
        borderColor: NSColor = NSColor.separatorColor.withAlphaComponent(0.18),
        cornerRadius: CGFloat = 8,
        textInsets: NSSize = NSSize(width: 8, height: 7)
    ) {
        _text = text
        self.surfaceID = surfaceID
        self.placeholder = placeholder
        self.contextLabel = contextLabel
        self.font = font
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.cornerRadius = cornerRadius
        self.textInsets = textInsets
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> WritingAwareTextContainerView {
        let configuration = WritingAwareTextConfiguration(
            surfaceID: surfaceID,
            placeholder: placeholder,
            contextLabel: contextLabel,
            font: font,
            singleLine: true,
            minHeight: max(36, font.pointSize + (textInsets.height * 2) + 8),
            backgroundColor: backgroundColor,
            borderColor: borderColor,
            cornerRadius: cornerRadius,
            textInsets: textInsets
        )
        let view = WritingAwareTextContainerView(configuration: configuration)
        context.coordinator.attach(to: view, configuration: configuration)
        view.setText(text)
        return view
    }

    func updateNSView(_ nsView: WritingAwareTextContainerView, context: Context) {
        let configuration = WritingAwareTextConfiguration(
            surfaceID: surfaceID,
            placeholder: placeholder,
            contextLabel: contextLabel,
            font: font,
            singleLine: true,
            minHeight: max(36, font.pointSize + (textInsets.height * 2) + 8),
            backgroundColor: backgroundColor,
            borderColor: borderColor,
            cornerRadius: cornerRadius,
            textInsets: textInsets
        )
        context.coordinator.updateBinding($text)
        context.coordinator.attach(to: nsView, configuration: configuration)
        nsView.apply(configuration: configuration)
        nsView.setText(text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>
        private weak var containerView: WritingAwareTextContainerView?
        private var configuration: WritingAwareTextConfiguration?

        init(text: Binding<String>) {
            self.text = text
        }

        func updateBinding(_ binding: Binding<String>) {
            text = binding
        }

        func attach(to view: WritingAwareTextContainerView, configuration: WritingAwareTextConfiguration) {
            containerView = view
            self.configuration = configuration
            view.textView.delegate = self
            view.onIssueInteraction = { [weak self] span, anchorRect in
                self?.showPopover(for: span, anchorRect: anchorRect)
            }
            scheduleAnalysis(for: view.textView.string)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let value = textView.string
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
            scheduleAnalysis(for: value)
        }

        private func scheduleAnalysis(for value: String) {
            guard let configuration, let containerView else { return }
            let snapshot = WritingSurfaceSnapshot(
                surfaceID: configuration.surfaceID,
                text: value,
                sourceApp: "Audora",
                contextLabel: configuration.contextLabel,
                origin: .audora,
                selectionRange: containerView.textView.selectedRange()
            )

            WritingSurfaceDebounceCoordinator.shared.schedule(
                surfaceID: configuration.surfaceID,
                fingerprint: "\(configuration.surfaceID)|\(value)"
            ) { [weak containerView] in
                let payload = WritingAwarenessManager.shared.analyzeSurface(snapshot)
                containerView?.apply(payload: payload)
            }
        }

        private func showPopover(for span: WritingIssueSpan, anchorRect: CGRect) {
            guard let containerView, let configuration else { return }
            let request = WritingIssuePopoverRequest(
                sourceApp: "Audora",
                contextLabel: configuration.contextLabel,
                span: span,
                onReplace: span.kind == .avoid ? { [weak self] replacement in
                    self?.applyReplacement(span: span, replacement: replacement)
                } : nil,
                onOpenLens: { [weak self] in
                    self?.openLens()
                }
            )
            guard let screenRect = containerView.textView.screenRect(for: anchorRect) else { return }
            WritingIssuePopoverWindowManager.shared.show(request: request, anchorRect: screenRect)
        }

        private func applyReplacement(span: WritingIssueSpan, replacement: String) {
            guard let containerView else { return }
            let updated = WritingAwarenessManager.shared.applySuggestion(
                to: containerView.textView.string,
                span: span,
                replacement: replacement
            )
            text.wrappedValue = updated
            containerView.setText(updated)
            containerView.textView.setSelectedRange(
                NSRange(location: span.rangeLower + replacement.count, length: 0)
            )
            scheduleAnalysis(for: updated)
        }

        private func openLens() {
            guard let configuration, let containerView else { return }
            WritingAwarenessManager.shared.applyCapture(
                SelectionCaptureResult(
                    text: containerView.textView.string,
                    selectedText: nil,
                    sourceApp: "Audora",
                    sourceBundleIdentifier: Bundle.main.bundleIdentifier,
                    contextLabel: configuration.contextLabel,
                    usedClipboardFallback: false,
                    selectionRange: containerView.textView.selectedRange(),
                    elementFrame: nil,
                    selectionBounds: nil,
                    capability: .replaceable,
                    isSecureInput: false
                ),
                recordFeedback: false
            )
            Task { @MainActor in
                WritingLensWindowManager.shared.show(captureSelection: false)
            }
        }
    }
}

struct WritingAwareTextView: NSViewRepresentable {
    @Binding var text: String

    let surfaceID: String
    var placeholder: String
    var contextLabel: String
    var font: NSFont
    var minHeight: CGFloat
    var backgroundColor: NSColor
    var borderColor: NSColor
    var cornerRadius: CGFloat
    var textInsets: NSSize

    init(
        text: Binding<String>,
        surfaceID: String,
        placeholder: String = "",
        contextLabel: String = "Audora",
        font: NSFont = .systemFont(ofSize: 14, weight: .medium),
        minHeight: CGFloat = 100,
        backgroundColor: NSColor = .textBackgroundColor,
        borderColor: NSColor = NSColor.separatorColor.withAlphaComponent(0.18),
        cornerRadius: CGFloat = 8,
        textInsets: NSSize = NSSize(width: 8, height: 8)
    ) {
        _text = text
        self.surfaceID = surfaceID
        self.placeholder = placeholder
        self.contextLabel = contextLabel
        self.font = font
        self.minHeight = minHeight
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.cornerRadius = cornerRadius
        self.textInsets = textInsets
    }

    func makeCoordinator() -> WritingAwareTextField.Coordinator {
        WritingAwareTextField.Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> WritingAwareTextContainerView {
        let configuration = WritingAwareTextConfiguration(
            surfaceID: surfaceID,
            placeholder: placeholder,
            contextLabel: contextLabel,
            font: font,
            singleLine: false,
            minHeight: minHeight,
            backgroundColor: backgroundColor,
            borderColor: borderColor,
            cornerRadius: cornerRadius,
            textInsets: textInsets
        )
        let view = WritingAwareTextContainerView(configuration: configuration)
        context.coordinator.attach(to: view, configuration: configuration)
        view.setText(text)
        return view
    }

    func updateNSView(_ nsView: WritingAwareTextContainerView, context: Context) {
        let configuration = WritingAwareTextConfiguration(
            surfaceID: surfaceID,
            placeholder: placeholder,
            contextLabel: contextLabel,
            font: font,
            singleLine: false,
            minHeight: minHeight,
            backgroundColor: backgroundColor,
            borderColor: borderColor,
            cornerRadius: cornerRadius,
            textInsets: textInsets
        )
        context.coordinator.updateBinding($text)
        context.coordinator.attach(to: nsView, configuration: configuration)
        nsView.apply(configuration: configuration)
        nsView.setText(text)
    }
}

final class WritingAwareTextContainerView: NSView {
    let scrollView = NSScrollView()
    let textView = WritingAwareTextViewImpl(frame: .zero, textContainer: nil)

    var onIssueInteraction: ((WritingIssueSpan, CGRect) -> Void)?

    private var configuration: WritingAwareTextConfiguration

    init(configuration: WritingAwareTextConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = !configuration.singleLine
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.configure(with: configuration)
        textView.onIssueInteraction = { [weak self] span, rect in
            self?.onIssueInteraction?(span, rect)
        }
        scrollView.documentView = textView

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: configuration.minHeight)
        ])

        apply(configuration: configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: configuration.minHeight)
    }

    func apply(configuration: WritingAwareTextConfiguration) {
        self.configuration = configuration
        wantsLayer = true
        layer?.backgroundColor = configuration.backgroundColor.cgColor
        layer?.cornerRadius = configuration.cornerRadius
        layer?.borderWidth = 1
        layer?.borderColor = configuration.borderColor.cgColor
        textView.configure(with: configuration)
        scrollView.hasVerticalScroller = !configuration.singleLine
        invalidateIntrinsicContentSize()
    }

    func setText(_ value: String) {
        textView.setStringIfNeeded(value)
    }

    func apply(payload: WritingUnderlinePayload?) {
        textView.apply(payload: payload)
    }
}

final class WritingAwareTextViewImpl: NSTextView {
    var onIssueInteraction: ((WritingIssueSpan, CGRect) -> Void)?

    private var placeholder = ""
    private var singleLine = false
    private var trackingAreaRef: NSTrackingArea?
    private var hoverSpanID: String?
    private var hoverWorkItem: DispatchWorkItem?
    private var activePayload: WritingUnderlinePayload?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = container ?? NSTextContainer(
            size: NSSize(width: frameRect.width, height: CGFloat.greatestFiniteMagnitude)
        )
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        super.init(frame: frameRect, textContainer: textContainer)
        isRichText = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        allowsUndo = true
        drawsBackground = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        textContainerInset = NSSize(width: 8, height: 8)
        self.textContainer?.widthTracksTextView = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(with configuration: WritingAwareTextConfiguration) {
        guard let textContainer else { return }
        placeholder = configuration.placeholder
        singleLine = configuration.singleLine
        font = configuration.font
        textColor = .labelColor
        insertionPointColor = .labelColor
        textContainerInset = configuration.textInsets
        textContainer.lineBreakMode = configuration.singleLine ? .byClipping : .byWordWrapping
        textContainer.containerSize = configuration.singleLine
            ? NSSize(width: CGFloat.greatestFiniteMagnitude, height: configuration.minHeight)
            : NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        textContainer.widthTracksTextView = !configuration.singleLine
        isHorizontallyResizable = configuration.singleLine
        isVerticallyResizable = !configuration.singleLine
        maxSize = configuration.singleLine
            ? NSSize(width: CGFloat.greatestFiniteMagnitude, height: configuration.minHeight)
            : NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    func setStringIfNeeded(_ value: String) {
        guard string != value else { return }
        let selection = selectedRange()
        string = value
        setSelectedRange(NSRange(location: min(selection.location, (value as NSString).length), length: 0))
        apply(payload: activePayload)
    }

    func apply(payload: WritingUnderlinePayload?) {
        activePayload = payload
        guard let textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.removeAttribute(.underlineStyle, range: fullRange)
        textStorage.removeAttribute(.underlineColor, range: fullRange)
        textStorage.removeAttribute(.backgroundColor, range: fullRange)

        payload?.spans.forEach { span in
            let range = span.sourceRange
            guard range.location != NSNotFound, NSMaxRange(range) <= textStorage.length else { return }
            switch span.kind {
            case .avoid:
                textStorage.addAttributes([
                    .underlineStyle: NSUnderlineStyle.patternDash.rawValue | NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor.systemOrange
                ], range: range)
            case .reward:
                textStorage.addAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor.systemGreen
                ], range: range)
            }
        }
        textStorage.endEditing()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        ]
        let rect = NSRect(
            x: textContainerInset.width + 2,
            y: textContainerInset.height + 1,
            width: bounds.width - (textContainerInset.width * 2),
            height: bounds.height - (textContainerInset.height * 2)
        )
        placeholder.draw(in: rect, withAttributes: attributes)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func keyDown(with event: NSEvent) {
        if singleLine && event.keyCode == 36 {
            window?.makeFirstResponder(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let span = span(at: convert(event.locationInWindow, from: nil)) else {
            hoverSpanID = nil
            hoverWorkItem?.cancel()
            NSCursor.arrow.set()
            return
        }

        NSCursor.pointingHand.set()
        guard hoverSpanID != span.id else { return }
        hoverSpanID = span.id
        hoverWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.presentPopover(for: span)
        }
        hoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if let span = span(at: convert(event.locationInWindow, from: nil)) {
            presentPopover(for: span)
        }
    }

    func screenRect(for localRect: CGRect) -> CGRect? {
        guard let window else { return nil }
        return window.convertToScreen(convert(localRect, to: nil))
    }

    private func presentPopover(for span: WritingIssueSpan) {
        guard let anchorRect = rect(for: span) else { return }
        onIssueInteraction?(span, anchorRect)
    }

    private func span(at point: CGPoint) -> WritingIssueSpan? {
        guard let layoutManager, let textContainer else { return nil }
        let glyphIndex = layoutManager.glyphIndex(
            for: CGPoint(
                x: point.x - textContainerInset.width,
                y: point.y - textContainerInset.height
            ),
            in: textContainer
        )
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        return activePayload?.spans.first(where: { span in
            characterIndex >= span.rangeLower && characterIndex < span.rangeUpper
        })
    }

    private func rect(for span: WritingIssueSpan) -> CGRect? {
        guard let layoutManager, let textContainer else { return nil }
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: span.sourceRange,
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height
        rect.size.height = max(rect.size.height, 18)
        return rect
    }
}
