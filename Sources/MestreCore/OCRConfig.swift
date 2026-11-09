import Foundation

public extension Config {
    /// Text recognition, on this Mac with Vision: the Copy Text from Screen command and the
    /// text in images that enter clipboard history.
    struct OCR: Codable, Equatable, Sendable {
        public enum Level: String, Codable, CaseIterable, Sendable { case accurate, fast }

        /// Off hides Copy Text from Screen and stops reading copied images.
        public var enabled: Bool = true
        /// Read the text in images copied to the clipboard, once per entry, in the background, so
        /// typing a word from a screenshot finds it. On by default: it runs on this Mac only, at
        /// background priority, only for images history already keeps, and the text is stored
        /// beside the image it came from and deleted with it.
        public var clipboardImages: Bool = true
        /// Recognition languages, e.g. ["en-US", "pt-BR"]. Empty detects the language.
        public var languages: [String] = []
        /// "accurate" (default) or "fast".
        public var recognitionLevel: Level = .accurate
        /// Copy Text from Screen keeps the lines as they were; false joins them with spaces.
        public var keepLineBreaks: Bool = true
        /// Larger images are scaled down to this many pixels before reading, which bounds the work.
        public var maxImagePixels: Int = 16_000_000
        /// How long Copy Text from Screen's message ("Copied 3 lines") stays near the bottom of the
        /// screen. Its own key: the panel is closed by then, so `panel.toastSeconds` doesn't apply.
        public var hudSeconds: Double = 2

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, clipboardImages, languages, recognitionLevel, keepLineBreaks, maxImagePixels, hudSeconds }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            clipboardImages = try c.decodeIfPresent(Bool.self, forKey: .clipboardImages) ?? clipboardImages
            languages = (try c.decodeIfPresent([String].self, forKey: .languages) ?? languages)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            recognitionLevel = c.decodeChoice(forKey: .recognitionLevel) ?? recognitionLevel
            keepLineBreaks = try c.decodeIfPresent(Bool.self, forKey: .keepLineBreaks) ?? keepLineBreaks
            maxImagePixels = min(100_000_000, max(250_000, try c.decodeIfPresent(Int.self, forKey: .maxImagePixels) ?? maxImagePixels))
            hudSeconds = max(0, try c.decodeIfPresent(Double.self, forKey: .hudSeconds) ?? hudSeconds)
        }

        /// Whether copied images get their text read.
        public var readsClipboardImages: Bool { enabled && clipboardImages }
    }
}
