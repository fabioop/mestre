import Darwin
import Foundation

/// One running process, from libproc. Memory is the physical footprint, the number
/// Activity Monitor shows.
public struct RunningProcess: Equatable, Sendable, Identifiable {
    public let pid: pid_t
    public let name: String
    public let path: String
    public let memoryBytes: UInt64

    public var id: pid_t { pid }

    public init(pid: pid_t, name: String, path: String, memoryBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.path = path
        self.memoryBytes = memoryBytes
    }
}

public enum ProcessList {
    /// Every process the current user can inspect (and so signal), largest memory first,
    /// excluding the caller itself. A few milliseconds for 500 processes: run it off the
    /// main thread and cache it for a moment.
    public static func snapshot() -> [RunningProcess] {
        let me = getpid()
        var count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        count = proc_listallpids(&pids, Int32(pids.count) * Int32(MemoryLayout<pid_t>.size))

        var pathBuffer = [CChar](repeating: 0, count: 4096)
        var usage = rusage_info_current()
        var result: [RunningProcess] = []
        result.reserveCapacity(Int(count))

        for pid in pids.prefix(Int(max(count, 0))) where pid > 0 && pid != me {
            guard let path = path(of: pid, buffer: &pathBuffer) else { continue }  // gone
            let status = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) }
            }
            guard status == 0 else { continue }  // another user's process (EPERM): we couldn't signal it anyway
            let name = (path as NSString).lastPathComponent
            result.append(RunningProcess(pid: pid, name: name, path: path, memoryBytes: usage.ri_phys_footprint))
        }
        result.sort { $0.memoryBytes > $1.memoryBytes }
        return result
    }

    /// Executable path of a live process, nil when it has exited. Used to make sure a pid
    /// shown a while ago still belongs to the same program before signalling it.
    public static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        return path(of: pid, buffer: &buffer)
    }

    private static func path(of pid: pid_t, buffer: inout [CChar]) -> String? {
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// "1.2 GB", "348 MB", "900 KB".
    public static func formatMemory(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return value >= 100 || unit == 0 ? "\(Int(value.rounded())) \(units[unit])" : String(format: "%.1f %@", value, units[unit])
    }
}
