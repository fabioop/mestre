import AppKit
import ApplicationServices
import Combine
import MestreCore

/// Sends play/pause, next and previous, and keeps track of what Music and Spotify are playing.
///
/// Controls go out as system media key events (what the keyboard's ⏯ ⏭ ⏮ send, so any app that
/// owns Now Playing reacts: Music, Spotify, a browser tab, Podcasts). Posting events needs the
/// Accessibility permission, asked on the first control. `media.method: "player"` sends Apple
/// Events to the running player instead (Automation consent, once per player).
///
/// Now-playing comes from each player's distributed notification, so nothing is polled and the
/// app sits at 0 % CPU between tracks. A player that was already playing before Mestre started
/// has said nothing yet; it is asked once, by Apple Event, when the keyword is typed. Nothing
/// here ever launches a player: every script is guarded by `is running`.
@MainActor
final class MediaController: NSObject {
    enum Outcome { case sent, needsPermission, noPlayer }

    /// Only what changes listening re-registers observers: not a keyword typed in Settings.
    var settings = Config.Media() {
        didSet {
            let listening = { (media: Config.Media) in [media.enabled, media.nowPlaying] }
            if !configured || listening(settings) != listening(oldValue) || settings.players != oldValue.players { reconfigure() }
        }
    }
    /// Called on the main thread when a player's state or track changes.
    var onChange: (() -> Void)?

    private(set) var players: [MediaPlayer] = []
    private var states: [String: NowPlaying] = [:]
    /// Configured players that are running, kept by the shared `RunningAppsMonitor`.
    private var running: Set<String> = []
    private let runningApps: RunningAppsMonitor
    private var runningSubscription: AnyCancellable?
    /// Players asked by Apple Event since they launched, so the query runs once per run.
    private var asked: Set<String> = []
    /// Nothing is registered until the config's settings arrive.
    private var configured = false
    private var askedForAccess = false

    init(runningApps: RunningAppsMonitor) {
        self.runningApps = runningApps
        super.init()
    }

    /// The player to show and to control; nil when none is known to be playing or paused.
    var current: NowPlaying? {
        settings.nowPlaying ? NowPlaying.current(in: states, order: players.map(\.bundleID), running: running) : nil
    }

    /// Only the now-playing row asks, for a player that is running.
    func icon(for bundleID: String) -> NSImage? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.icon
    }

    func name(of bundleID: String) -> String {
        players.first { $0.bundleID == bundleID }?.name ?? bundleID
    }

    func send(_ control: MediaControl) -> Outcome {
        switch settings.method {
        case .keys:
            guard Accessibility.isTrusted else {
                // Once per run: after the first press the toast says where to allow it.
                if !askedForAccess { askedForAccess = true; Accessibility.requestAccess() }
                return .needsPermission
            }
            Self.postMediaKey(control)
            return .sent
        case .player:
            let now = current?.bundleID
            guard let player = players.first(where: { $0.bundleID == now }) ?? players.first(where: { running.contains($0.bundleID) }) else { return .noPlayer }
            ProcessRunner.run("/usr/bin/osascript", ["-e", player.script(for: control)], label: "Media \(control.rawValue)")
            return .sent
        }
    }

    /// Asks each running player that hasn't said anything yet, once, off the main thread.
    func askSilentPlayers() {
        guard settings.enabled, settings.nowPlaying else { return }
        for player in players where running.contains(player.bundleID) && states[player.bundleID] == nil && !asked.contains(player.bundleID) {
            asked.insert(player.bundleID)
            let script = player.nowPlayingScript
            let id = player.bundleID
            Task { [weak self] in
                // Off the main thread; long timeout: the first run waits on the Automation consent dialog.
                let output = await Task.detached(priority: .userInitiated) {
                    ProcessRunner.output("/usr/bin/osascript", ["-e", script], timeout: 60)
                }.value
                guard let self, let output, let state = NowPlaying(scriptOutput: output.trimmingCharacters(in: .newlines), bundleID: id),
                      self.states[id] == nil, self.running.contains(id) else { return }
                self.update(state)
            }
        }
    }

    // MARK: Media keys

    /// One press and release of a media key, as the keyboard sends it: an NSSystemDefined event,
    /// subtype 8 (NX_SUBTYPE_AUX_CONTROL_BUTTONS), key type in the high half of data1 and
    /// 0xA (down) or 0xB (up) in the next byte.
    private static func postMediaKey(_ control: MediaControl) {
        for down in [true, false] {
            let code = down ? 0xA : 0xB
            let flags = NSEvent.ModifierFlags(rawValue: UInt(code << 8))
            let data1 = Int(control.keyType) << 16 | code << 8
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                           windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Listening

    private func reconfigure() {
        configured = true
        players = MediaPlayer.players(for: settings.players)
        // While nothing listens the states go stale, so they and the one-off queries start over.
        let ids = Set(players.map(\.bundleID))
        let heard = settings.enabled && settings.nowPlaying ? ids : []
        states = states.filter { heard.contains($0.key) }
        asked = asked.filter(heard.contains)
        stopListening()
        guard settings.enabled else { running = []; return }
        running = runningApps.identifiers.intersection(ids)
        // dropFirst: `running` was just set from the current value.
        runningSubscription = runningApps.$identifiers.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] identifiers in
            MainActor.assumeIsolated { self?.runningChanged(identifiers) }
        }
        guard settings.nowPlaying else { return }
        // Deliver immediately: Mestre is almost never the active app, and the default behaviour
        // holds notifications back until it is.
        let distributed = DistributedNotificationCenter.default()
        for player in players {
            distributed.addObserver(self, selector: #selector(playerChanged(_:)), name: Notification.Name(player.notification), object: nil, suspensionBehavior: .deliverImmediately)
        }
    }

    private func stopListening() {
        runningSubscription = nil
        DistributedNotificationCenter.default().removeObserver(self)
    }

    /// A player that quit forgets its state and gets asked again on its next run.
    private func runningChanged(_ identifiers: Set<String>) {
        let now = identifiers.intersection(players.map(\.bundleID))
        guard now != running else { return }
        var forgot = false
        for id in running.subtracting(now) {
            asked.remove(id)
            if states.removeValue(forKey: id) != nil { forgot = true }
        }
        // A player heard from just before its launch was noticed shows only now.
        let shown = now.subtracting(running).contains { states[$0] != nil }
        running = now
        if forgot || shown { onChange?() }
    }

    @objc private func playerChanged(_ note: Notification) {
        guard let player = players.first(where: { $0.notification == note.name.rawValue }),
              let state = NowPlaying(notification: note.userInfo ?? [:], bundleID: player.bundleID) else { return }
        update(state)
    }

    private func update(_ state: NowPlaying) {
        if let old = states[state.bundleID], old.sameTrackAndState(as: state) { return }
        states[state.bundleID] = state
        onChange?()
    }
}
