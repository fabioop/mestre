import Foundation
import Testing
@testable import MestreCore

@Suite struct BluetoothDeviceTests {
    private func device(_ name: String, _ kind: BluetoothDevice.Kind, connected: Bool = false, used: TimeInterval? = nil) -> BluetoothDevice {
        BluetoothDevice(address: name, name: name, kind: kind, isConnected: connected, lastUsed: used.map(Date.init(timeIntervalSince1970:)))
    }

    @Test func classOfDeviceGivesTheKind() {
        #expect(BluetoothDevice.Kind(classOfDevice: 0x240404) == .headphones)
        #expect(BluetoothDevice.Kind(classOfDevice: 0x240418) == .headphones)
        #expect(BluetoothDevice.Kind(classOfDevice: 0x240414) == .speaker)
        #expect(BluetoothDevice.Kind(classOfDevice: 0x002540) == .keyboard)
        #expect(BluetoothDevice.Kind(classOfDevice: 0x002580) == .pointer)
        #expect(BluetoothDevice.Kind(classOfDevice: 0x5A020C) == .phone)
        #expect(BluetoothDevice.Kind(classOfDevice: 0x38010C) == .computer)
        #expect(BluetoothDevice.Kind(classOfDevice: 0) == .other)
    }

    @Test func connectedDevicesNeverComeFirstSoReturnCannotDropTheKeyboard() {
        let listed = BluetoothDevice.listed([
            device("Keyboard", .keyboard, connected: true, used: 900),
            device("Mouse", .pointer, used: 800),
            device("Old speaker", .speaker, used: 100),
            device("AirPods", .headphones, used: 500),
        ])
        #expect(listed.map(\.name) == ["AirPods", "Old speaker", "Mouse", "Keyboard"])
    }

    @Test func devicesNeverUsedSortByName() {
        let listed = BluetoothDevice.listed([device("b", .speaker), device("A", .speaker)])
        #expect(listed.map(\.name) == ["A", "b"])
    }

    @Test func disconnectedDevicesOfNoKnownKindAreLeftOutUnlessAskedFor() {
        let devices = [device("iPhone", .other), device("MX Master", .other, connected: true), device("AirPods", .headphones)]
        #expect(BluetoothDevice.listed(devices).map(\.name) == ["AirPods", "MX Master"])
        #expect(BluetoothDevice.listed(devices, showUnknown: true).map(\.name) == ["AirPods", "iPhone", "MX Master"])
    }

    @Test func onlyAConnectedDeviceThatIsNotAudioCountsAsInputInUse() {
        #expect(device("Keyboard", .keyboard, connected: true).isInputInUse)
        #expect(device("MX Master", .other, connected: true).isInputInUse)
        #expect(!device("Keyboard", .keyboard).isInputInUse)
        #expect(!device("AirPods", .headphones, connected: true).isInputInUse)
    }

    @Test func airPodsGetTheirOwnSymbol() {
        #expect(device("Fabio's AirPods Pro", .headphones).symbol == "airpodspro")
        #expect(device("airpods max", .headphones).symbol == "airpodsmax")
        #expect(device("AirPods", .headphones).symbol == "airpods")
        #expect(device("JBL Go 3", .speaker).symbol == "hifispeaker")
    }

    @Test func configDecodesWithDefaultsAndClampsTheTimeout() throws {
        let empty = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(empty.bluetooth == Config.Bluetooth())
        #expect(empty.bluetooth.keyword == "pair" && empty.bluetooth.enabled && empty.bluetooth.closeOnConnect)
        let custom = try JSONDecoder().decode(Config.self, from: Data(#"{"bluetooth": {"keyword": "BT", "closeOnConnect": false, "connectTimeoutSeconds": 0}}"#.utf8))
        #expect(custom.bluetooth.keyword == "bt" && !custom.bluetooth.closeOnConnect)
        #expect(custom.bluetooth.connectTimeoutSeconds == 1)
    }
}
