import AppKit

@MainActor
final class LearningWordServiceProvider: NSObject {
    @objc(addToLearningWords:userData:error:)
    func addToLearningWords(
        _ pasteboard: NSPasteboard,
        userData _: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        let text = pasteboard.string(forType: .string) ?? ""
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Service"
        let contextLabel = BrowserURLHelper.getCurrentContext() ?? sourceApp

        let result = WritingAwarenessManager.shared.submitLearningTarget(
            text: text,
            sourceApp: sourceApp,
            contextLabel: contextLabel,
            origin: "service"
        )

        if result?.status == .invalid {
            error?.pointee = (result?.message ?? "Couldn't prepare learning words.") as NSString
        }
    }
}
