import Foundation

/// A Bluetooth device this Mac knows, as plain data: no IOBluetooth objects leave the app target.
public struct BluetoothDevice: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case headphones, speaker, keyboard, pointer, phone, computer, other

        /// Reads the major and minor fields of a Bluetooth class of device.
        public init(classOfDevice: UInt32) {
            let major = (classOfDevice >> 8) & 0x1F
            let minor = (classOfDevice >> 2) & 0x3F
            switch major {
            case 1: self = .computer
            case 2: self = .phone
            case 4: self = minor == 5 || minor == 10 ? .speaker : .headphones
            case 5:
                switch minor >> 4 {
                case 1, 3: self = .keyboard
                case 2: self = .pointer
                default: self = .other
                }
            default: self = .other
            }
        }

        var isAudio: Bool { self == .headphones || self == .speaker }
    }

    public let address: String
    public let name: String
    public let kind: Kind
    public let isConnected: Bool
    /// When Mestre last connected it; the system keeps no usable date.
    public let lastUsed: Date?

    public init(address: String, name: String, kind: Kind, isConnected: Bool, lastUsed: Date?) {
        self.address = address
        self.name = name
        self.kind = kind
        self.isConnected = isConnected
        self.lastUsed = lastUsed
    }

    /// A connected keyboard or mouse: disconnecting it may leave no way to undo that.
    public var isInputInUse: Bool { isConnected && !kind.isAudio }

    /// SF Symbol.
    public var symbol: String {
        let lowered = name.lowercased()
        if lowered.contains("airpods max") { return "airpodsmax" }
        if lowered.contains("airpods pro") { return "airpodspro" }
        if lowered.contains("airpods") { return "airpods" }
        switch kind {
        case .headphones: return "headphones"
        case .speaker: return "hifispeaker"
        case .keyboard: return "keyboard"
        case .pointer: return "computermouse"
        case .phone: return "iphone"
        case .computer: return "laptopcomputer"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }

    /// What Return should reach first. Devices to connect come before connected ones, so a bare
    /// keyword and Return can't disconnect the keyboard in use; among them audio first, then the
    /// most recently used. An unknown kind that isn't connected is left out unless `showUnknown`:
    /// those are mostly an iPhone, Watch or Mac synced through iCloud, which can't be connected.
    public static func listed(_ devices: [BluetoothDevice], showUnknown: Bool = false) -> [BluetoothDevice] {
        devices.filter { showUnknown || $0.isConnected || $0.kind != .other }.sorted { a, b in
            if a.isConnected != b.isConnected { return b.isConnected }
            if a.kind.isAudio != b.kind.isAudio { return a.kind.isAudio }
            let (first, second) = (a.lastUsed ?? .distantPast, b.lastUsed ?? .distantPast)
            if first != second { return first > second }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
