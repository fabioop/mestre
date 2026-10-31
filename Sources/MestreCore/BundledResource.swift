import Foundation

/// A file that ships with the app. In the .app it sits in Contents/Resources (the bundle script
/// puts it there); under `swift test` and `swift run` it comes from SwiftPM's module bundle.
enum BundledResource {
    /// `Bundle.module` traps when its bundle is missing, which is always the case in an installed
    /// .app, so it is only asked outside one. A missing file is nil, never a crash.
    static func url(forResource name: String, withExtension type: String) -> URL? {
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: type),
            Bundle.main.bundleURL.appendingPathComponent("Mestre_MestreCore.bundle/\(name).\(type)"),
        ].compactMap { $0 }
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) { return found }
        guard Bundle.main.bundleURL.pathExtension != "app" else { return nil }
        return Bundle.module.url(forResource: name, withExtension: type)
    }
}
