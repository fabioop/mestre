import AppKit
import EventKit
import MestreCore

/// The one EventKit store the calendar and reminders share. Connecting to the calendar daemon
/// takes tens of ms, so it is made off the main thread, and only when a feature first needs it.
@MainActor
enum SharedEventStore {
    private static var store: EKEventStore?

    static func get() async -> EKEventStore {
        if let store { return store }
        let made = await Task.detached(priority: .userInitiated) { EKEventStore() }.value
        // Another caller may have made one meanwhile: keep a single store.
        if let store { return store }
        store = made
        return made
    }

    /// A store made before access was granted can go on seeing nothing, also after a later grant
    /// in System Settings; the next caller makes a new one.
    static func reset() { store = nil }

    // MARK: Access

    nonisolated static func status(for type: EKEntityType) -> PrivacyGate.Status {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: return .granted
        case .notDetermined: return .undetermined
        default: return .denied
        }
    }

    /// Asks macOS the first time; once refused, only System Settings can change it, so it opens there.
    static func requestAccess(to type: EKEntityType) async {
        switch status(for: type) {
        case .undetermined:
            let store = await get()
            if type == .event {
                _ = try? await store.requestFullAccessToEvents()
            } else {
                _ = try? await store.requestFullAccessToReminders()
            }
            // A store made before access can go on seeing nothing; the next read makes a new one.
            reset()
        case .granted:
            break
        case .denied:
            NSWorkspace.shared.open(SettingsPane.privacyURL(privacyAnchor(for: type)))
        }
    }

    static func privacyAnchor(for type: EKEntityType) -> String {
        type == .event ? "Privacy_Calendars" : "Privacy_Reminders"
    }

    // MARK: Changes

    private static var subscribers: [(invalidate: @MainActor () -> Void, refresh: @MainActor () -> Void)] = []
    private static var isObserving = false
    private static var isFlushPending = false

    /// One observer for every store Mestre makes (the cached one is replaced after an access
    /// prompt). A burst of changes is folded into one pass: each subscriber's `invalidate` runs,
    /// then one `refresh`, since every provider's `onChange` runs the same search.
    static func observeChanges(invalidate: @escaping @MainActor () -> Void, refresh: @escaping @MainActor () -> Void) {
        subscribers.append((invalidate, refresh))
        guard !isObserving else { return }
        isObserving = true
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { scheduleFlush() }
        }
    }

    private static func scheduleFlush() {
        guard !isFlushPending else { return }
        isFlushPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            MainActor.assumeIsolated {
                isFlushPending = false
                for subscriber in subscribers { subscriber.invalidate() }
                subscribers.last?.refresh()
            }
        }
    }
}
