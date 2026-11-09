import Foundation

extension Config {
    /// Script commands: a folder of scripts in Raycast's Script Commands format, as results.
    public struct Scripts: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// First word that lists every script and runs one with arguments: "script search github swift".
        public var keyword: String = "script"
        /// Folders whose scripts are listed (not their subfolders). "~" is expanded.
        public var directories: [String] = ["~/.config/mestre/scripts"]
        /// Script titles also rank in ordinary searches, like apps.
        public var searchEverywhere: Bool = true
        /// A run past this many seconds is stopped.
        public var timeoutSeconds: Double = 30
        /// Folders put before PATH for scripts, which otherwise get only the system folders.
        public var extraPath: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]
        /// App that Edit Script opens a script in: a bundle identifier or an app path; empty uses
        /// the default text editor, never the app that would run the script.
        public var editor: String = ""
        /// How long the HUD shown after the panel has closed stays up.
        public var hudSeconds: Double = 2

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, keyword, directories, searchEverywhere, timeoutSeconds, extraPath, editor, hudSeconds }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            keyword = try c.decodeKeyword(forKey: .keyword, default: keyword)
            directories = (try c.decodeIfPresent([String].self, forKey: .directories) ?? directories)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            searchEverywhere = try c.decodeIfPresent(Bool.self, forKey: .searchEverywhere) ?? searchEverywhere
            timeoutSeconds = max(1, try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? timeoutSeconds)
            extraPath = try c.decodeIfPresent([String].self, forKey: .extraPath) ?? extraPath
            editor = (try c.decodeIfPresent(String.self, forKey: .editor) ?? editor).trimmingCharacters(in: .whitespaces)
            hudSeconds = max(0, try c.decodeIfPresent(Double.self, forKey: .hudSeconds) ?? hudSeconds)
        }

        /// `directories` with "~" expanded.
        public var resolvedDirectories: [URL] {
            directories.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath).standardizedFileURL }
        }
    }
}
