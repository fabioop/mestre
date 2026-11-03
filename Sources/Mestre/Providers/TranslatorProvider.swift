import AppKit
import MestreCore
import Translation

struct TranslationItem: SearchItem {
    let translated: String
    let languages: String

    var id: String { "translation" }
    var title: String { translated }
    var subtitle: String? { languages }
    var icon: NSImage? { nil }
    var iconSymbol: String? { "translate" }
    var kind: ItemKind { .translation }
    var actions: [ItemAction] { [Self.copy] }

    static let copy = ItemAction(id: "copy", title: "Copy Translation", icon: "doc.on.doc")
}

enum TranslationOutcome: Equatable, Sendable {
    case translated(String)
    case needsDownload
    case unsupported
    case failed
    case needsNewerSystem
}

/// "tr bom dia" translates on this Mac, after a short pause and off the main thread, so the rows
/// arrive through onChange. Nothing is sent anywhere: only downloaded languages are used.
@MainActor
final class TranslatorProvider: ResultProvider {
    nonisolated let id = "translator"
    nonisolated let declaredActions = [TranslationItem.copy, TranslatorProvider.openLanguages]

    var settings = Config.Translator() {
        didSet {
            mode = KeywordMode(enabled: settings.enabled, keyword: settings.keyword, needsSpace: true)
            languages = TranslationLanguages.effective(configured: settings.languages)
        }
    }
    /// Needs the space, so "tr" on its way to "Transmit" or "Trash" still finds them.
    private var mode = KeywordMode(enabled: true, keyword: Config.Translator().keyword, needsSpace: true)
    private var languages = TranslationLanguages.effective(configured: [])
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    static let openLanguages = ItemAction(id: "openLanguages", title: "Open Language & Region", icon: "gear")

    private var answer: (input: String, languages: String, outcome: TranslationOutcome)?
    /// The latest translation: a pause, then the work. Cancelled by the next keystroke.
    private var running: (input: String, task: Task<Void, Never>)?

    /// Where a query stands, worked out once for both the rows and the empty message.
    private enum State {
        case nothingYet, tooLong
        case waiting(TranslationRequest, input: String)
        case answered(input: String, languages: String, outcome: TranslationOutcome)
    }

    private func state(of query: Query) -> State {
        let input = query.remainder
        guard let request = TranslationRequest.parse(input) else { return .nothingYet }
        guard input.count <= settings.maxCharacters else { return .tooLong }
        if let answer, answer.input == input { return .answered(input: input, languages: answer.languages, outcome: answer.outcome) }
        return .waiting(request, input: input)
    }

    func owns(_ query: Query) -> Bool { mode.matches(query) }

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "translator", title: "Translate", subtitle: "On this Mac. >de picks the language", symbol: "translate", keyword: settings.keyword)
    }

    func emptyMessage(for query: Query) -> String? {
        switch state(of: query) {
        case .nothingYet: return "Translate: bom dia, >de hello, en>pt hello"
        case .tooLong: return "Too long to translate here"
        case .waiting: return "Translating…"
        case .answered(_, let languages, .unsupported): return "macOS can't translate \(languages)"
        case .answered(_, _, .needsNewerSystem): return "Translating needs macOS 26"
        case .answered(_, _, .failed): return "Couldn't translate that"
        case .answered: return nil
        }
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard owns(query) else { return [] }
        switch state(of: query) {
        case .nothingYet, .tooLong:
            queryLeft()
            return []
        case .waiting(let request, let input):
            if running?.input != input { translate(request, input: input) }
            return []
        case .answered(_, let languages, .translated(let text)):
            return ScoredItem.pinned([TranslationItem(translated: text, languages: languages)], provider: self)
        case .answered(_, let languages, .needsDownload):
            let row = SettingsLinkItem(id: "download", title: "Download Languages to Translate", subtitle: languages, iconSymbol: "arrow.down.circle",
                                       kind: .translation, action: Self.openLanguages, url: SettingsPane.languageAndRegion.url)
            return ScoredItem.pinned([row], provider: self)
        case .answered:
            return []
        }
    }

    func queryLeft() {
        running?.task.cancel()
        running = nil
        answer = nil
    }

    private func translate(_ request: TranslationRequest, input: String) {
        running?.task.cancel()
        let languages = languages
        let pause = settings.debounceSeconds
        running = (input, Task {
            try? await Task.sleep(for: .seconds(pause))
            guard !Task.isCancelled else { return }
            let (names, outcome) = await Task.detached(priority: .userInitiated) { await Self.run(request, languages: languages) }.value
            guard !Task.isCancelled else { return }
            answer = (input, names, outcome)
            onChange?()
        })
    }

    private nonisolated static func run(_ request: TranslationRequest, languages: [String]) async -> (String, TranslationOutcome) {
        let source = request.source ?? TranslationLanguages.detect(request.text, hints: languages)
        guard let source else { return ("this text", .unsupported) }
        guard let target = request.target ?? TranslationLanguages.target(from: source, languages: languages) else { return (TranslationLanguages.name(of: source), .unsupported) }
        let names = "\(TranslationLanguages.name(of: source)) → \(TranslationLanguages.name(of: target))"
        guard #available(macOS 26.0, *) else { return (names, .needsNewerSystem) }
        return (names, await translated(request.text, source: source, target: target))
    }

    @available(macOS 26.0, *)
    private nonisolated static func translated(_ text: String, source: String, target: String) async -> TranslationOutcome {
        let from = Locale.Language(identifier: source)
        let to = Locale.Language(identifier: target)
        switch await LanguageAvailability().status(from: from, to: to) {
        case .unsupported: return .unsupported
        case .supported: return .needsDownload
        case .installed: break
        @unknown default: return .failed
        }
        do {
            return .translated(try await TranslationSession(installedSource: from, target: to).translate(text).targetText)
        } catch {
            return .failed
        }
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        if openSettingsLink(item) { return }
        guard let item = item as? TranslationItem else { return }
        item.translated.copyToPasteboard()
        dismiss?()
    }
}
