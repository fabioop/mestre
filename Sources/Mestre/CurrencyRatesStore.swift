import Foundation
import MestreCore

/// Exchange rates for the calculator: read from disk the first time they are asked for, downloaded
/// when missing or old. Nothing happens until someone types a currency conversion.
@MainActor
final class CurrencyRatesStore {
    private(set) var rates: CurrencyRates?
    /// The last download failed; the calculator says so instead of "Fetching…".
    private(set) var failed = false
    var onChange: (() -> Void)?

    private let file: URL
    private var loadedFromDisk = false
    private var isBusy = false
    private var lastAttempt: Date?
    /// A failed download isn't retried on every keystroke, but soon enough that coming back
    /// online or fixing `ratesURL` shows rates within minutes.
    private let retryInterval: TimeInterval = 300
    private var lastURL: String?

    nonisolated static let defaultFile = AppSupport.folder.appendingPathComponent("currency-rates.json")

    init(file: URL = CurrencyRatesStore.defaultFile) {
        self.file = file
    }

    /// Called from the keystroke path, so it only starts work and returns.
    func refreshIfNeeded(settings: Config.Calculator) {
        guard !isBusy else { return }
        if settings.ratesURL != lastURL {
            // Another source: a failure of the old one doesn't hold this one back. The old rates stay
            // until the new ones arrive (`isStale` sees the other source), as they would after a relaunch.
            lastAttempt = nil
            lastURL = settings.ratesURL
        }
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < retryInterval { return }
        if loadedFromDisk, let rates, !rates.isStale(maxAgeHours: settings.ratesMaxAgeHours, source: settings.ratesURL) { return }
        isBusy = true
        let file = file
        let urlText = settings.ratesURL
        let maxAge = settings.ratesMaxAgeHours
        let needsDisk = !loadedFromDisk
        Task {
            if needsDisk {
                let cached = await Task.detached(priority: .utility) { Self.read(file) }.value
                loadedFromDisk = true
                if let cached {
                    rates = cached
                    onChange?()
                }
            }
            if rates?.isStale(maxAgeHours: maxAge, source: urlText) ?? true {
                lastAttempt = Date()
                let fresh = await Task.detached(priority: .utility, operation: { await Self.download(urlText, to: file) }).value
                if let fresh {
                    rates = fresh
                    lastAttempt = nil
                }
                failed = fresh == nil
                onChange?()
            }
            isBusy = false
        }
    }

    private nonisolated static func read(_ file: URL) -> CurrencyRates? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(CurrencyRates.self, from: data)
    }

    /// No cookies or on-disk response cache, and a short timeout: the rates file is a few KB.
    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()
    private nonisolated static let maxResponseBytes = 1_000_000

    private nonisolated static func download(_ urlText: String, to file: URL) async -> CurrencyRates? {
        guard let url = URL(string: urlText), let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= maxResponseBytes,
              var parsed = CurrencyRates.parse(String(decoding: data, as: UTF8.self)) else { return nil }
        parsed.source = urlText
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(parsed).write(to: file, options: .atomic)
        return parsed
    }
}
