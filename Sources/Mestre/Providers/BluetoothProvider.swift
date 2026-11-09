import AppKit
import CoreBluetooth
import IOBluetooth
import MestreCore

struct BluetoothDeviceItem: SearchItem {
    let device: BluetoothDevice
    var status: String? = nil

    var id: String { device.address }
    var title: String { device.name }
    var subtitle: String? {
        status ?? (device.isConnected ? "Connected" : "Not connected")
    }
    var icon: NSImage? { nil }
    var iconSymbol: String? { device.symbol }
    var kind: ItemKind { .bluetooth }
    var isActive: Bool { device.isConnected }
    var actions: [ItemAction] { [device.isConnected ? Self.disconnect : Self.connect, Self.copyAddress] }

    static let connect = ItemAction(id: "connect", title: "Connect", icon: "link")
    static let disconnect = ItemAction(id: "disconnect", title: "Disconnect", icon: "link.badge.minus")
    static let copyAddress = ItemAction(id: "copyAddress", title: "Copy Address", icon: "doc.on.doc")
}

/// A row that hands over to System Settings: pairing something new, or granting access.
struct BluetoothSettingsItem: SearchItem {
    let title: String
    let subtitle: String?
    let symbol: String
    let url: URL

    var id: String { url.absoluteString }
    var icon: NSImage? { nil }
    var iconSymbol: String? { symbol }
    var kind: ItemKind { .bluetooth }
    var actions: [ItemAction] { [Self.open] }

    static let open = ItemAction(id: "openSettings", title: "Open System Settings", icon: "gearshape")
    static let pairNew = BluetoothSettingsItem(title: "Pair a New Device…", subtitle: "Bluetooth settings", symbol: "plus.circle", url: SettingsPane(bundleIdentifier: "com.apple.BluetoothSettings", title: "Bluetooth").url)
    static let allowAccess = BluetoothSettingsItem(title: "Allow Bluetooth Access…", subtitle: "Mestre needs it to list your devices", symbol: "lock", url: SettingsPane.privacyURL("Privacy_Bluetooth"))
}

/// "pair <name>" lists the devices this Mac is paired with; Return connects or disconnects one.
/// Nothing touches Bluetooth until the keyword is typed, so the permission prompt only ever
/// reaches someone who asked for the feature, and the rest of the time this costs nothing.
@MainActor
final class BluetoothProvider: NSObject, ResultProvider {
    nonisolated let id = "bluetooth"
    nonisolated let declaredActions = [BluetoothDeviceItem.connect, BluetoothDeviceItem.disconnect, BluetoothDeviceItem.copyAddress, BluetoothSettingsItem.open]

    var settings = Config.Bluetooth() {
        didSet { mode = KeywordMode(enabled: settings.enabled, keyword: settings.keyword) }
    }
    private var mode = KeywordMode(enabled: true, keyword: Config.Bluetooth().keyword)
    func owns(_ query: Query) -> Bool { mode.matches(query) }
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    /// Read off the main thread with each sample: `CBManager.authorization` takes about 13 ms,
    /// over the whole keystroke budget. Nil until the first sample lands.
    private var authorization: CBManagerAuthorization?
    private var devices: [BluetoothDevice] = []
    private var sampledAt = Date.distantPast
    private var sampling = false
    /// A state change asked for a sample while one was running: the running one may predate it.
    private var sampleAgain = false
    /// Connections under way, and the devices whose last one failed, by address.
    private var attempts: [String: ConnectionAttempt] = [:]
    private var failures: Set<String> = []
    /// Timed out but IOBluetooth may still report to them, so they have to stay alive.
    private var abandoned: Set<ConnectionAttempt> = []
    /// Fires when a link really is down; `closeConnection` returns before that.
    private var disconnectWatchers: [String: IOBluetoothUserNotification] = [:]
    /// Exists only while the permission prompt is up: it reports the answer.
    private var authorizer: CBCentralManager?
    /// The connection the open panel is waiting on: it alone may close the panel when it lands.
    /// Forgotten when the query leaves, which also happens each time the panel reopens.
    private var awaited: ConnectionAttempt?
    /// When Mestre last connected each device, by address: usage data, not a setting. IOBluetooth's
    /// own `recentAccessDate` just answers with the current time.
    private lazy var lastConnected = UserDefaults.standard.dictionary(forKey: Self.lastConnectedKey) as? [String: Date] ?? [:]
    private static let lastConnectedKey = "bluetoothLastConnected"
    private static let cacheLifetime: TimeInterval = 2

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "bluetooth", title: "Bluetooth Devices", subtitle: "Connect your AirPods and other paired devices", symbol: "airpodspro", keyword: settings.keyword)
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard mode.matches(query) else { return [] }
        resampleIfStale()
        switch authorization {
        case nil, .notDetermined?:
            return []
        case .denied?, .restricted?:
            return ScoredItem.pinned([BluetoothSettingsItem.allowAccess], provider: self)
        default:
            break
        }
        let items = devices.map { BluetoothDeviceItem(device: $0, status: status(of: $0.address)) }
        let filter = query.remainder
        if filter.isEmpty {
            return ScoredItem.pinned(Array(items.prefix(max(0, limit - 1))) + [BluetoothSettingsItem.pairNew], provider: self)
        }
        // A connected keyboard or mouse goes last here too: "pair magic" and Return must not drop the one in use.
        let ranked = Ranker.rank(items, query: filter, limit: limit, provider: self)
        func inUse(_ row: ScoredItem) -> Bool { (row.item as? BluetoothDeviceItem)?.device.isInputInUse == true }
        return ranked.filter { !inUse($0) } + ranked.filter(inUse)
    }

    private func status(of address: String) -> String? {
        if attempts[address] != nil { return "Connecting…" }
        return failures.contains(address) ? "Could not connect. Is it nearby and on?" : nil
    }

    func emptyMessage(for query: Query) -> String? {
        switch authorization {
        case nil: return "Looking for devices…"
        case .notDetermined?: return "Waiting for Bluetooth access…"
        default: return nil
        }
    }

    func queryLeft() { awaited = nil }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        if let settingsRow = item as? BluetoothSettingsItem {
            NSWorkspace.shared.open(settingsRow.url)
            dismiss?()
            return
        }
        guard let device = (item as? BluetoothDeviceItem)?.device else { return }
        switch action.id {
        case "connect": connect(device)
        case "disconnect": disconnect(device)
        case "copyAddress": device.address.copyToPasteboard(toast: "Address copied")
        default: NSSound.beep()
        }
    }

    private func connect(_ device: BluetoothDevice) {
        guard attempts[device.address] == nil else { return }
        guard let target = IOBluetoothDevice(addressString: device.address) else { return failed(device) }
        let attempt = ConnectionAttempt { [weak self] attempt, status in self?.finish(device, attempt, status: status) }
        attempts[device.address] = attempt
        awaited = attempt
        failures.remove(device.address)
        onChange?()
        guard target.openConnection(attempt) == kIOReturnSuccess else {
            attempts[device.address] = nil
            return failed(device)
        }
        // A device out of range normally reports back; this covers the time it doesn't.
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.connectTimeoutSeconds) { [weak self, weak attempt] in
            guard let self, let attempt, self.attempts[device.address] === attempt else { return }
            self.attempts[device.address] = nil
            self.abandoned.insert(attempt)
            self.failed(device)
        }
    }

    /// A report from a timed-out attempt still counts if it succeeded, but the row has already
    /// said it failed, and the panel may have moved on.
    private func finish(_ device: BluetoothDevice, _ attempt: ConnectionAttempt, status: IOReturn) {
        let isCurrent = abandoned.remove(attempt) == nil
        if isCurrent { attempts[device.address] = nil }
        guard status == kIOReturnSuccess else {
            if isCurrent { failed(device) }
            return
        }
        lastConnected[device.address] = Date()
        UserDefaults.standard.set(lastConnected, forKey: Self.lastConnectedKey)
        onChange?()
        resample()
        if settings.closeOnConnect, awaited === attempt { dismiss?() }
    }

    private func failed(_ device: BluetoothDevice) {
        failures.insert(device.address)
        NSSound.beep()
        onChange?()
    }

    private func disconnect(_ device: BluetoothDevice) {
        guard let target = IOBluetoothDevice(addressString: device.address) else { return NSSound.beep() }
        disconnectWatchers[device.address] = disconnectWatchers[device.address] ?? target.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        guard target.closeConnection() == kIOReturnSuccess else {
            disconnectWatchers.removeValue(forKey: device.address)?.unregister()
            return NSSound.beep()
        }
        failures.remove(device.address)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        if let address = device.addressString { disconnectWatchers[address] = nil }
        resample()
    }

    private func requestAccess() {
        guard authorizer == nil else { return }
        authorizer = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    private func resampleIfStale() {
        guard Date().timeIntervalSince(sampledAt) > Self.cacheLifetime else { return }
        resample()
    }

    private func resample() {
        guard !sampling else {
            sampleAgain = true
            return
        }
        sampling = true
        Task {
            let (lastConnected, showUnknown) = (lastConnected, settings.showUnknownDevices)
            let (access, snapshot) = await Task.detached(priority: .userInitiated) {
                let access = CBManager.authorization
                return (access, access == .allowedAlways ? Self.pairedDevices(lastConnected: lastConnected, showUnknown: showUnknown) : [])
            }.value
            failures.subtract(snapshot.filter(\.isConnected).map(\.address))
            let changed = access != authorization || snapshot != devices
            authorization = access
            devices = snapshot
            sampledAt = Date()
            sampling = false
            if access == .notDetermined { requestAccess() } else { authorizer = nil }
            if changed { onChange?() }
            if sampleAgain {
                sampleAgain = false
                resample()
            }
        }
    }

    nonisolated private static func pairedDevices(lastConnected: [String: Date], showUnknown: Bool) -> [BluetoothDevice] {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return BluetoothDevice.listed(paired.compactMap { device in
            guard let address = device.addressString else { return nil }
            return BluetoothDevice(
                address: address,
                name: device.nameOrAddress ?? address,
                kind: BluetoothDevice.Kind(classOfDevice: device.classOfDevice),
                isConnected: device.isConnected(),
                lastUsed: lastConnected[address]
            )
        }, showUnknown: showUnknown)
    }
}

extension BluetoothProvider: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { resample() }
    }
}

/// The target IOBluetooth reports an asynchronous connection to.
private final class ConnectionAttempt: NSObject {
    private let completion: (ConnectionAttempt, IOReturn) -> Void

    init(completion: @escaping (ConnectionAttempt, IOReturn) -> Void) {
        self.completion = completion
    }

    @objc(connectionComplete:status:)
    func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        completion(self, status)
    }
}
