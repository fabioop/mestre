import Carbon.HIToolbox
import MestreCore

// Four-char code 'MSTR'. Lets the handler ignore hotkey events that aren't ours.
private let hotKeySignature: OSType = 0x4D535452

/// Registers system-wide hotkeys through the Carbon Hot Key API. Unlike CGEvent
/// taps this needs no Accessibility permission and fires while another app is
/// frontmost, which is exactly what a launcher needs.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    struct RegistrationError: Error, LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "another app may already use this shortcut (OSStatus \(status))"
        }
    }

    /// Called with the id passed to `register`.
    var onPress: ((UInt32) -> Void)?

    private var registered: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// Replaces every registration with `combos`. Returns the combos that failed, by id.
    @discardableResult
    func replaceAll(with combos: [UInt32: KeyCombo]) -> [UInt32: RegistrationError] {
        unregisterAll()
        var failures: [UInt32: RegistrationError] = [:]
        do {
            try installHandlerIfNeeded()
        } catch let error as RegistrationError {
            for id in combos.keys { failures[id] = error }
            return failures
        } catch { return failures }

        for (id, combo) in combos.sorted(by: { $0.key < $1.key }) {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: id)
            let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[id] = ref
            } else {
                failures[id] = RegistrationError(status: status)
            }
        }
        return failures
    }

    func unregisterAll() {
        for ref in registered.values { UnregisterEventHotKey(ref) }
        registered.removeAll()
    }

    private func installHandlerIfNeeded() throws {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                // C callback: no captures allowed, so `self` travels through userData.
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                guard hotKeyID.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                let id = hotKeyID.id
                // Carbon delivers on the main thread; tell the compiler so.
                MainActor.assumeIsolated { manager.onPress?(id) }
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard status == noErr else { throw RegistrationError(status: status) }
    }
}
