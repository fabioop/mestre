import Darwin
import Foundation

/// The parameterised system commands: "volume 30".
public enum VolumeQuery {
    /// The level asked for by "volume 30", "vol 30%" or "set volume 30", 0–100; nil otherwise.
    /// Takes the query's lowercased words.
    public static func level(in words: [String]) -> Int? {
        let words = words.first == "set" ? words.dropFirst() : words[...]
        guard words.count == 2, let first = words.first, first == "volume" || first == "vol", var number = words.last.map({ Substring($0) }) else { return nil }
        if number.hasSuffix("%") { number = number.dropLast() }
        guard !number.isEmpty, number.allSatisfy({ $0.isASCII && $0.isNumber }), let level = Int(number), level <= 100 else { return nil }
        return level
    }

    /// AppleScript for a step up or down, clamped to 0–100 and unmuting, as the volume keys do.
    /// `set volume` is a Standard Addition run inside osascript: no Automation consent.
    public static func changeScript(by step: Int) -> String {
        """
        set v to (output volume of (get volume settings)) + (\(step))
        if v > 100 then set v to 100
        if v < 0 then set v to 0
        set volume output muted false
        set volume output volume v
        """
    }

    public static func setScript(level: Int) -> String {
        "set volume output muted false\nset volume output volume \(min(100, max(0, level)))"
    }

    public static let toggleMuteScript = "set volume output muted not (output muted of (get volume settings))"
}

/// Which apps "Quit All Apps" leaves running: Finder (quitting it only relaunches it) and
/// the user's exclusions, app names or bundle identifiers, case-insensitive.
public struct QuitAllApps {
    private let kept: Set<String>

    public init(exclusions: [String]) {
        kept = Set((exclusions + ["com.apple.finder"]).map { $0.lowercased() })
    }

    public func shouldQuit(name: String?, bundleID: String?) -> Bool {
        ![name, bundleID].contains { $0.map { kept.contains($0.lowercased()) } ?? false }
    }
}

/// "kill :3000" and "kill port 3000": the processes listening on a TCP port, read in-process
/// with libproc (no lsof subprocess while typing).
public enum PortLookup {
    /// The port in the text after the keyword: ":3000", "port 3000", "port :3000". 1–65535.
    public static func port(in remainder: String) -> UInt16? {
        let words = remainder.lowercased().split(whereSeparator: \.isWhitespace)
        let token: Substring
        switch words.count {
        case 1 where words[0].hasPrefix(":"): token = words[0].dropFirst()
        case 2 where words[0] == "port": token = words[1].hasPrefix(":") ? words[1].dropFirst() : words[1]
        default: return nil
        }
        guard !token.isEmpty, token.allSatisfy({ $0.isASCII && $0.isNumber }), let port = UInt16(token), port > 0 else { return nil }
        return port
    }

    /// Port → pids of the sockets listening on it, each pid once per port.
    public static func listeners(from sockets: [TCPSocket]) -> [UInt16: [pid_t]] {
        var result: [UInt16: [pid_t]] = [:]
        for socket in sockets where socket.isListening && socket.localPort > 0 && socket.pid > 0 {
            if result[socket.localPort]?.contains(socket.pid) != true { result[socket.localPort, default: []].append(socket.pid) }
        }
        return result
    }

    /// The TCP sockets `pids` have open, IPv4 and IPv6. A pid that exited or belongs to another
    /// user (EPERM) is skipped. A few milliseconds for a user's processes: run it off the main thread.
    public static func tcpSockets(of pids: [pid_t]) -> [TCPSocket] {
        var sockets: [TCPSocket] = []
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: 256)
        let fdStride = MemoryLayout<proc_fdinfo>.stride
        let infoSize = Int32(MemoryLayout<socket_fdinfo>.size)
        var info = socket_fdinfo()
        for pid in pids where pid > 0 {
            // With no buffer, the size the fd list needs right now; leave room for a few more.
            let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard needed > 0 else { continue }
            let capacity = Int(needed) / fdStride + 32
            if fds.count < capacity { fds = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity) }
            let filled = fds.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
            guard filled > 0 else { continue }
            for fd in fds.prefix(Int(filled) / fdStride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
                guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, infoSize) == infoSize,
                      info.psi.soi_kind == Int32(SOCKINFO_TCP) else { continue }
                let tcp = info.psi.soi_proto.pri_tcp
                sockets.append(TCPSocket(pid: pid, state: tcp.tcpsi_state, networkOrderPort: tcp.tcpsi_ini.insi_lport))
            }
        }
        return sockets
    }
}

/// One TCP socket a process has open, as libproc describes it.
public struct TCPSocket: Equatable, Sendable {
    public let pid: pid_t
    /// `TSI_S_*` from <sys/proc_info.h>.
    public let state: Int32
    public let localPort: UInt16

    public init(pid: pid_t, state: Int32, localPort: UInt16) {
        self.pid = pid
        self.state = state
        self.localPort = localPort
    }

    /// libproc's `insi_lport` holds the port in network byte order in an int.
    public init(pid: pid_t, state: Int32, networkOrderPort: Int32) {
        self.init(pid: pid, state: state, localPort: UInt16(bigEndian: UInt16(truncatingIfNeeded: networkOrderPort)))
    }

    public var isListening: Bool { state == TSI_S_LISTEN }
}
