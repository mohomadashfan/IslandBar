import Carbon.HIToolbox
import IslandCore

/// System-wide shortcut via Carbon's `RegisterEventHotKey`, which is still the supported way to
/// register a global hot key and, unlike event taps, needs no Accessibility permission.
@MainActor
final class GlobalHotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handler: EventHandlerRef?
    private static let signature = OSType(0x4953_4C42)  // "ISLB"

    private var reference: EventHotKeyRef?
    private let id: UInt32

    /// Returns `nil` if the shortcut is disabled or already taken by another app.
    init?(shortcut: ToggleShortcut, action: @escaping () -> Void) {
        guard let (keyCode, modifiers) = Self.keyCombination(for: shortcut) else { return nil }
        Self.installHandlerIfNeeded()

        id = Self.nextID
        Self.nextID += 1

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &reference
        )
        guard status == noErr, let reference else { return nil }
        self.reference = reference
        Self.actions[id] = action
    }

    func unregister() {
        if let reference {
            UnregisterEventHotKey(reference)
        }
        reference = nil
        Self.actions[id] = nil
    }

    private static func keyCombination(for shortcut: ToggleShortcut) -> (UInt32, UInt32)? {
        let controlOption = UInt32(controlKey | optionKey)
        return switch shortcut {
        case .disabled: nil
        case .controlOptionSpace: (UInt32(kVK_Space), controlOption)
        case .controlOptionI: (UInt32(kVK_ANSI_I), controlOption)
        }
    }

    private static func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == GlobalHotKey.signature else { return status }
            let id = hotKeyID.id
            // Application event target handlers run on the main thread.
            MainActor.assumeIsolated {
                GlobalHotKey.actions[id]?()
            }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
