import Foundation

/// Runs command line tools off the main thread. Shared by commands and shortcuts.
enum ProcessRunner {
    /// Fire and forget; a non-zero exit only reaches the log, with stderr.
    static func run(_ path: String, _ arguments: [String], label: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = FileHandle.nullDevice
            do {
                try process.run()
                // Drain stderr before waiting so a chatty child can't fill the pipe and block.
                let message = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    NSLog("%@ failed (%d): %@", label, process.terminationStatus, message.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } catch {
                NSLog("%@ could not start: %@", label, error.localizedDescription)
            }
        }
    }

    enum Capture {
        case output(Data)
        case exited(Int32)
        case couldNotStart(String)
        case timedOut
    }

    /// Most stdout a tool may print before its output is dropped.
    static let maxOutputBytes = 4 << 20

    /// Runs a tool and captures its stdout. `environment` is added to the inherited one.
    /// A run past `timeout` gets SIGTERM, then SIGKILL a second later if it ignored that.
    /// Blocking: call it from a detached task.
    static func capture(_ path: String, _ arguments: [String], environment: [String: String] = [:], timeout: TimeInterval? = nil) -> Capture {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if !environment.isEmpty { process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new } }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .couldNotStart(error.localizedDescription) }
        let timedOut = Flag()
        var killers: [DispatchWorkItem] = []
        if let timeout {
            let terminate = DispatchWorkItem { if process.isRunning { timedOut.set(); process.terminate() } }
            let forceKill = DispatchWorkItem { if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) } }
            killers = [terminate, forceKill]
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: terminate)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 1, execute: forceKill)
        }
        // Read as it comes, so a runaway child is stopped at the cap instead of buffered whole.
        var data = Data()
        var overflowed = false
        let reader = pipe.fileHandleForReading
        while true {
            let chunk = reader.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count > maxOutputBytes { overflowed = true; process.terminate(); break }
        }
        process.waitUntilExit()
        for killer in killers { killer.cancel() }
        if timedOut.isSet { return .timedOut }
        if overflowed { return .exited(-1) }
        return process.terminationStatus == 0 ? .output(data) : .exited(process.terminationStatus)
    }

    /// A Bool set from one queue and read from another.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// Captured stdout as text, nil for anything but a clean exit.
    static func output(_ path: String, _ arguments: [String], timeout: TimeInterval? = nil) -> String? {
        if case .output(let data) = capture(path, arguments, timeout: timeout) { return String(decoding: data, as: UTF8.self) }
        return nil
    }
}
