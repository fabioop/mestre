import AppKit
import Combine
import IOKit.pwr_mgt
import MestreCore

/// Keeps the Mac (and, unless configured otherwise, the display) awake with a power
/// management assertion, like `caffeinate`. One session at a time: a manual
/// one (indefinite, timed or until a clock time) outranks the triggered ones (an app in
/// `whileRunningApps` running, or the Mac charging). Timed sessions end on a single
/// wall-clock timer; triggers are re-evaluated only on NSWorkspace and IOKit notifications,
/// which are installed only while a trigger is configured, so nothing polls.
@MainActor
final class KeepAwakeManager: ObservableObject {
    var settings = Config.KeepAwake() {
        didSet {
            guard settings != oldValue else { return }
            updateWatchers()
            if !settings.enabled {
                end()
                suppressedTrigger = nil  // re-enabling starts from a clean slate
                return
            }
            if settings.allowDisplaySleep != oldValue.allowDisplaySleep, session != nil {
                release()
                assert()
            }
            evaluate()
        }
    }
    @Published private(set) var session: KeepAwakeSession?

    private var assertion: IOPMAssertionID = 0
    private var timer: DispatchSourceTimer?
    private var appObservers: [NSObjectProtocol] = []
    private var wakeObserver: NSObjectProtocol?
    private var powerWatcher: PowerSourceWatcher?
    /// A trigger the user stopped by hand; it stays off until its condition changes.
    private var suppressedTrigger: KeepAwakeSession.Reason?
    /// The last reading that mattered, so a battery-percent tick doesn't re-evaluate for nothing.
    private var lastPower: PowerSource?

    // MARK: Manual sessions

    func apply(_ request: KeepAwakeRequest) {
        switch request {
        case .stop: stop()
        case .indefinite: start(KeepAwakeSession(reason: .manual, endDate: nil))
        case .duration(let seconds): start(KeepAwakeSession(reason: .manual, endDate: Date().addingTimeInterval(seconds)))
        case .until(let date): start(KeepAwakeSession(reason: .manual, endDate: date))
        }
    }

    /// Hotkey and command entry point: stops any session, else starts an indefinite one.
    func toggle() {
        session == nil ? apply(.indefinite) : stop()
    }

    /// Ends the current session. Whatever trigger currently holds stays off until it changes,
    /// otherwise stopping would do nothing while the app runs or the charger is in.
    func stop() {
        guard session != nil else { return }
        end()
        suppressedTrigger = hasTriggers ? triggerReason(power: currentPower()) : nil
        evaluate()
    }

    private func start(_ new: KeepAwakeSession) {
        guard settings.enabled else { return }
        if new.reason == .manual, settings.endWhenBatteryBelow > 0, batteryTooLow(PowerSource.current()) {
            NSSound.beep()  // the cut-off would end it on the next battery tick
            return
        }
        end()
        guard assert() else { return }
        session = new
        if let endDate = new.endDate {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(wallDeadline: .now() + endDate.timeIntervalSinceNow)
            timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.expireIfDue() } }
            timer.resume()
            self.timer = timer
            watchWake()
        }
    }

    private func end() {
        timer?.cancel()
        timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        release()
        session = nil
    }

    /// Timers don't tick while the Mac sleeps, so the end is also checked on wake. The
    /// timer can fire a hair before the end date (nanosecond rounding of the deadline),
    /// and it never fires again, so anything within a second counts as due.
    private func expireIfDue() {
        guard let endDate = session?.endDate, endDate.timeIntervalSinceNow < 1 else { return }
        end()
        evaluate()
    }

    private func watchWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.expireIfDue() }
        }
    }

    // MARK: Triggers

    private var needsPower: Bool { settings.whileCharging || settings.endWhenBatteryBelow > 0 }
    private var hasTriggers: Bool { !settings.whileRunningApps.isEmpty || needsPower }

    /// The power reading when a setting depends on it; otherwise "on AC, no battery", which
    /// makes every power rule a no-op without touching IOKit.
    private func currentPower() -> PowerSource {
        needsPower ? PowerSource.current() : PowerSource(onAC: true, batteryPercent: nil)
    }

    /// Observers exist only while the feature is on and a setting needs them.
    private func updateWatchers() {
        let center = NSWorkspace.shared.notificationCenter
        if !settings.enabled || settings.whileRunningApps.isEmpty {
            appObservers.forEach(center.removeObserver)
            appObservers = []
        } else if appObservers.isEmpty {
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                appObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.evaluate() }
                })
            }
        }
        if !settings.enabled || !needsPower {
            powerWatcher = nil
            lastPower = nil
        } else if powerWatcher == nil {
            powerWatcher = PowerSourceWatcher { [weak self] in MainActor.assumeIsolated { self?.powerChanged() } }
        }
    }

    /// IOKit also reports percent ticks and time-remaining updates; only AC state and, with a
    /// cut-off set, the percentage matter.
    private func powerChanged() {
        let power = PowerSource.current()
        let relevant = settings.endWhenBatteryBelow > 0 ? power : PowerSource(onAC: power.onAC, batteryPercent: nil)
        guard relevant != lastPower else { return }
        lastPower = relevant
        evaluate()
    }

    /// Starts or ends a triggered session according to the current state. Never touches a
    /// manual session, except to end everything when the battery is low.
    private func evaluate() {
        guard hasTriggers else {
            if session?.isTriggered == true { end() }  // its trigger was just removed from the config
            suppressedTrigger = nil
            return
        }
        let power = currentPower()
        if batteryTooLow(power) {
            if session != nil { end() }
            return
        }
        if session?.isTriggered == false { return }  // a manual session outranks the triggers
        let wanted = triggerReason(power: power)
        if wanted != suppressedTrigger { suppressedTrigger = nil }
        guard wanted != session?.reason else { return }
        if let wanted {
            if suppressedTrigger == nil { start(KeepAwakeSession(reason: wanted, endDate: nil)) }
        } else {
            end()
        }
    }

    private func batteryTooLow(_ power: PowerSource) -> Bool {
        settings.endWhenBatteryBelow > 0 && !power.onAC && (power.batteryPercent ?? 100) < settings.endWhenBatteryBelow
    }

    private func triggerReason(power: PowerSource) -> KeepAwakeSession.Reason? {
        if let app = runningTriggerApp() { return .app(app) }
        if settings.whileCharging, power.onAC { return .charging }
        return nil
    }

    /// The display name of the first configured app that is running, matched by name or bundle id.
    private func runningTriggerApp() -> String? {
        guard !settings.whileRunningApps.isEmpty else { return nil }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited && !app.isTerminated {
            for target in settings.whileRunningApps {
                if app.bundleIdentifier?.caseInsensitiveCompare(target) == .orderedSame
                    || app.localizedName?.caseInsensitiveCompare(target) == .orderedSame {
                    return app.localizedName ?? target
                }
            }
        }
        return nil
    }

    // MARK: Assertion

    @discardableResult
    private func assert() -> Bool {
        let type = settings.allowDisplaySleep ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Mestre keeps the Mac awake" as CFString, &assertion)
        guard result == kIOReturnSuccess else {
            assertion = 0
            NSLog("Keep awake: assertion failed (%d)", result)
            NSSound.beep()
            return false
        }
        return true
    }

    private func release() {
        guard assertion != 0 else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
    }

}
