import Carbon
import Foundation

@MainActor
final class GlobalHotKey {
    private static let signature = OSType(0x41504C53) // "APLS"
    private static let id = UInt32(1)

    private let action: @MainActor () -> Void
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var registered: (keyCode: UInt32, modifiers: UInt32)?

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        installEventHandler()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// (Re)registers the global hotkey. Carbon modifiers are the `cmdKey` /
    /// `shiftKey` / … bit flags. Safe to call repeatedly; a no-op if unchanged.
    func register(keyCode: UInt32, modifiers: UInt32) {
        guard registered?.keyCode != keyCode || registered?.modifiers != modifiers else {
            return
        }

        unregister()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.id)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )

        guard status == noErr, let newRef else {
            NSLog("Agent Pulse failed to register hotkey: \(status)")
            registered = nil
            return
        }

        hotKeyRef = newRef
        registered = (keyCode, modifiers)
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        registered = nil
    }

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      hotKeyID.signature == GlobalHotKey.signature,
                      hotKeyID.id == GlobalHotKey.id else {
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
    }
}
