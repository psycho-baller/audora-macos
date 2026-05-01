import AppKit
import ApplicationServices
import Foundation

@MainActor
final class SelectionCaptureManager {
    static let shared = SelectionCaptureManager()

    private struct FocusedElementContext {
        var sourceApp: String
        var sourceBundleIdentifier: String?
        var contextLabel: String
        var element: AXUIElement
    }

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    private init() {}

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func captureSelection(allowClipboardFallback: Bool) -> SelectionCaptureResult? {
        if let snapshot = captureFocusedTextSnapshot(),
           let selectedText = snapshot.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedText.isEmpty {
            return SelectionCaptureResult(
                text: selectedText,
                selectedText: selectedText,
                sourceApp: snapshot.sourceApp,
                sourceBundleIdentifier: snapshot.sourceBundleIdentifier,
                contextLabel: snapshot.contextLabel,
                usedClipboardFallback: false,
                selectionRange: snapshot.selectionRange,
                elementFrame: snapshot.elementFrame,
                selectionBounds: snapshot.selectionBounds,
                capability: snapshot.capability,
                isSecureInput: snapshot.isSecureInput
            )
        }

        guard allowClipboardFallback,
              let clipboardText = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboardText.isEmpty else {
            return nil
        }

        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown App"
        return SelectionCaptureResult(
            text: clipboardText,
            selectedText: clipboardText,
            sourceApp: sourceApp,
            sourceBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            contextLabel: BrowserURLHelper.getCurrentContext() ?? sourceApp,
            usedClipboardFallback: true,
            selectionRange: nil,
            elementFrame: nil,
            selectionBounds: nil,
            capability: .readable,
            isSecureInput: false
        )
    }

    func captureFocusedTextSnapshot(maxLength: Int = 8_000) -> SelectionCaptureResult? {
        guard isTrusted else { return nil }
        guard let context = currentFocusedElementContext() else { return nil }
        let focusedElement = context.element

        let isSecureInput = isSecureTextInput(element: focusedElement)
        let fullValue = copyStringAttribute(from: focusedElement, attribute: kAXValueAttribute as CFString)
        let selectedText = copySelectedText(from: focusedElement)
        let selectionRange = copySelectedRange(from: focusedElement)
        let elementFrame = copyFrame(from: focusedElement)
        let selectionBounds = copyBounds(for: focusedElement, range: selectionRange)
        let boundsProbeRange = preferredBoundsProbeRange(fullValue: fullValue, selectionRange: selectionRange)
        let probeBounds = boundsProbeRange.flatMap { copyBounds(for: focusedElement, range: $0) }
        let capability = focusedElementCapability(
            for: focusedElement,
            fullValue: fullValue,
            selectedText: selectedText,
            selectionRange: selectionRange,
            elementFrame: elementFrame,
            selectionBounds: selectionBounds,
            probeBounds: probeBounds
        )

        let text: String
        if let fullValue, !fullValue.isEmpty {
            text = String(fullValue.prefix(maxLength))
        } else if let selectedText, !selectedText.isEmpty {
            text = String(selectedText.prefix(maxLength))
        } else {
            return nil
        }

        return SelectionCaptureResult(
            text: text,
            selectedText: selectedText,
            sourceApp: context.sourceApp,
            sourceBundleIdentifier: context.sourceBundleIdentifier,
            contextLabel: context.contextLabel,
            usedClipboardFallback: false,
            selectionRange: selectionRange,
            elementFrame: elementFrame,
            selectionBounds: selectionBounds,
            capability: capability,
            isSecureInput: isSecureInput
        )
    }

    func replaceFocusedSelection(with replacement: String) -> Bool {
        guard isTrusted else { return false }
        guard let context = currentFocusedElementContext() else {
            return false
        }
        let focusedElement = context.element

        if let fullValue = copyStringAttribute(from: focusedElement, attribute: kAXValueAttribute as CFString),
           let selectionRange = copySelectedRange(from: focusedElement),
           selectionRange.location != NSNotFound,
           selectionRange.length > 0,
           NSMaxRange(selectionRange) <= (fullValue as NSString).length,
           isAttributeSettable(on: focusedElement, attribute: kAXValueAttribute as CFString) {
            let updatedValue = (fullValue as NSString).replacingCharacters(in: selectionRange, with: replacement)
            let setValueResult = AXUIElementSetAttributeValue(
                focusedElement,
                kAXValueAttribute as CFString,
                updatedValue as CFTypeRef
            )
            guard setValueResult == .success else { return false }
            _ = setSelectedRange(
                on: focusedElement,
                location: selectionRange.location + (replacement as NSString).length,
                length: 0
            )
            return true
        }

        guard isAttributeSettable(on: focusedElement, attribute: kAXSelectedTextAttribute as CFString) else {
            return false
        }

        let setSelectionResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            replacement as CFTypeRef
        )
        return setSelectionResult == .success
    }

    func selectFocusedRange(_ range: NSRange) -> Bool {
        guard isTrusted else { return false }
        guard let context = currentFocusedElementContext() else {
            return false
        }
        return setSelectedRange(on: context.element, location: range.location, length: range.length)
    }

    func replaceFocusedRange(_ range: NSRange, with replacement: String) -> Bool {
        guard isTrusted else { return false }
        guard let context = currentFocusedElementContext() else {
            return false
        }
        let focusedElement = context.element

        if let fullValue = copyStringAttribute(from: focusedElement, attribute: kAXValueAttribute as CFString),
           range.location != NSNotFound,
           range.length >= 0,
           NSMaxRange(range) <= (fullValue as NSString).length,
           isAttributeSettable(on: focusedElement, attribute: kAXValueAttribute as CFString) {
            let updatedValue = (fullValue as NSString).replacingCharacters(in: range, with: replacement)
            let setValueResult = AXUIElementSetAttributeValue(
                focusedElement,
                kAXValueAttribute as CFString,
                updatedValue as CFTypeRef
            )
            guard setValueResult == .success else { return false }
            _ = setSelectedRange(on: focusedElement, location: range.location + (replacement as NSString).length, length: 0)
            return true
        }

        guard selectFocusedRange(range) else {
            return false
        }
        return replaceFocusedSelection(with: replacement)
    }

    func boundsForFocusedRange(_ range: NSRange) -> CGRect? {
        guard isTrusted else { return nil }
        guard let context = currentFocusedElementContext() else {
            return nil
        }
        return copyBounds(for: context.element, range: range)
    }

    func boundsForFocusedRanges(_ ranges: [NSRange]) -> [FocusedTextRangeBounds] {
        guard isTrusted else { return [] }
        guard let context = currentFocusedElementContext() else {
            return []
        }

        return ranges.compactMap { range in
            guard let rect = copyBounds(for: context.element, range: range) else {
                return nil
            }
            return FocusedTextRangeBounds(
                rangeLower: range.location,
                rangeUpper: range.location + range.length,
                rect: rect
            )
        }
    }

    func isFocusedFieldSecure() -> Bool {
        guard isTrusted else { return false }
        guard let context = currentFocusedElementContext() else {
            return false
        }
        return isSecureTextInput(element: context.element)
    }

    func debugFocusedElementDiagnostics() -> String {
        guard isTrusted else {
            return "Accessibility trust: false"
        }

        guard let context = currentFocusedElementContext() else {
            return """
            Accessibility trust: true
            Focused element: unavailable
            """
        }

        let element = context.element
        let fullValue = copyStringAttribute(from: element, attribute: kAXValueAttribute as CFString) ?? ""
        let selectedText = copyStringAttribute(from: element, attribute: kAXSelectedTextAttribute as CFString) ?? ""
        let selectionRange = copySelectedRange(from: element)
        let elementFrame = copyFrame(from: element)
        let selectionBounds = copyBounds(for: element, range: selectionRange)
        let boundsProbeRange = preferredBoundsProbeRange(fullValue: fullValue, selectionRange: selectionRange)
        let probeBounds = boundsProbeRange.flatMap { copyBounds(for: element, range: $0) }
        let capability = focusedElementCapability(
            for: element,
            fullValue: fullValue,
            selectedText: selectedText,
            selectionRange: selectionRange,
            elementFrame: elementFrame,
            selectionBounds: selectionBounds,
            probeBounds: probeBounds
        )

        let preview = String(fullValue.prefix(160)).replacingOccurrences(of: "\n", with: "\\n")
        return """
        Accessibility trust: true
        Source app: \(context.sourceApp)
        Bundle ID: \(context.sourceBundleIdentifier ?? "unknown")
        Context label: \(context.contextLabel)
        AX role: \(copyStringAttribute(from: element, attribute: kAXRoleAttribute as CFString) ?? "nil")
        AX subrole: \(copyStringAttribute(from: element, attribute: kAXSubroleAttribute as CFString) ?? "nil")
        AX role description: \(copyStringAttribute(from: element, attribute: kAXRoleDescriptionAttribute as CFString) ?? "nil")
        Secure input: \(isSecureTextInput(element: element))
        Full value length: \(fullValue.count)
        Selected text length: \(selectedText.count)
        Selection range: \(selectionRange.map { "\($0.location):\($0.length)" } ?? "nil")
        Element frame: \(elementFrame.map(Self.debugRectString) ?? "nil")
        Selection bounds: \(selectionBounds.map(Self.debugRectString) ?? "nil")
        Bounds probe range: \(boundsProbeRange.map { "\($0.location):\($0.length)" } ?? "nil")
        Probe bounds: \(probeBounds.map(Self.debugRectString) ?? "nil")
        Capability: read=\(capability.canReadText) selection=\(capability.canReadSelection) replace=\(capability.canReplaceSelection) bounds=\(capability.canLocateBounds)
        Text preview: \(preview)
        """
    }

    private func currentFocusedElementContext() -> FocusedElementContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let sourceApp = app.localizedName ?? "Unknown App"
        let contextLabel = BrowserURLHelper.getCurrentContext() ?? sourceApp
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)

        guard let focusedElement = copyFocusedElement(from: applicationElement) else {
            return nil
        }

        return FocusedElementContext(
            sourceApp: sourceApp,
            sourceBundleIdentifier: app.bundleIdentifier,
            contextLabel: contextLabel,
            element: focusedElement
        )
    }

    private func copyFocusedElement(from applicationElement: AXUIElement) -> AXUIElement? {
        var focusedValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard result == .success, let focusedValue else { return nil }
        return unsafeBitCast(focusedValue, to: AXUIElement.self)
    }

    private func copySelectedText(from element: AXUIElement) -> String? {
        if let directSelection = copyStringAttribute(
            from: element,
            attribute: kAXSelectedTextAttribute as CFString
        )?.trimmingCharacters(in: .whitespacesAndNewlines), !directSelection.isEmpty {
            return directSelection
        }

        guard let fullValue = copyStringAttribute(from: element, attribute: kAXValueAttribute as CFString),
              let selectedRange = copySelectedRange(from: element),
              selectedRange.location != NSNotFound,
              selectedRange.length > 0,
              NSMaxRange(selectedRange) <= (fullValue as NSString).length else {
            return nil
        }

        let nsValue = fullValue as NSString
        return nsValue.substring(with: selectedRange).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyStringAttribute(from element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func copySelectedRange(from element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )
        guard result == .success, let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        let typedValue = unsafeBitCast(axValue, to: AXValue.self)
        guard AXValueGetType(typedValue) == .cfRange else { return nil }

        var range = CFRange()
        guard AXValueGetValue(typedValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func copyFrame(from element: AXUIElement) -> CGRect? {
        guard let position = copyPoint(from: element, attribute: kAXPositionAttribute as CFString),
              let size = copySize(from: element, attribute: kAXSizeAttribute as CFString) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func copyPoint(from element: AXUIElement, attribute: CFString) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }
        let typedValue = unsafeBitCast(axValue, to: AXValue.self)
        guard AXValueGetType(typedValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(typedValue, .cgPoint, &point) ? point : nil
    }

    private func copySize(from element: AXUIElement, attribute: CFString) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }
        let typedValue = unsafeBitCast(axValue, to: AXValue.self)
        guard AXValueGetType(typedValue) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(typedValue, .cgSize, &size) ? size : nil
    }

    private func copyBounds(for element: AXUIElement, range: NSRange?) -> CGRect? {
        guard let range else { return nil }
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return nil }

        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )

        guard result == .success, let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        let typedValue = unsafeBitCast(axValue, to: AXValue.self)
        guard AXValueGetType(typedValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(typedValue, .cgRect, &rect) ? rect : nil
    }

    private func isSecureTextInput(element: AXUIElement) -> Bool {
        let secureValues = [
            copyStringAttribute(from: element, attribute: kAXSubroleAttribute as CFString)?.lowercased(),
            copyStringAttribute(from: element, attribute: kAXRoleDescriptionAttribute as CFString)?.lowercased(),
            copyStringAttribute(from: element, attribute: kAXDescriptionAttribute as CFString)?.lowercased()
        ]

        return secureValues.contains { value in
            guard let value else { return false }
            return value.contains("secure") || value.contains("password")
        }
    }

    private static func debugRectString(_ rect: CGRect) -> String {
        let origin = "\(Int(rect.origin.x)),\(Int(rect.origin.y))"
        let size = "\(Int(rect.size.width))x\(Int(rect.size.height))"
        return "\(origin) \(size)"
    }

    private func focusedElementCapability(
        for element: AXUIElement,
        fullValue: String?,
        selectedText: String?,
        selectionRange: NSRange?,
        elementFrame: CGRect?,
        selectionBounds: CGRect?,
        probeBounds: CGRect?
    ) -> FocusedElementCapability {
        let hasReadableText = (fullValue?.isEmpty == false) || (selectedText?.isEmpty == false)
        let hasSelection = (selectedText?.isEmpty == false) || selectionRange != nil
        let canLocateBounds = isUsableBounds(probeBounds) || isUsableBounds(selectionBounds)
        let canReplaceSelection = hasReadableText &&
            (
                isAttributeSettable(on: element, attribute: kAXValueAttribute as CFString) ||
                isAttributeSettable(on: element, attribute: kAXSelectedTextAttribute as CFString)
            )

        return FocusedElementCapability(
            canReadText: hasReadableText,
            canReadSelection: hasSelection,
            canReplaceSelection: canReplaceSelection,
            canLocateBounds: canLocateBounds
        )
    }

    private func preferredBoundsProbeRange(fullValue: String?, selectionRange: NSRange?) -> NSRange? {
        let fullLength = (fullValue as NSString?)?.length ?? 0

        if let selectionRange, selectionRange.location != NSNotFound {
            if selectionRange.length > 0 {
                if fullLength == 0 || NSMaxRange(selectionRange) <= fullLength {
                    return NSRange(location: selectionRange.location, length: 1)
                }
            }

            if fullLength > 0 {
                let clampedLocation = min(max(selectionRange.location, 0), fullLength - 1)
                return NSRange(location: clampedLocation, length: 1)
            }
        }

        guard fullLength > 0 else { return nil }
        return NSRange(location: 0, length: 1)
    }

    private func isUsableBounds(_ rect: CGRect?) -> Bool {
        guard let rect else { return false }
        return !rect.isEmpty
    }

    private func isAttributeSettable(on element: AXUIElement, attribute: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, attribute, &settable)
        return result == .success && settable.boolValue
    }

    private func setSelectedRange(on element: AXUIElement, location: Int, length: Int) -> Bool {
        var range = CFRange(location: location, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            return false
        }
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )
        return result == .success
    }
}
