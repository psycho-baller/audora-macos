import AppKit
import Foundation

enum WritingSurfaceOrigin: String, Codable, Hashable {
    case audora
    case accessibility
    case browser
}

enum WritingIssueKind: String, Codable, Hashable {
    case avoid
    case reward
}

enum WritingAdapterKind: String, CaseIterable, Hashable, Identifiable {
    case audoraInline = "audora-inline"
    case browserInline = "browser-inline"
    case accessibilityInline = "accessibility-inline"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .audoraInline:
            return "Audora inline"
        case .browserInline:
            return "Browser inline"
        case .accessibilityInline:
            return "AX inline"
        }
    }
}

enum WritingAdapterStatus: String, Hashable {
    case available
    case popupFallback = "popup-fallback"
    case unavailable

    var shortLabel: String {
        switch self {
        case .available:
            return "Available"
        case .popupFallback:
            return "Popup fallback"
        case .unavailable:
            return "Unavailable"
        }
    }

    var explanation: String {
        switch self {
        case .available:
            return "Inline underlines are available for this adapter."
        case .popupFallback:
            return "Audora falls back to the coach popup when precise inline geometry is unavailable."
        case .unavailable:
            return "This adapter is off, unsupported, or blocked by permissions."
        }
    }
}

struct WritingSurfaceSnapshot: Hashable {
    var surfaceID: String
    var text: String
    var sourceApp: String
    var contextLabel: String
    var origin: WritingSurfaceOrigin
    var selectionRange: NSRange?
}

struct WritingIssueSpan: Identifiable, Hashable {
    var id: String
    var kind: WritingIssueKind
    var ruleID: String
    var term: String
    var rangeLower: Int
    var rangeUpper: Int
    var message: String
    var snippet: String
    var replacements: [String]

    var sourceRange: NSRange {
        NSRange(location: rangeLower, length: max(0, rangeUpper - rangeLower))
    }

    var primaryReplacement: String? {
        replacements.first
    }
}

struct WritingUnderlinePayload: Hashable {
    var surfaceID: String
    var text: String
    var sourceApp: String
    var contextLabel: String
    var origin: WritingSurfaceOrigin
    var spans: [WritingIssueSpan]
    var confidence: Double
    var fingerprint: String

    var hasAvoidSpans: Bool {
        spans.contains { $0.kind == .avoid }
    }
}

struct FocusedTextRangeBounds: Hashable {
    var rangeLower: Int
    var rangeUpper: Int
    var rect: CGRect

    var sourceRange: NSRange {
        NSRange(location: rangeLower, length: max(0, rangeUpper - rangeLower))
    }
}

protocol WritingSurfaceAdapter: AnyObject {
    var adapterID: String { get }
    var status: WritingAdapterStatus { get }
    func update(payload: WritingUnderlinePayload?)
}

