import Carbon
import Foundation

@MainActor
final class GlobalHotKey {
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let action: @MainActor () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.action = action
        register(keyCode: keyCode, modifiers: modifiers)
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return noErr
                }

                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    hotKey.action()
                }
                return noErr
            },
            1,
            &eventSpec,
            userData,
            &eventHandlerRef
        )

        if handlerStatus != noErr {
            NSLog("Agent Pulse failed to install hotkey handler: \(handlerStatus)")
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x41504C53), id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if hotKeyStatus != noErr {
            NSLog("Agent Pulse failed to register hotkey: \(hotKeyStatus)")
        }
    }
}
