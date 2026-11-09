import Foundation

/// DateFormatters cost more to build than to use, and agenda rows and time answers ask for them
/// on every keystroke: one shared cache, keyed by everything that shapes the output. A formatter
/// is never changed once cached, so using one from any thread is safe.
enum DateFormatters {
    private static let cache = NSCache<NSString, DateFormatter>()

    /// A localized format from `template` ("EEEdMMM", "jm"). Without `calendar`, the locale's own.
    static func template(_ template: String, locale: Locale, timeZone: TimeZone, calendar: Calendar? = nil) -> DateFormatter {
        let key = "t|\(template)|\(locale.identifier)|\(calendar.map { "\($0.identifier)" } ?? "-")|\(timeZone.identifier)"
        return cached(key) { formatter in
            if let calendar { formatter.calendar = calendar }
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
        }
    }

    /// A fixed, locale-independent format ("yyyy-MM-dd") in the Gregorian calendar.
    static func fixed(_ format: String, timeZone: TimeZone) -> DateFormatter {
        cached("f|\(format)|\(timeZone.identifier)") { formatter in
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = format
            formatter.timeZone = timeZone
        }
    }

    private static func cached(_ key: String, make: (DateFormatter) -> Void) -> DateFormatter {
        if let formatter = cache.object(forKey: key as NSString) { return formatter }
        let formatter = DateFormatter()
        make(formatter)
        cache.setObject(formatter, forKey: key as NSString)
        return formatter
    }
}
