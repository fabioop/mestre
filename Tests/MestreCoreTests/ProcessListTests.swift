import Foundation
import Testing
@testable import MestreCore

@Suite struct ProcessListTests {
    @Test func snapshotListsSignallableProcessesExceptSelfSortedByMemory() {
        let processes = ProcessList.snapshot()
        #expect(processes.count > 10)
        #expect(!processes.contains { $0.pid == ProcessInfo.processInfo.processIdentifier })
        #expect(!processes.contains { $0.pid == 1 })
        #expect(zip(processes, processes.dropFirst()).allSatisfy { $0.memoryBytes >= $1.memoryBytes })
        #expect(processes.allSatisfy { !$0.name.isEmpty && $0.memoryBytes > 0 })
    }

    @Test func pathOfLiveAndDeadProcesses() {
        #expect(ProcessList.path(of: ProcessInfo.processInfo.processIdentifier)?.isEmpty == false)
        #expect(ProcessList.path(of: 99_999_999) == nil)
    }

    @Test func memoryFormatting() {
        #expect(ProcessList.formatMemory(900) == "900 B")
        #expect(ProcessList.formatMemory(348 * 1_048_576) == "348 MB")
        #expect(ProcessList.formatMemory(UInt64(1.2 * 1_073_741_824)) == "1.2 GB")
        #expect(ProcessList.formatMemory(45_000) == "43.9 KB")
    }

    @Test func processesConfigDecodesAndKeepsKeywordNonEmpty() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"processes": {"keyword": "  "}}"#.utf8))
        #expect(config.processes.keyword == "kill")
        let custom = try JSONDecoder().decode(Config.self, from: Data(#"{"processes": {"keyword": "Kill App", "enabled": false}}"#.utf8))
        #expect(custom.processes.keyword == "kill" && !custom.processes.enabled)
        let ps = try JSONDecoder().decode(Config.self, from: Data(#"{"processes": {"keyword": "ps"}}"#.utf8))
        #expect(ps.processes.keyword == "ps")
    }
}
