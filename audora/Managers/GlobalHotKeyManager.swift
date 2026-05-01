import Carbon
import Foundation

@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private let hotKeySignature = OSType(0x4157444C)
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var actionsByHotKeyID: [UInt32: () -> Void] = [:]

    private init() {
        register()
    }

    deinit {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
    }

    private func register() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.stride,
                    nil,
                    &hotKeyID
                )

                guard status == noErr else {
                    return status
                }

                if hotKeyID.signature == GlobalHotKeyManager.shared.hotKeySignature,
                   let action = GlobalHotKeyManager.shared.actionsByHotKeyID[hotKeyID.id] {
                    action()
                }

                return noErr
            },
            1,
            &eventSpec,
            nil,
            &eventHandlerRef
        )

        registerHotKey(
            id: 1,
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt32(cmdKey | shiftKey)
        ) {
            NotificationCenter.default.post(name: .openWritingLens, object: nil)
        }

        registerHotKey(
            id: 2,
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt32(cmdKey | optionKey | controlKey)
        ) {
            WritingAwarenessManager.shared.captureSelectionAsLearningTarget()
        }
    }

    private func registerHotKey(
        id: UInt32,
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: id)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if let hotKeyRef {
            hotKeyRefs.append(hotKeyRef)
            actionsByHotKeyID[id] = action
        }
    }
}
