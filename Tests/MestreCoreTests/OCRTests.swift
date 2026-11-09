import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
@testable import MestreCore

@Suite struct TextRecognitionTests {
    @Test func joiningKeepsOrFoldsLineBreaks() {
        let lines = ["Invoice 2024", "Total:   42 EUR"]  // as `lines(in:)` returns them: trimmed, none empty
        #expect(TextRecognition.join(lines, keepLineBreaks: true) == "Invoice 2024\nTotal:   42 EUR")
        #expect(TextRecognition.join(lines, keepLineBreaks: false) == "Invoice 2024 Total: 42 EUR")
        #expect(TextRecognition.join([], keepLineBreaks: true).isEmpty)
    }

    @Test func largeImagesAreScaledToThePixelCap() {
        #expect(TextRecognition.scaledLongSide(width: 1000, height: 1000, maxPixels: 2_000_000) == nil)
        let side = TextRecognition.scaledLongSide(width: 8000, height: 4000, maxPixels: 8_000_000)
        #expect(side == 4000)  // 4000 × 2000 = 8 M
    }

    @Test func configDefaultsAndBounds() throws {
        let defaults = Config().ocr
        #expect(defaults.enabled && defaults.clipboardImages && defaults.keepLineBreaks)
        #expect(defaults.languages.isEmpty && defaults.recognitionLevel == .accurate && defaults.maxImagePixels == 16_000_000)
        let json = #"{"ocr": {"recognitionLevel": "FAST", "languages": [" en-US ", ""], "maxImagePixels": 5, "clipboardImages": false}}"#
        let ocr = try JSONDecoder().decode(Config.self, from: Data(json.utf8)).ocr
        #expect(ocr.recognitionLevel == .fast && ocr.languages == ["en-US"] && ocr.maxImagePixels == 250_000)
        #expect(!ocr.readsClipboardImages && ocr.enabled)
        let unknown = try JSONDecoder().decode(Config.self, from: Data(#"{"ocr": {"recognitionLevel": "best"}}"#.utf8)).ocr
        #expect(unknown.recognitionLevel == .accurate)
        let round = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(Config()))
        #expect(round.ocr == defaults)
    }

    /// Vision runs headless: render text into a bitmap and read it back.
    @Test func readsTextRenderedIntoAnImage() throws {
        let image = try #require(Self.render(["Mestre reads this", "Second line 42"]))
        let lines = try TextRecognition.lines(in: image, settings: Config.OCR())
        let joined = TextRecognition.join(lines, keepLineBreaks: true).lowercased()
        #expect(joined.contains("mestre reads this"))
        #expect(joined.contains("second line 42"))
        #expect(lines.count == 2)

        var english = Config.OCR()
        english.languages = ["en-US", "xx-NOPE"]
        english.recognitionLevel = .fast
        #expect(try TextRecognition.lines(in: image, settings: english).joined(separator: " ").lowercased().contains("mestre"))
    }

    @Test func loadsAndScalesAnImageFile() throws {
        let image = try #require(Self.render(["Scaled"]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mestre-ocr-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let full = try #require(TextRecognition.image(at: url, maxPixels: 100_000_000))
        #expect(full.width == image.width)
        let small = try #require(TextRecognition.image(at: url, maxPixels: image.width * image.height / 4))
        #expect(small.width * small.height <= image.width * image.height / 4 + image.width)
        let junk = url.deletingPathExtension().appendingPathExtension("junk.png")
        defer { try? FileManager.default.removeItem(at: junk) }
        try Data([1, 2, 3]).write(to: junk)
        #expect(TextRecognition.image(at: junk, maxPixels: 1000) == nil)
        #expect(try TextRecognition.lines(at: junk, settings: Config.OCR()) == nil)
        #expect(try TextRecognition.lines(at: url, settings: Config.OCR())?.first?.lowercased() == "scaled")
    }

    @Test func storedTextIsCutAtABytesLimitOnACharacterBoundary() {
        #expect("abc".prefix(utf8Bytes: 10) == "abc")
        #expect("ação".prefix(utf8Bytes: 2) == "a")  // ç is two bytes: "aç" would be three
        #expect("日本語".prefix(utf8Bytes: 7) == "日本")
        #expect("x".prefix(utf8Bytes: 0).isEmpty)
    }

    static func render(_ lines: [String], width: Int = 900, lineHeight: Int = 80) -> CGImage? {
        let height = lineHeight * (lines.count + 1)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 40, nil)
        for (index, text) in lines.enumerated() {
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ])
            context.textPosition = CGPoint(x: 30, y: height - lineHeight * (index + 1))
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        return context.makeImage()
    }
}

@Suite struct ClipboardImageTextTests {
    let name = String(repeating: "a", count: 64) + ".png"

    func image(_ text: String? = nil) -> ClipboardEntry {
        ClipboardEntry(kind: .image, content: name, sourceApp: "Preview", copiedAt: Date(timeIntervalSince1970: 10), recognizedText: text)
    }

    @Test func oldFilesDecodeAndTheTextRoundTrips() throws {
        let old = #"{"entries":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"image","content":"\#(name)","copiedAt":0}]}"#
        let decoded = try JSONDecoder().decode(ClipboardHistory.self, from: Data(old.utf8))
        #expect(decoded.entries.first?.recognizedText == nil)
        #expect(decoded.imagesAwaitingText == [name])

        var history = decoded
        let stored = history.setRecognizedText("Boarding pass\nGate 12", forImage: name)
        let storedForMissing = history.setRecognizedText("x", forImage: "missing.png")
        #expect(stored && !storedForMissing)
        let data = try JSONEncoder().encode(history)
        #expect(String(decoding: data, as: UTF8.self).contains(#""text":"Boarding pass\nGate 12""#))
        let round = try JSONDecoder().decode(ClipboardHistory.self, from: data)
        #expect(round == history)
        #expect(round.imagesAwaitingText.isEmpty)
    }

    @Test func emptyTextMeansReadOnceWithNothingFound() throws {
        var history = ClipboardHistory(entries: [image()])
        history.setRecognizedText("", forImage: name)
        #expect(history.imagesAwaitingText.isEmpty)
        #expect(history.entries[0].recognizedSnippet == nil)
        let round = try JSONDecoder().decode(ClipboardHistory.self, from: JSONEncoder().encode(history))
        #expect(round.entries[0].recognizedText == "")
    }

    @Test func searchFindsWordsInTheImageText() {
        let deep = String(repeating: "filler words ", count: 60) + "Zanzibar"  // past the fuzzy head
        var history = ClipboardHistory()
        history.add(ClipboardEntry(kind: .text, content: "meeting notes", sourceApp: nil), limit: 10)
        history.add(image("Invoice 2024 TOTAL 42\n" + deep), limit: 10)
        #expect(history.matching("total 42", limit: 5).map(\.kind) == [.image])
        #expect(history.matching("zanzibar", limit: 5).map(\.kind) == [.image])
        #expect(history.matching("meeting", limit: 5).map(\.kind) == [.text])

        // Decomposed text and a precomposed query (or the other way round) still meet.
        let decomposed = ClipboardHistory(entries: [image("Cafe\u{301} Lisboa")])
        #expect(decomposed.matching("café", limit: 5).count == 1)
        #expect(ClipboardHistory(entries: [image("Café")]).matching("cafe\u{301}", limit: 5).count == 1)
    }

    /// 500 screenshots full of text, the word near the end of each: the substring pass reads
    /// 4 000 characters of every entry (the fuzzy pass, untouched, only the 400-character head).
    @Test func searchingTheTextOfAFullHistoryOfScreenshotsStaysFast() {
        let page = (0..<400).map { "word\($0) " }.joined()
        let entries = (0..<500).map { index in
            ClipboardEntry(kind: .image, content: String(format: "%064x", index) + ".png", sourceApp: nil, recognizedText: page)
        }
        let history = ClipboardHistory(entries: entries)
        let queries = ["word399", "word398 word399"]
        let start = Date()
        for query in queries { #expect(history.matching(query, limit: 20).count == 20) }
        let perQuery = Date().timeIntervalSince(start) / Double(queries.count)
        print("substring search over 500 OCR'd images: \(perQuery) seconds per query")
        #expect(perQuery < 0.005, "the keystroke budget, even in a debug build")
        #expect(ClipboardEntry.bytes("ação total", contain: "ção") && !ClipboardEntry.bytes("abc", contain: "abd"))
        #expect(ClipboardEntry.bytes("", contain: "") && !ClipboardEntry.bytes("", contain: "a"))
    }

    @Test func textAndFileEntriesIgnoreRecognizedText() {
        var text = ClipboardEntry(kind: .text, content: "hello", sourceApp: nil, recognizedText: "nope")
        text.setRecognizedText("still nope")
        #expect(text.recognizedText == nil && text.searchText == "hello")
    }

    @Test func snippetIsOneShortLine() {
        #expect(image("Line one\n\n  line   two").recognizedSnippet == "Line one line two")
        let long = image(String(repeating: "word ", count: 40)).recognizedSnippet ?? ""
        #expect(long.count == 61 && long.hasSuffix("…"))
    }
}
