import Foundation

/// Runs a script command and collects what it printed. Blocking for as long as the script runs:
/// call it on a dispatch queue, not from Swift concurrency's few shared threads.
/// (`ProcessRunner` in the app runs system tools; scripts need stderr, an environment and a folder.)
public enum ScriptRunner {
    public enum Outcome: Equatable, Sendable {
        /// Exit status 0.
        case finished(stdout: String)
        /// A non-zero exit status, with what the script printed.
        case failed(status: Int32, stdout: String, stderr: String)
        case timedOut
        case couldNotStart(String)
    }

    /// Most bytes kept from each of stdout and stderr; the rest is read and dropped.
    public static let maxOutputBytes = 1 << 20

    /// Runs `command` with `values` as its arguments, in its `currentDirectoryPath` (or its own
    /// folder), with `extraPath` put before the inherited PATH: an app started from the Dock gets
    /// only the system folders, and Homebrew's tools are where most scripts expect them.
    /// Past `timeout` the script gets SIGTERM, then SIGKILL a second later.
    public static func run(_ command: ScriptCommand, values: [String], timeout: TimeInterval, extraPath: [String] = [],
                           environment: [String: String] = ProcessInfo.processInfo.environment) -> Outcome {
        let launch = command.launch(with: values)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executable)
        process.arguments = launch.arguments
        process.currentDirectoryURL = workingDirectory(for: command)
        var env = environment
        let inherited = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let extra = extraPath.map { NSString(string: $0).expandingTildeInPath }.filter { !$0.isEmpty }
        env["PATH"] = (extra + [inherited]).joined(separator: ":")
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let stdout = Collector(), stderr = Collector()
        stdout.read(out.fileHandleForReading)
        stderr.read(err.fileHandleForReading)

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            return .couldNotStart(error.localizedDescription)
        }
        var timedOut = false
        if exited.wait(timeout: .now() + max(0.1, timeout)) == .timedOut {
            timedOut = true
            // The script's own children too: a killed shell would leave its `sleep` or `curl` running.
            let tree = [process.processIdentifier] + descendants(of: process.processIdentifier)
            for pid in tree { kill(pid, SIGTERM) }
            let ignoredTerm = exited.wait(timeout: .now() + 1) == .timedOut
            for pid in tree.dropFirst() { kill(pid, SIGKILL) }
            if ignoredTerm {
                kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
        }
        // A child the script left in the background may hold the pipes open: wait a moment, not forever.
        let grace = DispatchTime.now() + 1
        let output = stdout.finish(by: grace), errors = stderr.finish(by: grace)
        if timedOut { return .timedOut }
        let status = process.terminationStatus
        return status == 0 ? .finished(stdout: output) : .failed(status: status, stdout: output, stderr: errors)
    }

    /// Every process below `pid`, children first.
    static func descendants(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 256)
        let count = proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        let children = buffer.prefix(Int(count)).filter { $0 > 0 }
        return children + children.flatMap(descendants)
    }

    static func workingDirectory(for command: ScriptCommand) -> URL {
        command.resolve(command.currentDirectoryPath ?? ".")
    }

    /// Gathers one pipe's bytes from its readability handler, up to `maxOutputBytes`.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private let done = DispatchSemaphore(value: 0)
        private var handle: FileHandle?

        func read(_ handle: FileHandle) {
            self.handle = handle
            handle.readabilityHandler = { [self] h in
                let chunk = h.availableData
                if chunk.isEmpty {
                    h.readabilityHandler = nil
                    done.signal()
                    return
                }
                lock.lock()
                if data.count < ScriptRunner.maxOutputBytes { data.append(chunk.prefix(ScriptRunner.maxOutputBytes - data.count)) }
                lock.unlock()
            }
        }

        func finish(by deadline: DispatchTime) -> String {
            if done.wait(timeout: deadline) == .timedOut { handle?.readabilityHandler = nil }
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }
}
