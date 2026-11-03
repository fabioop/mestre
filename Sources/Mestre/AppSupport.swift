import Foundation

/// Where Mestre keeps its data (clipboard history, caches): ~/Library/Application Support/Mestre.
enum AppSupport {
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mestre")

    /// Creates `url` owner-only, or tightens it if an older build made it readable by others.
    static func makePrivateFolder(_ url: URL) {
        let manager = FileManager.default
        try? manager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    /// Replaces `url` with `data`, owner-only from the first byte: a 0600 temporary file renamed
    /// over it. `Data.write(options: .atomic)` makes its temporary file with the umask (0644), and
    /// a chmod afterwards leaves a moment when other accounts could read it.
    static func writePrivately(_ data: Data, to url: URL) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        do {
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            try handle.write(contentsOf: data)
            try handle.close()
            guard rename(temp.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            unlink(temp.path)
            throw error
        }
    }
}
