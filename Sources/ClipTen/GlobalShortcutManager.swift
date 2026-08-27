import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalShortcutManager {
    struct Definition: Equatable {
        let slot: Int
        let keyCode: UInt32
    }

    static let definitions: [Definition] = [
        .init(slot: 0, keyCode: UInt32(kVK_ANSI_1)),
        .init(slot: 1, keyCode: UInt32(kVK_ANSI_2)),
        .init(slot: 2, keyCode: UInt32(kVK_ANSI_3)),
        .init(slot: 3, keyCode: UInt32(kVK_ANSI_4)),
        .init(slot: 4, keyCode: UInt32(kVK_ANSI_5)),
        .init(slot: 5, keyCode: UInt32(kVK_ANSI_6)),
        .init(slot: 6, keyCode: UInt32(kVK_ANSI_7)),
        .init(slot: 7, keyCode: UInt32(kVK_ANSI_8)),
        .init(slot: 8, keyCode: UInt32(kVK_ANSI_9)),
        .init(slot: 9, keyCode: UInt32(kVK_ANSI_0))
    ]

    static let modifierFlags = UInt32(controlKey | shiftKey)

    private static let signature: OSType = 0x436C_3130 // "Cl10"

    private let action: (Int) -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKeyReferences: [EventHotKeyRef] = []

    private(set) var registeredSlots: Set<Int> = []

    init(action: @escaping (Int) -> Void) {
        self.action = action
    }

    @discardableResult
    func register() -> Set<Int> {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            clipTenHotKeyHandler,
            1,
            &eventType,
            userData,
            &eventHandler
        )
        guard handlerStatus == noErr else { return [] }

        for definition in Self.definitions {
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(
                signature: Self.signature,
                id: UInt32(definition.slot + 1)
            )
            let status = RegisterEventHotKey(
                definition.keyCode,
                Self.modifierFlags,
                identifier,
                GetApplicationEventTarget(),
                0,
                &reference
            )

            guard status == noErr, let reference else { continue }
            hotKeyReferences.append(reference)
            registeredSlots.insert(definition.slot)
        }

        return registeredSlots
    }

    func unregister() {
        for reference in hotKeyReferences {
            UnregisterEventHotKey(reference)
        }
        hotKeyReferences.removeAll()
        registeredSlots.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    fileprivate func handle(slot: Int) {
        guard registeredSlots.contains(slot) else { return }
        action(slot)
    }
}

private func clipTenHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr, identifier.signature == 0x436C_3130 else {
        return OSStatus(eventNotHandledErr)
    }

    let slot = Int(identifier.id) - 1
    let manager = Unmanaged<GlobalShortcutManager>
        .fromOpaque(userData)
        .takeUnretainedValue()
    Task { @MainActor in
        manager.handle(slot: slot)
    }
    return noErr
}
