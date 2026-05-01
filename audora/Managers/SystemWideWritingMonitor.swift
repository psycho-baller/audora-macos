import AppKit
import CoreGraphics
import Foundation

@MainActor
final class SystemWideWritingMonitor: ObservableObject {
    static let shared = SystemWideWritingMonitor()

    @Published private(set) var isRunning = false
    @Published private(set) var isInputMonitoringTrusted = CGPreflightListenEventAccess()

    private let observedNotifications: [CFString] = [
        kAXFocusedUIElementChangedNotification as CFString,
        kAXFocusedWindowChangedNotification as CFString,
        kAXSelectedTextChangedNotification as CFString,
        kAXValueChangedNotification as CFString
    ]
    private var globalKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var scheduledRefresh: DispatchWorkItem?
    private var lastFingerprint = ""
    private var axObserver: AXObserver?
    private var observedApplicationElement: AXUIElement?
    private var observedPID: pid_t?

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        installMonitors()
        updateAXObserver()
        scheduleRefresh(delay: 0.1)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        scheduledRefresh?.cancel()
        scheduledRefresh = nil

        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        detachAXObserver()

        WritingAwarenessManager.shared.clearLiveCapture()
    }

    func refreshPermissionState() {
        isInputMonitoringTrusted = CGPreflightListenEventAccess()
    }

    func requestInputMonitoringAccess() {
        _ = CGRequestListenEventAccess()
        refreshPermissionState()
        if !isInputMonitoringTrusted {
            openInputMonitoringSettings()
        }
    }

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func installMonitors() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh(delay: 0.06)
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh(delay: 0.06)
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh(delay: 0.08)
            }
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateAXObserver()
                self?.scheduleRefresh(delay: 0.12)
            }
        }
    }

    private func updateAXObserver() {
        guard isRunning else { return }
        guard SelectionCaptureManager.shared.isTrusted else {
            detachAXObserver()
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            detachAXObserver()
            return
        }

        let pid = app.processIdentifier
        guard observedPID != pid else { return }

        detachAXObserver()

        let applicationElement = AXUIElementCreateApplication(pid)
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let monitor = Unmanaged<SystemWideWritingMonitor>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in
                monitor.scheduleRefresh(delay: 0.05)
            }
        }

        var observer: AXObserver?
        let result = AXObserverCreate(pid, callback, &observer)
        guard result == .success, let observer else {
            return
        }

        let observerRef = Unmanaged.passUnretained(self).toOpaque()
        for notification in observedNotifications {
            AXObserverAddNotification(observer, applicationElement, notification, observerRef)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        axObserver = observer
        observedApplicationElement = applicationElement
        observedPID = pid
    }

    private func detachAXObserver() {
        if let axObserver, let applicationElement = observedApplicationElement {
            for notification in observedNotifications {
                AXObserverRemoveNotification(axObserver, applicationElement, notification)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
        }

        axObserver = nil
        observedApplicationElement = nil
        observedPID = nil
    }

    private func scheduleRefresh(delay: TimeInterval) {
        guard isRunning else { return }
        scheduledRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshFocusedText()
            }
        }
        scheduledRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func refreshFocusedText() {
        refreshPermissionState()

        guard SelectionCaptureManager.shared.isTrusted else {
            lastFingerprint = ""
            WritingAwarenessManager.shared.clearLiveCapture()
            return
        }

        guard let capture = SelectionCaptureManager.shared.captureFocusedTextSnapshot() else {
            lastFingerprint = ""
            WritingAwarenessManager.shared.clearLiveCapture()
            return
        }

        if capture.sourceApp != "Audora" {
            WritingAwarenessManager.shared.cacheExternalFocusDiagnostics(
                SelectionCaptureManager.shared.debugFocusedElementDiagnostics(),
                sourceApp: capture.sourceApp
            )
        }

        let fingerprint = [
            capture.sourceApp,
            capture.text.prefix(240),
            capture.selectionRange.map { "\($0.location):\($0.length)" } ?? "none"
        ].map(String.init(describing:)).joined(separator: "|")

        guard fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint
        WritingAwarenessManager.shared.applyLiveCapture(capture, recordFeedback: true)
    }
}
