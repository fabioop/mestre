import AppKit
import Carbon.HIToolbox
import MestreCore

/// Expands snippet keywords as they are typed anywhere, through a listen-only
/// keyboard event tap. Listen-only taps need the Input Monitoring permission; posting
/// the replacement needs Accessibility. Only the last few typed characters are kept
/// in memory, nothing is logged or stored.
///
/// Listen-only rather than an active tap: an active tap could swallow the final
/// keystroke, but a stalled callback would freeze typing system-wide. The price is a
/// small race between the Backspaces posted here and keys the user keeps typing.
@MainActor
final class TextExpander {
    var config = Config.Snippets() {
        didSet {
            matcher = ExpansionMatcher(snippets: config.enabled ? config.items : [])
            refresh()
        }
    }
    var paster: Paster?
    /// The host says when Mestre's own panel is up: typing a keyword there must not expand.
    var isSuspended: () -> Bool = { false }

    private var matcher = ExpansionMatcher(snippets: [])
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var observer: NSObjectProtocol?

    init() {
        // Permission can be granted while Mestre runs; app switches are a cheap moment to re-check.
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    static var hasInputMonitoring: Bool { CGPreflightListenEventAccess() }

    /// Shows the Input Monitoring prompt; macOS remembers the answer.
    static func requestInputMonitoring() { CGRequestListenEventAccess() }

    var isActive: Bool { tap != nil }

    /// Starts or stops the tap according to config, snippets and permissions.
    func refresh() {
        let wanted = config.expansion.enabled && !matcher.isEmpty && Self.hasInputMonitoring && Paster.canPaste
        if wanted != isActive { wanted ? start() : stop() }
    }

    private func start() {
        let keyEvents: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = keyEvents.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let expander = Unmanaged<TextExpander>.fromOpaque(userInfo).takeUnretainedValue()
            MainActor.assumeIsolated { expander.handle(type: type, event: event) }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { NSLog("Text expansion: could not create the event tap"); return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    private func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }  // macOS pauses slow taps; resume
            matcher.reset()
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            matcher.reset()  // the caret moved
        case .flagsChanged:
            if !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty { matcher.reset() }
        case .keyDown:
            guard event.getIntegerValueField(.eventSourceUserData) != Paster.ownEventTag else { return }
            if !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty { matcher.reset(); return }
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == kVK_Delete { matcher.deletedBackward(); return }
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &characters)
            let text = String(utf16CodeUnits: characters, count: length)
            // Arrows, function keys and friends come through as private-use characters.
            guard length > 0, !text.unicodeScalars.contains(where: { (0xF700...0xF8FF).contains($0.value) }), !text.contains(where: \.isNewline), text != "\t" else {
                matcher.reset()
                return
            }
            guard let snippet = matcher.typed(text) else { return }
            if shouldExpandNow(event) { expand(snippet) }
        default:
            break
        }
    }

    /// Not in Mestre's own windows, not in excluded apps, and not while an input method is composing.
    private func shouldExpandNow(_ event: CGEvent) -> Bool {
        if isSuspended() || event.getIntegerValueField(.eventTargetUnixProcessID) == Int64(ProcessInfo.processInfo.processIdentifier) { return false }
        if Self.isUsingInputMethod() { return false }
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return true }
        return !config.expansion.excludeApps.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    /// Japanese, Chinese and similar input modes compose text; raw key letters there aren't text.
    private static func isUsingInputMethod() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else { return false }
        return (Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String) == (kTISTypeKeyboardInputMode as String)
    }

    /// Deletes the keyword that was just typed, then pastes the expansion.
    private func expand(_ snippet: Snippet) {
        guard let paster, let keyword = snippet.keyword else { return }
        for _ in 0..<keyword.count { Paster.press(CGKeyCode(kVK_Delete)) }
        let expansion = SnippetProvider.expansion(of: snippet, with: config)
        paster.paste(expansion.text, caretMoves: expansion.cursorOffsetFromEnd, dismiss: nil)
    }
}
