import Foundation
import NaturalLanguage

/// What follows the translator's keyword: `hello`, `>de hello`, or `en>pt hello`.
public struct TranslationRequest: Equatable, Sendable {
    public let source: String?
    public let target: String?
    public let text: String

    public init(source: String? = nil, target: String? = nil, text: String) {
        self.source = source
        self.target = target
        self.text = text
    }

    /// Nil while there is nothing to translate yet ("", or only ">de").
    public static func parse(_ input: String) -> TranslationRequest? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
        if let (source, target) = languagePair(parts[0]) {
            guard parts.count == 2 else { return nil }
            return TranslationRequest(source: source, target: target, text: parts[1])
        }
        return TranslationRequest(text: trimmed)
    }

    /// "en>pt" or ">pt". Anything else, like "a>b>c" or "x>", is text.
    private static func languagePair(_ token: String) -> (String?, String)? {
        let sides = token.split(separator: ">", omittingEmptySubsequences: false).map(String.init)
        guard sides.count == 2, isLanguage(sides[1]), sides[0].isEmpty || isLanguage(sides[0]) else { return nil }
        return (sides[0].isEmpty ? nil : sides[0], sides[1])
    }

    private static func isLanguage(_ text: String) -> Bool {
        (2...16).contains(text.count) && text.first?.isLetter == true && text.allSatisfy { $0.isLetter || $0 == "-" || $0 == "_" }
    }
}

public enum TranslationLanguages {
    /// The language of `text`, leaning towards `hints`, which short text often needs ("casa").
    public static func detect(_ text: String, hints: [String]) -> String? {
        let recognizer = NLLanguageRecognizer()
        if !hints.isEmpty {
            let share = 0.8 / Double(hints.count)
            recognizer.languageHints = Dictionary(hints.map { (NLLanguage(baseCode($0)), share) }) { first, _ in first }
        }
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    /// The first of `languages` that isn't the language being translated from.
    public static func target(from source: String, languages: [String]) -> String? {
        languages.first { baseCode($0) != baseCode(source) }
    }

    /// `configured`, or else what the Mac is set to with English as the way out of it.
    public static func effective(configured: [String], preferred: [String] = Locale.preferredLanguages) -> [String] {
        configured.isEmpty ? preferred.map(baseCode) + ["en"] : configured
    }

    /// "pt-PT" → "pt".
    public static func baseCode(_ language: String) -> String {
        String(language.lowercased().prefix { $0 != "-" && $0 != "_" })
    }

    /// "pt-PT" → "Portuguese (Portugal)".
    public static func name(of language: String, locale: Locale = .current) -> String {
        locale.localizedString(forIdentifier: language) ?? language
    }
}
