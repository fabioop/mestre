import Carbon.HIToolbox
import Foundation

/// Maps characters to virtual key codes for the keyboard layout currently in use,
/// so a config entry like "option+k" resolves to the right physical key on any layout.
public enum KeyCodeMap {
    // Text Input Source calls are not safe to make from several threads at once
    // (the test runner does exactly that), so serialise them and cache per layout.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: (sourceID: String, map: [Character: UInt16])?

    public static func current() -> [Character: UInt16] {
        lock.lock()
        defer { lock.unlock() }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return [:] }
        let sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? ""
        if let cache, cache.sourceID == sourceID { return cache.map }

        guard let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data

        var map: [Character: UInt16] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for keyCode in 0..<128 {
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars
                )
                guard status == noErr, length > 0, let scalar = Unicode.Scalar(chars[0]),
                      let character = String(scalar).lowercased().first
                else { continue }
                // Main-block keys have lower codes than the keypad; keep the first one seen.
                if map[character] == nil { map[character] = UInt16(keyCode) }
            }
        }
        cache = (sourceID, map)
        return map
    }
}
