import Foundation

@MainActor
final class WritingSurfaceDebounceCoordinator {
    static let shared = WritingSurfaceDebounceCoordinator()

    private var workItems: [String: DispatchWorkItem] = [:]
    private var lastFingerprints: [String: String] = [:]

    private init() {}

    func schedule(
        surfaceID: String,
        fingerprint: String,
        delay: TimeInterval = 0.14,
        action: @escaping () -> Void
    ) {
        if lastFingerprints[surfaceID] == fingerprint {
            return
        }

        workItems[surfaceID]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.lastFingerprints[surfaceID] = fingerprint
            self?.workItems[surfaceID] = nil
            action()
        }
        workItems[surfaceID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func invalidate(surfaceID: String) {
        workItems[surfaceID]?.cancel()
        workItems[surfaceID] = nil
        lastFingerprints[surfaceID] = nil
    }
}

