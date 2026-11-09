import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Reads the text in an image with Vision, on this Mac. Blocking and CPU-heavy: call it off
/// the main thread.
public enum TextRecognition {
    /// The recognised lines, top to bottom as Vision orders them, trimmed, empty ones dropped.
    public static func lines(in image: CGImage, settings: Config.OCR) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = settings.recognitionLevel == .fast ? .fast : .accurate
        request.usesLanguageCorrection = true
        // Codes Vision doesn't know would make the request fail; unknown ones fall back to detection.
        let wanted: [String]
        if settings.languages.isEmpty {
            wanted = []
        } else {
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            wanted = settings.languages.filter { code in supported.contains { $0.caseInsensitiveCompare(code) == .orderedSame } }
        }
        if wanted.isEmpty {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = wanted
        }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Lines from `lines(in:)` as one string: one per line, or joined by single spaces.
    public static func join(_ lines: [String], keepLineBreaks: Bool) -> String {
        if keepLineBreaks { return lines.joined(separator: "\n") }
        return lines.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The lines in the image file at `url`; nil when it can't be read as an image.
    public static func lines(at url: URL, settings: Config.OCR) throws -> [String]? {
        guard let image = image(at: url, maxPixels: settings.maxImagePixels) else { return nil }
        return try lines(in: image, settings: settings)
    }

    /// The image at `url`, upright, scaled down to at most `maxPixels` pixels (aspect kept).
    public static func image(at url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else { return nil }
        let scaled = scaledLongSide(width: width, height: height, maxPixels: maxPixels)
        let rotated = (properties[kCGImagePropertyOrientation] as? Int).map { $0 != 1 } ?? false
        guard scaled != nil || rotated else { return CGImageSourceCreateImageAtIndex(source, 0, nil) }
        // The thumbnail path also applies the EXIF orientation, which Vision isn't told about.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: scaled ?? max(width, height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The long side that brings `width × height` within `maxPixels`; nil when it already fits.
    static func scaledLongSide(width: Int, height: Int, maxPixels: Int) -> Int? {
        let area = Double(width) * Double(height)
        guard area > Double(max(1, maxPixels)) else { return nil }
        let scale = (Double(max(1, maxPixels)) / area).squareRoot()
        return max(1, Int(Double(max(width, height)) * scale))
    }
}

public extension String {
    /// The longest whole-character head that fits in `maxBytes` of UTF-8.
    func prefix(utf8Bytes maxBytes: Int) -> String {
        guard utf8.count > maxBytes else { return self }
        var end = utf8.index(utf8.startIndex, offsetBy: max(0, maxBytes))
        while end > startIndex, String.Index(end, within: self) == nil { end = utf8.index(before: end) }
        return String(self[..<end])
    }
}
