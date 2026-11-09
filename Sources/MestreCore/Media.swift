import Foundation

/// One of the controls a media key sends.
public enum MediaControl: String, CaseIterable, Sendable {
    case playPause, next, previous

    /// `NX_KEYTYPE_*` from IOKit's ev_keymap.h: the code inside a system-defined media key event.
    public var keyType: Int32 {
        switch self {
        case .playPause: return 16 // NX_KEYTYPE_PLAY
        case .next: return 17 // NX_KEYTYPE_NEXT
        case .previous: return 18 // NX_KEYTYPE_PREVIOUS
        }
    }

    /// The Music and Spotify AppleScript command for this control.
    public var scriptCommand: String {
        switch self {
        case .playPause: return "playpause"
        case .next: return "next track"
        case .previous: return "previous track"
        }
    }

    /// Row title; the play/pause row says what pressing it does when the state is known.
    public func title(state: MediaPlayerState?) -> String {
        switch self {
        case .playPause:
            switch state {
            case .playing: return "Pause"
            case .paused, .stopped: return "Play"
            case nil: return "Play/Pause"
            }
        case .next: return "Next Track"
        case .previous: return "Previous Track"
        }
    }

    /// SF Symbol.
    public func symbol(state: MediaPlayerState?) -> String {
        switch self {
        case .playPause:
            switch state {
            case .playing: return "pause.fill"
            case .paused, .stopped: return "play.fill"
            case nil: return "playpause.fill"
            }
        case .next: return "forward.fill"
        case .previous: return "backward.fill"
        }
    }

    /// The words that reach this control in an ordinary search ("play", "next").
    public func words(in settings: Config.Media) -> [String] {
        switch self {
        case .playPause: return settings.playPauseWords
        case .next: return settings.nextWords
        case .previous: return settings.previousWords
        }
    }
}

public enum MediaPlayerState: String, Sendable {
    case playing, paused, stopped

    /// "Playing", "paused", "stopped" in any case, as notifications and `player state as text`
    /// spell it; nil for anything else (fast forwarding, rewinding).
    public init?(text: String) {
        self.init(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

/// A player Mestre knows how to listen to: its bundle id and the distributed notification it
/// posts on every track or state change, so now-playing needs no polling.
public struct MediaPlayer: Equatable, Sendable {
    public let bundleID: String
    public let name: String
    public let notification: String

    public static let known: [MediaPlayer] = [
        MediaPlayer(bundleID: "com.apple.Music", name: "Music", notification: "com.apple.Music.playerInfo"),
        MediaPlayer(bundleID: "com.spotify.client", name: "Spotify", notification: "com.spotify.client.PlaybackStateChanged"),
    ]

    /// The known players among `bundleIDs`, in the user's order; unknown ids are dropped.
    public static func players(for bundleIDs: [String]) -> [MediaPlayer] {
        var seen: Set<String> = []
        return bundleIDs.compactMap { id in
            guard let player = known.first(where: { $0.bundleID.caseInsensitiveCompare(id) == .orderedSame }), seen.insert(player.bundleID).inserted else { return nil }
            return player
        }
    }

    /// Reads the player's state and track without launching it (the `is running` guard).
    /// Prints the state, then name, artist and album on their own lines.
    public var nowPlayingScript: String {
        """
        if application id "\(bundleID)" is running then
            tell application id "\(bundleID)"
                set s to (player state as text)
                try
                    return s & linefeed & (name of current track) & linefeed & (artist of current track) & linefeed & (album of current track)
                on error
                    return s
                end try
            end tell
        end if
        """
    }

    /// Sends one control by Apple Event, again only when the player is already running.
    public func script(for control: MediaControl) -> String {
        "if application id \"\(bundleID)\" is running then tell application id \"\(bundleID)\" to \(control.scriptCommand)"
    }
}

/// What one player is doing, from its notification or from a one-off Apple Event query.
public struct NowPlaying: Equatable, Sendable {
    public let bundleID: String
    public let state: MediaPlayerState
    public let track: String?
    public let artist: String?
    public let album: String?
    public let updated: Date

    public init(bundleID: String, state: MediaPlayerState, track: String? = nil, artist: String? = nil, album: String? = nil, updated: Date = Date()) {
        self.bundleID = bundleID
        self.state = state
        self.track = Self.clean(track)
        self.artist = Self.clean(artist)
        self.album = Self.clean(album)
        self.updated = updated
    }

    /// From a `com.apple.Music.playerInfo` or `com.spotify.client.PlaybackStateChanged` userInfo.
    public init?(notification userInfo: [AnyHashable: Any], bundleID: String, now: Date = Date()) {
        guard let raw = userInfo["Player State"] as? String, let state = MediaPlayerState(text: raw) else { return nil }
        self.init(bundleID: bundleID, state: state, track: userInfo["Name"] as? String, artist: userInfo["Artist"] as? String,
                  album: userInfo["Album"] as? String, updated: now)
    }

    /// From what `MediaPlayer.nowPlayingScript` printed; nil when the player wasn't running.
    public init?(scriptOutput: String, bundleID: String, now: Date = Date()) {
        let lines = scriptOutput.components(separatedBy: "\n")
        guard let first = lines.first, let state = MediaPlayerState(text: first) else { return nil }
        func line(_ index: Int) -> String? { index < lines.count ? lines[index] : nil }
        self.init(bundleID: bundleID, state: state, track: line(1), artist: line(2), album: line(3), updated: now)
    }

    /// Equal apart from when it was heard: nothing on screen would change.
    public func sameTrackAndState(as other: NowPlaying) -> Bool {
        bundleID == other.bundleID && state == other.state && track == other.track && artist == other.artist && album == other.album
    }

    /// "Track — Artist", or whichever of the two is known.
    public var title: String? {
        let parts = [track, artist].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    /// The player to show and control: the first playing one in `order`, else the most recently
    /// changed one that still has a track. Only players in `running` count.
    public static func current(in states: [String: NowPlaying], order: [String], running: Set<String>) -> NowPlaying? {
        let live = order.compactMap { states[$0] }.filter { running.contains($0.bundleID) }
        if let playing = live.first(where: { $0.state == .playing }) { return playing }
        return live.filter { $0.track != nil && $0.state != .stopped }.max { $0.updated < $1.updated }
    }

    private static func clean(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
