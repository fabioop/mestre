import Foundation

/// The actions a contact row offers, and the links they open. Pure, so the ids, order and
/// URLs are tested; the app only copies and opens.
public enum ContactActions {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case reveal, copyEmail, copyPhone, email, call, message, facetime

        /// The ⌘K menu's title, also Settings' name for the Return action.
        public var title: String {
            switch self {
            case .reveal: return "Open in Contacts"
            case .copyEmail: return "Copy Email"
            case .copyPhone: return "Copy Phone"
            case .email: return "Email"
            case .call: return "Call"
            case .message: return "Message"
            case .facetime: return "FaceTime"
            }
        }

        var icon: String {
            switch self {
            case .reveal: return "person.crop.circle"
            case .copyEmail, .copyPhone: return "doc.on.doc"
            case .email: return "envelope"
            case .call: return "phone"
            case .message: return "message"
            case .facetime: return "video"
            }
        }

        /// The shared `reveal` id gets ⌘↩, as Show in Finder does.
        var defaultKeys: [String] { self == .reveal ? ItemAction.reveal.defaultKeys : [] }

        var action: ItemAction { ItemAction(id: rawValue, title: title, icon: icon, defaultKeys: defaultKeys) }
    }

    /// One action and the value it acts on.
    public struct Target: Equatable, Sendable {
        public let kind: Kind
        /// Index into the emails or phones it uses; 0 for `reveal`.
        public let index: Int
    }

    /// Every action id a contact can carry, for the action table and key bindings.
    public static var declared: [ItemAction] { Kind.allCases.map(\.action) }

    /// A contact's actions: `defaultAction` first when the card has what it needs, then one per
    /// value. The first value of each kind keeps the plain id ("email"), so a bound key acts on
    /// it; the others are "email.1", "email.2"…, and name their value in the title.
    public static func actions(for record: ContactRecord, defaultAction: Kind = .reveal) -> [ItemAction] {
        var actions: [ItemAction] = []
        for kind in Kind.allCases where kind != .reveal {
            let values = values(for: kind, in: record)
            for (index, value) in values.enumerated() {
                let suffix = values.count > 1 ? " \(value.value)" + (value.label.map { " (\($0))" } ?? "") : ""
                actions.append(ItemAction(id: kind.rawValue + (index == 0 ? "" : ".\(index)"), title: kind.title + suffix, icon: kind.icon))
            }
        }
        actions.append(Kind.reveal.action)
        // A card without the value the default needs opens in Contacts instead.
        let first = actions.firstIndex { $0.id == defaultAction.rawValue } ?? actions.count - 1
        actions.insert(actions.remove(at: first), at: 0)
        return actions
    }

    /// What an action id from `actions(for:)` does; nil for an id it never makes.
    public static func target(for id: String) -> Target? {
        let parts = id.split(separator: ".", maxSplits: 1)
        guard let kind = parts.first.flatMap({ Kind(rawValue: String($0)) }) else { return nil }
        guard parts.count == 2 else { return Target(kind: kind, index: 0) }
        guard kind != .reveal, let index = Int(parts[1]), index > 0 else { return nil }
        return Target(kind: kind, index: index)
    }

    /// The value an action uses: emails for mail, phones for calls; messages and FaceTime use
    /// the phones, or the emails on a card without one.
    public static func values(for kind: Kind, in record: ContactRecord) -> [ContactRecord.Value] {
        switch kind {
        case .reveal: return []
        case .copyEmail, .email: return record.emails
        case .copyPhone, .call: return record.phones
        case .message, .facetime: return record.phones.isEmpty ? record.emails : record.phones
        }
    }

    public static func value(for target: Target, in record: ContactRecord) -> String? {
        let values = values(for: target.kind, in: record)
        return values.indices.contains(target.index) ? values[target.index].value : nil
    }

    /// The link an action opens; nil for the copy actions and for a value it can't use.
    public static func url(for target: Target, in record: ContactRecord, settings: Config.Contacts = Config.Contacts()) -> URL? {
        if target.kind == .reveal { return URL(string: "addressbook://" + record.id) }
        guard let value = value(for: target, in: record) else { return nil }
        // A phone keeps its digits and leading +; an email address stays whole.
        let address = value.contains("@") ? value : dialable(value)
        guard !address.isEmpty else { return nil }
        let scheme: String
        switch target.kind {
        case .email: scheme = "mailto"
        case .call: scheme = settings.callScheme.rawValue
        case .message: scheme = settings.messageScheme.rawValue
        case .facetime: scheme = "facetime"
        case .reveal, .copyEmail, .copyPhone: return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.path = address
        return components.url
    }

    /// "+351 912-345 678" → "+351912345678". An extension ("ext. 89", "x89", ",89") is left off.
    public static func dialable(_ phone: String) -> String {
        let number = phone.prefix { !$0.isLetter && $0 != "," && $0 != ";" }
        let digits = String(decoding: ContactIndex.digits(of: String(number)), as: UTF8.self)
        return number.trimmingCharacters(in: .whitespaces).hasPrefix("+") && !digits.isEmpty ? "+" + digits : digits
    }
}

public extension Config {
    /// "contact jane": contacts by name, nickname, organisation, email or phone. Read with
    /// Contacts access, kept in memory only.
    struct Contacts: Codable, Equatable, Sendable {
        public enum CallScheme: String, Codable, CaseIterable, Sendable {
            /// A phone call through an iPhone nearby (Continuity).
            case tel
            /// A FaceTime audio call.
            case facetimeAudio = "facetime-audio"
        }

        public enum MessageScheme: String, Codable, CaseIterable, Sendable {
            case sms, imessage
        }

        public var enabled: Bool = true
        public var keyword: String = "contact"
        /// Contacts also answer ordinary queries of `minimumLength`+ characters, below apps by
        /// `ranking.providers.contacts.bias`, once access has been granted. Ordinary searches never ask for access.
        public var searchEverywhere: Bool = true
        public var minimumLength: Int = 2
        public var maxResults: Int = 20
        /// What Return does on a contact, when the card has the value it needs.
        public var defaultAction: ContactActions.Kind = .reveal
        public var callScheme: CallScheme = .tel
        public var messageScheme: MessageScheme = .sms

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, keyword, searchEverywhere, minimumLength, maxResults, defaultAction, callScheme, messageScheme }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            keyword = try c.decodeKeyword(forKey: .keyword, default: keyword)
            searchEverywhere = try c.decodeIfPresent(Bool.self, forKey: .searchEverywhere) ?? searchEverywhere
            minimumLength = min(10, max(1, try c.decodeIfPresent(Int.self, forKey: .minimumLength) ?? minimumLength))
            maxResults = min(100, max(1, try c.decodeIfPresent(Int.self, forKey: .maxResults) ?? maxResults))
            defaultAction = c.decodeChoice(forKey: .defaultAction) ?? defaultAction
            callScheme = c.decodeChoice(forKey: .callScheme) ?? callScheme
            messageScheme = c.decodeChoice(forKey: .messageScheme) ?? messageScheme
        }
    }
}
