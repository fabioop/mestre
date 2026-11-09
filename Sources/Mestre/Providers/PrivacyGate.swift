import AppKit
import MestreCore

/// A privacy permission a provider needs before it has rows to show (Calendar, Reminders,
/// Contacts). The status is checked once per panel show, not on every keystroke; macOS is asked
/// the first time the feature is used, never at launch; once refused, a row points to System Settings.
@MainActor
final class PrivacyGate {
    enum Status { case granted, undetermined, denied }

    nonisolated static let openPrivacy = ItemAction(id: "openPrivacy", title: "Open Privacy Settings", icon: "gear")

    /// The row shown once access was refused.
    let row: SettingsLinkItem
    /// True while macOS shows its prompt.
    private(set) var isRequesting = false
    private let check: @MainActor () -> Status
    private let request: @MainActor () async -> Void
    private var cached: Status?

    /// `anchor`: the Privacy & Security pane, like "Privacy_Calendars". `request` asks macOS.
    init(anchor: String, title: String, subtitle: String, kind: ItemKind,
         status: @escaping @MainActor () -> Status, request: @escaping @MainActor () async -> Void) {
        row = SettingsLinkItem(id: "access", title: title, subtitle: subtitle, iconSymbol: "lock", kind: kind,
                               action: Self.openPrivacy, url: SettingsPane.privacyURL(anchor))
        check = status
        self.request = request
    }

    var status: Status {
        if let cached { return cached }
        let current = check()
        cached = current
        return current
    }

    var isGranted: Bool { status == .granted }

    /// Call from `panelWillShow`, so a grant or a refusal in System Settings shows on the next open.
    func reset() { cached = nil }

    /// Stores a status the provider read off the main thread, for a check that is slow IPC (Contacts).
    /// True when it differs from the last one known.
    func update(_ status: Status) -> Bool {
        defer { cached = status }
        return cached != nil && cached != status
    }

    /// Nil once access is granted; else what the provider shows instead of its rows: nothing while
    /// macOS asks (first use), the row pointing to System Settings once refused.
    func blockingRows(provider: any ResultProvider) -> [ScoredItem]? {
        switch status {
        case .granted:
            return nil
        case .undetermined:
            requestAccess { [weak provider] in provider?.onChange?() }
            return []
        case .denied:
            return ScoredItem.pinned([row], provider: provider)
        }
    }

    /// Asks macOS once at a time; `then` runs after the answer, with the status read afresh.
    private func requestAccess(then done: @escaping () -> Void) {
        guard !isRequesting else { return }
        isRequesting = true
        Task {
            await request()
            isRequesting = false
            cached = nil
            done()
        }
    }
}
