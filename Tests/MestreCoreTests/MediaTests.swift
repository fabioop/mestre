import Foundation
import Testing
@testable import MestreCore

@Suite struct MediaTests {
    @Test func configDefaultsAndCleanup() throws {
        let defaults = Config().media
        #expect(defaults.enabled && defaults.nowPlaying && defaults.closeOnControl && defaults.searchEverywhere)
        #expect(defaults.keyword == "media" && defaults.method == .keys)
        #expect(defaults.players == ["com.apple.Music", "com.spotify.client"])
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"media": {"keyword": "Tunes now", "method": "PLAYER", "nextWords": [" Skip ", ""], "nowPlaying": false}}"#.utf8))
        #expect(config.media.keyword == "tunes")
        #expect(config.media.method == .player)
        #expect(config.media.nextWords == ["skip"])
        #expect(!config.media.nowPlaying && config.media.previousWords == ["previous", "prev"])
        let roundTrip = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(roundTrip.media == config.media)
    }

    @Test func eachControlHasItsWords() {
        let settings = Config.Media()
        #expect(MediaControl.previous.words(in: settings) == ["previous", "prev"])
        #expect(MediaControl.playPause.words(in: settings) == ["play", "pause"])
        #expect(MediaControl.next.words(in: settings) == ["next"])
    }

    @Test func titlesFollowTheState() {
        #expect(MediaControl.playPause.title(state: .playing) == "Pause")
        #expect(MediaControl.playPause.title(state: .paused) == "Play")
        #expect(MediaControl.playPause.title(state: nil) == "Play/Pause")
        #expect(MediaControl.next.keyType == 17 && MediaControl.previous.keyType == 18 && MediaControl.playPause.keyType == 16)
    }

    @Test func knownPlayersOnlyInTheUsersOrder() {
        let players = MediaPlayer.players(for: ["com.spotify.client", "com.example.unknown", "COM.APPLE.MUSIC", "com.spotify.client"])
        #expect(players.map(\.bundleID) == ["com.spotify.client", "com.apple.Music"])
        #expect(players[0].script(for: .next).contains("is running then tell application id \"com.spotify.client\" to next track"))
        #expect(players[1].nowPlayingScript.hasPrefix("if application id \"com.apple.Music\" is running"))
    }

    @Test func readsNotificationsAndScriptOutput() {
        let note: [AnyHashable: Any] = ["Player State": "Playing", "Name": "Song", "Artist": "Band", "Album": " "]
        let playing = NowPlaying(notification: note, bundleID: "com.spotify.client")
        #expect(playing?.state == .playing && playing?.title == "Song — Band" && playing?.album == nil)
        #expect(NowPlaying(notification: ["Player State": "Rewinding"], bundleID: "x") == nil)
        #expect(NowPlaying(notification: [:], bundleID: "x") == nil)

        let script = NowPlaying(scriptOutput: "paused\nSong\nBand\nRecord", bundleID: "com.apple.Music")
        #expect(script?.state == .paused && script?.album == "Record")
        let stopped = NowPlaying(scriptOutput: "stopped", bundleID: "com.apple.Music")
        #expect(stopped?.state == .stopped && stopped?.title == nil)
        #expect(NowPlaying(scriptOutput: "", bundleID: "com.apple.Music") == nil)
    }

    @Test func currentPrefersPlayingThenTheLatestPaused() {
        let old = Date(timeIntervalSince1970: 0), new = Date(timeIntervalSince1970: 100)
        let music = NowPlaying(bundleID: "m", state: .paused, track: "A", updated: new)
        let spotify = NowPlaying(bundleID: "s", state: .paused, track: "B", updated: old)
        let order = ["s", "m"]
        #expect(NowPlaying.current(in: ["m": music, "s": spotify], order: order, running: ["m", "s"])?.bundleID == "m")
        let spotifyPlaying = NowPlaying(bundleID: "s", state: .playing, track: "B", updated: old)
        #expect(NowPlaying.current(in: ["m": music, "s": spotifyPlaying], order: order, running: ["m", "s"])?.bundleID == "s")
        #expect(NowPlaying.current(in: ["m": music, "s": spotifyPlaying], order: order, running: ["m"])?.bundleID == "m")
        let stopped = NowPlaying(bundleID: "m", state: .stopped, track: "A")
        #expect(NowPlaying.current(in: ["m": stopped], order: order, running: ["m"]) == nil)
        #expect(music.sameTrackAndState(as: NowPlaying(bundleID: "m", state: .paused, track: "A", updated: old)))
    }
}
