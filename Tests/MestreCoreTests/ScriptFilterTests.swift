import Foundation
import Testing
@testable import MestreCore

@Suite struct ScriptFilterTests {
    @Test func decodesTheScriptContractAndFiltersOnceModeRows() throws {
        let json = #"{"items": [{"uid": "a", "title": "Alpha", "subtitle": "first", "arg": "https://a.example", "match": "alpha one"}, {"title": "Beta", "valid": false, "autocomplete": "be "}], "rerun": 9}"#
        let output = try #require(ScriptOutput.parse(Data(json.utf8)))
        #expect(output.items.count == 2 && output.rerun == 5)
        #expect(output.items[1].id == "Beta" && output.items[1].valid == false && output.items[1].autocomplete == "be ")
        #expect(output.filtered(by: "", limit: 1).map(\.title) == ["Alpha"])
        #expect(output.filtered(by: "one", limit: 8).map(\.title) == ["Alpha"])
        #expect(output.filtered(by: "bet", limit: 8).map(\.title) == ["Beta"])
        #expect(ScriptOutput.parse(Data("not json".utf8)) == nil)
    }

    @Test func configKeepsFirstOfRepeatedKeywordsAndBuildsALaunch() throws {
        let json = #"{"scripts": {"items": [{"name": "Notes", "keyword": "N", "command": "~/bin/notes.sh"}, {"name": "Other", "keyword": "n", "command": "x"}, {"name": "Shell", "keyword": "sh", "command": "ls -1 ~", "mode": "perKeystroke", "needs": ["fs:~"]}]}}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.scripts.items.map(\.keyword) == ["n", "sh"])
        let direct = config.scripts.items[0].launch(query: "todo")
        #expect(direct.path.hasSuffix("/bin/notes.sh") && !direct.path.hasPrefix("~") && direct.arguments == ["todo"])
        let shell = config.scripts.items[1].launch(query: "x y")
        #expect(shell.path == "/bin/sh" && shell.arguments == ["-c", "ls -1 ~", "mestre", "x y"])
        #expect(config.scripts.items[1].mode == .perKeystroke && config.scripts.items[1].needs == ["fs:~"])
        let saved = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(saved.scripts == config.scripts)
        #expect(config.scripts.items[0].timeoutSeconds == 10 && config.scripts.items[0].actionLaunch(argument: "x") == nil)
    }

    @Test func returnTargetIsDecidedFromTheArgument() {
        #expect(ScriptTarget(argument: "https://a.example/x") == .url(URL(string: "https://a.example/x")!))
        #expect(ScriptTarget(argument: "~/Notes/a.md") == .file(NSHomeDirectory() + "/Notes/a.md"))
        #expect(ScriptTarget(argument: "plain words") == .text("plain words") && ScriptTarget(argument: "plain words").title == "Copy")
        #expect(ScriptTarget(argument: "javascript:alert(1)") == .text("javascript:alert(1)"))
        #expect(ScriptTarget(argument: "file:///tmp/a.txt") == .file("/tmp/a.txt"))
        #expect(ScriptTarget(argument: "/Applications/Safari.app", isExecutable: { $0.hasSuffix(".app") }) == .text("/Applications/Safari.app"))
    }

    @Test func duplicateRowIdsAreMadeUniqueAndRowsAreCapped() throws {
        let rows = (0..<(ScriptOutput.maxItems + 5)).map { _ in #"{"title": "Same"}"# }.joined(separator: ",")
        let output = try #require(ScriptOutput.parse(Data("{\"items\": [\(rows)]}".utf8)))
        #expect(output.items.count == ScriptOutput.maxItems)
        #expect(Set(output.items.map(\.id)).count == ScriptOutput.maxItems && output.items[1].id == "Same#1")
    }

    @Test func aPathWithSpacesRunsDirectlyWhenItIsAFile() {
        let launch = ScriptFilter.launch(command: "~/My Scripts/notes.sh", argument: "q", fileExists: { $0.hasSuffix("/My Scripts/notes.sh") })
        #expect(launch.path.hasSuffix("/My Scripts/notes.sh") && launch.arguments == ["q"])
        #expect(ScriptFilter.launch(command: "ls -1", argument: "q").path == "/bin/sh")
    }
}
