import Foundation
import Testing
@testable import MestreCore

@Suite struct SystemCommandsTests {
    private func level(_ text: String) -> Int? { VolumeQuery.level(in: Query(text).words) }

    @Test func volumeLevelFromTheQuery() {
        #expect(level("volume 30") == 30)
        #expect(level("Vol 0") == 0)
        #expect(level("volume 100%") == 100)
        #expect(level("set volume 45") == 45)
        #expect(level("  volume   7 ") == 7)
        #expect(level("volume") == nil)
        #expect(level("volume 101") == nil)
        #expect(level("volume -5") == nil)
        #expect(level("volume +5") == nil)
        #expect(level("volume up") == nil)
        #expect(level("volume 30 40") == nil)
        #expect(level("volume %") == nil)
        #expect(level("volume ٣٠") == nil)
        #expect(level("set 30") == nil)
    }

    @Test func volumeScriptsClampAndUnmute() {
        #expect(VolumeQuery.setScript(level: 30) == "set volume output muted false\nset volume output volume 30")
        #expect(VolumeQuery.setScript(level: 300).hasSuffix("volume 100"))
        let down = VolumeQuery.changeScript(by: -10)
        #expect(down.contains("+ (-10)") && down.contains("if v < 0 then set v to 0") && down.contains("muted false"))
    }

    @Test func quitAllKeepsFinderAndTheExclusions() {
        let rule = QuitAllApps(exclusions: ["Music", "com.googlecode.iterm2"])
        #expect(rule.shouldQuit(name: "Safari", bundleID: "com.apple.Safari"))
        #expect(rule.shouldQuit(name: nil, bundleID: nil))
        #expect(!rule.shouldQuit(name: "Finder", bundleID: "com.apple.finder"))
        #expect(!rule.shouldQuit(name: "music", bundleID: "com.apple.Music"))
        #expect(!rule.shouldQuit(name: "iTerm", bundleID: "com.googlecode.iTerm2"))
    }

    @Test func portFromTheQuery() {
        #expect(PortLookup.port(in: ":3000") == 3000)
        #expect(PortLookup.port(in: "port 3000") == 3000)
        #expect(PortLookup.port(in: "Port :8080") == 8080)
        #expect(PortLookup.port(in: ":65535") == 65535)
        #expect(PortLookup.port(in: ":65536") == nil)
        #expect(PortLookup.port(in: ":0") == nil)
        #expect(PortLookup.port(in: ":") == nil)
        #expect(PortLookup.port(in: "3000") == nil)  // a process name filter, not a port
        #expect(PortLookup.port(in: "port") == nil)
        #expect(PortLookup.port(in: "port abc") == nil)
        #expect(PortLookup.port(in: ":30 00") == nil)
        #expect(PortLookup.port(in: "node :3000") == nil)
        #expect(PortLookup.port(in: ":+80") == nil)
    }

    @Test func listenersAreTheListeningSocketsByPort() {
        let listen = Int32(TSI_S_LISTEN)
        let sockets = [
            TCPSocket(pid: 652, state: listen, localPort: 49152),
            TCPSocket(pid: 652, state: listen, localPort: 49152),  // IPv4 and IPv6: one row
            TCPSocket(pid: 652, state: listen, localPort: 3000),
            TCPSocket(pid: 713, state: listen, localPort: 3000),
            TCPSocket(pid: 713, state: listen, localPort: 8080),
            TCPSocket(pid: 713, state: Int32(TSI_S_ESTABLISHED), localPort: 5432),  // a client connection
            TCPSocket(pid: 800, state: listen, localPort: 0),
            TCPSocket(pid: 0, state: listen, localPort: 22),
        ]
        #expect(PortLookup.listeners(from: sockets) == [49152: [652], 3000: [652, 713], 8080: [713]])
        #expect(PortLookup.listeners(from: []).isEmpty)
        // libproc keeps the port in network byte order.
        #expect(TCPSocket(pid: 1, state: listen, networkOrderPort: Int32(UInt16(3000).bigEndian)).localPort == 3000)
    }

    /// A real listener on an ephemeral loopback port, found through libproc for this process.
    @Test func findsOwnListeningSocket() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        try #require(fd >= 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) == 0 && listen(fd, 1) == 0 && getsockname(fd, $0, &length) == 0 }
        }
        try #require(bound)
        let port = UInt16(bigEndian: address.sin_port)
        let listeners = PortLookup.listeners(from: PortLookup.tcpSockets(of: [getpid()]))
        #expect(listeners[port] == [getpid()])
    }

    @Test func newCommandAndProcessKeysDecodeWithDefaults() throws {
        let defaults = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(defaults.commands.volumeStep == 10 && defaults.commands.quitAllExcept.isEmpty && defaults.processes.ports)
        let custom = try JSONDecoder().decode(Config.self, from: Data(#"{"commands": {"volumeStep": 500, "quitAllExcept": ["Music"]}, "processes": {"ports": false}}"#.utf8))
        #expect(custom.commands.volumeStep == 100 && custom.commands.quitAllExcept == ["Music"] && !custom.processes.ports)
        let low = try JSONDecoder().decode(Config.self, from: Data(#"{"commands": {"volumeStep": 0}}"#.utf8))
        #expect(low.commands.volumeStep == 1)
    }
}
