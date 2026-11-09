import AppKit
import Contacts
import MestreCore

struct ContactItem: SearchItem {
    let record: ContactRecord
    let defaultAction: ContactActions.Kind

    /// Built when asked, which is for the selected row only, not for every row on every keystroke.
    var actions: [ItemAction] { ContactActions.actions(for: record, defaultAction: defaultAction) }

    var id: String { record.id }
    var title: String { record.name }
    var subtitle: String? { record.subtitle }
    var icon: NSImage? { nil }
    var iconSymbol: String? { "person.crop.circle" }
    var kind: ItemKind { .contact }
}

/// "contact jane" searches Contacts; once access is granted, ordinary queries do too
/// (`contacts.searchEverywhere`). Contacts are read off the main thread into an in-memory index,
/// at launch when access was already granted, and again on the next use after Contacts says they changed.
/// Nothing is written to disk and no photos are loaded.
@MainActor
final class ContactsProvider: ResultProvider {
    nonisolated let id = "contacts"
    nonisolated let title = "Contacts"
    nonisolated let declaredActions = ContactActions.declared + [PrivacyGate.openPrivacy]

    var settings = Config.Contacts() {
        didSet {
            mode = KeywordMode(enabled: settings.enabled, keyword: settings.keyword, needsSpace: true)
            if !settings.enabled {
                index = nil
            } else if index == nil {
                refreshAccess()
            }
        }
    }
    /// Needs the space, so "contact" on its way to the Contacts app still finds it.
    private var mode = KeywordMode(enabled: true, keyword: Config.Contacts().keyword, needsSpace: true)
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    /// First use of the keyword: macOS asks once. Refused, the row points to System Settings.
    private lazy var gate = PrivacyGate(anchor: "Privacy_Contacts", title: "Allow Contacts Access",
                                        subtitle: "Mestre needs it to search your contacts", kind: .contact,
                                        status: Self.authorization,
                                        request: { [weak self] in await self?.requestAccess() })
    /// Nil until read, and again once the feature is off or access is taken back.
    private var index: ContactIndex?
    /// Kept so Contacts posts its change notifications to this process.
    private var store: CNContactStore?
    private var isLoading = false
    /// Contacts changed since `index` was read: it is read again on the next panel open or keyword
    /// use, never while the panel is hidden, and the old index answers until the new one lands.
    private var isStale = false
    private var isWatching = false

    private nonisolated static func authorization() -> PrivacyGate.Status {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: return .granted
        case .notDetermined: return .undetermined
        default: return .denied
        }
    }

    func owns(_ query: Query) -> Bool { mode.matches(query) }

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "contacts", title: "Contacts", subtitle: "Email, call or message anyone in Contacts", symbol: "person.crop.circle", keyword: settings.keyword)
    }

    func emptyMessage(for query: Query) -> String? {
        if isLoading && index == nil { return "Reading your contacts…" }
        if gate.isRequesting { return "Waiting for Contacts access…" }
        return query.remainder.isEmpty ? "No contacts" : "No matching contacts"
    }

    func panelWillShow() { refreshAccess() }

    /// Re-reads the permission off the main thread (the check is IPC to the contacts daemon, about
    /// 14 ms each time) and then reads the contacts if they are missing or stale.
    private func refreshAccess() {
        guard settings.enabled else { return }
        Task {
            let status = await Task.detached(priority: .userInitiated) { Self.authorization() }.value
            let changed = gate.update(status)
            guard settings.enabled else { return }
            switch status {
            case .granted:
                if index == nil || isStale { load() }
            case .undetermined:
                break
            case .denied:
                // Access taken back in System Settings: forget what was read.
                index = nil
            }
            if changed { onChange?() }
        }
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard settings.enabled else { return [] }
        if mode.matches(query) { return keywordResults(query.remainder, limit: min(limit, settings.maxResults)) }
        // Never asks: ordinary searches only use contacts already read with access granted.
        guard settings.searchEverywhere, let index, query.text.count >= settings.minimumLength, gate.isGranted else { return [] }
        return index.search(query.text, limit: limit, wordsOnly: true)
            .map { ScoredItem(item: item(for: $0.record), score: $0.score, provider: self) }
    }

    private func keywordResults(_ text: String, limit: Int) -> [ScoredItem] {
        if let rows = gate.blockingRows(provider: self) { return rows }
        if index == nil || isStale { load() }
        guard let index else { return [] }
        let hits = index.search(text, limit: limit)
        // An empty query lists contacts by name; a typed one by how well they match.
        if text.isEmpty { return ScoredItem.pinned(hits.map { item(for: $0.record) }, provider: self) }
        return hits.map { ScoredItem(item: item(for: $0.record), score: $0.score, provider: self) }
    }

    private func item(for record: ContactRecord) -> ContactItem {
        ContactItem(record: record, defaultAction: settings.defaultAction)
    }

    /// The prompt; the keyword's next search, which the gate triggers, reads the contacts.
    private func requestAccess() async {
        _ = try? await contactStore().requestAccess(for: .contacts)
    }

    /// The one store, made on first use. Connecting to the contacts daemon is kept off the main thread.
    private func contactStore() async -> CNContactStore {
        if let store { return store }
        let made = await Task.detached(priority: .userInitiated) { CNContactStore() }.value
        if let store { return store }
        store = made
        return made
    }

    /// Reads every contact. A change that arrives during the read marks the index stale again.
    private func load() {
        guard !isLoading else { return }
        isLoading = true
        isStale = false
        Task {
            let store = await contactStore()
            let loaded = await Task.detached(priority: .utility) { ContactIndex(Self.read(store)) }.value
            isLoading = false
            watchForChanges()
            if settings.enabled, gate.isGranted {
                index = loaded
                onChange?()
            }
        }
    }

    private func watchForChanges() {
        guard !isWatching else { return }
        isWatching = true
        // Several arrive while a sync runs: they only mark the index stale, so all of them cost one read, later.
        NotificationCenter.default.addObserver(forName: .CNContactStoreDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isStale = true }
        }
    }

    /// Names, nickname, organisation, emails and phones of every contact. No photos.
    private nonisolated static func read(_ store: CNContactStore) -> [ContactRecord] {
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var records: [ContactRecord] = []
        try? store.enumerateContacts(with: request) { contact, _ in
            records.append(ContactRecord(
                id: contact.identifier,
                name: CNContactFormatter.string(from: contact, style: .fullName) ?? "",
                nickname: contact.nickname,
                organization: contact.organizationName,
                emails: contact.emailAddresses.map { .init(label: label($0.label), value: $0.value as String) },
                phones: contact.phoneNumbers.map { .init(label: label($0.label), value: $0.value.stringValue) }
            ))
        }
        return records
    }

    private nonisolated static func label(_ raw: String?) -> String? {
        raw.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) }
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        if openSettingsLink(item) { return }
        guard let record = (item as? ContactItem)?.record, let target = ContactActions.target(for: action.id) else { NSSound.beep(); return }
        switch target.kind {
        case .copyEmail, .copyPhone:
            guard let value = ContactActions.value(for: target, in: record) else { NSSound.beep(); return }
            value.copyToPasteboard(toast: target.kind == .copyEmail ? "Email copied" : "Phone copied")
        default:
            guard let url = ContactActions.url(for: target, in: record, settings: settings) else { NSSound.beep(); return }
            dismiss?()
            NSWorkspace.shared.open(url)
        }
    }
}
