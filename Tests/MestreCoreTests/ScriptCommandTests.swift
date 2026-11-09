import Foundation
import Testing
@testable import MestreCore

@Suite struct ScriptParserTests {
    @Test func readsARaycastHeader() throws {
        let text = """
        #!/bin/bash

        # Required parameters:
        # @raycast.schemaVersion 1
        # @raycast.title Search GitHub
        # @raycast.mode silent

        # Optional parameters:
        # @raycast.icon 🐙
        # @raycast.packageName Developer Utils
        # @raycast.description Opens a GitHub search
        # @raycast.argument1 { "type": "text", "placeholder": "Query", "percentEncoded": true }
        # @raycast.argument2 { "type": "text", "placeholder": "Language", "optional": true }
        # @raycast.needsConfirmation true
        # @raycast.currentDirectoryPath ~

        open "https://github.com/search?q=$1"
        """
        let command = try #require(ScriptParser.parse(text, path: "/s/search.sh"))
        #expect(command.title == "Search GitHub")
        #expect(command.mode == .silent)
        #expect(command.icon == .text("🐙"))
        #expect(command.packageName == "Developer Utils")
        #expect(command.description == "Opens a GitHub search")
        #expect(command.arguments == [
            .init(kind: .text, placeholder: "Query", optional: false, percentEncoded: true),
            .init(kind: .text, placeholder: "Language", optional: true),
        ])
        #expect(command.needsConfirmation && command.needsArguments)
        #expect(command.currentDirectoryPath == "~")
        #expect(command.interpreter == ["/bin/bash"])
    }

    @Test func acceptsOtherCommentStylesAndTheMestrePrefix() throws {
        let swift = """
        #!/usr/bin/env swift
        // @raycast.title Raycast Title
        // @mestre.title Mestre Title
        // @raycast.mode fullOutput
        """
        let command = try #require(ScriptParser.parse(swift, path: "/s/a.swift"))
        #expect(command.title == "Mestre Title")
        #expect(command.mode == .fullOutput)
        #expect(command.interpreter == ["/usr/bin/env", "swift"])

        // @mestre wins whichever line comes first.
        let shell = "# @mestre.mode compact\n# @raycast.mode silent\n# @raycast.title T"
        #expect(ScriptParser.parse(shell, path: "/s/b")?.mode == .compact)
        #expect(ScriptParser.parse("-- @raycast.title Lua", path: "/s/c.lua")?.title == "Lua")
    }

    @Test func skipsFilesWithoutATitle() {
        #expect(ScriptParser.parse("#!/bin/sh\necho hi", path: "/s/x.sh") == nil)
        #expect(ScriptParser.parse("# @raycast.title   ", path: "/s/x.sh") == nil)
        #expect(ScriptParser.parse("echo @raycast.title Not a comment", path: "/s/x.sh") == nil)
    }

    @Test func iconsNeverComeFromTheNetwork() {
        func icon(_ value: String) -> ScriptCommand.Icon? {
            ScriptParser.parse("# @raycast.title T\n# @raycast.icon \(value)", path: "/s/x")?.icon
        }
        #expect(icon("https://example.com/i.png") == nil)
        #expect(icon("images/logo.png") == .file("images/logo.png"))
        #expect(icon("⚡️") == .text("⚡️"))
    }

    @Test func unknownModesAndBadArgumentsFallBack() throws {
        let text = """
        # @raycast.title T
        # @raycast.mode whatever
        # @raycast.argument1 not json
        # @raycast.argument2 { "type": "dropdown", "placeholder": "Size", "data": [{"title": "Large", "value": "L"}] }
        """
        let command = try #require(ScriptParser.parse(text, path: "/s/x"))
        #expect(command.mode == .compact)
        #expect(command.arguments.count == 1)
        #expect(command.arguments.first?.kind == .dropdown)
        #expect(command.arguments.first?.choices == [.init(title: "Large", value: "L")])
    }

    @Test func runsThroughTheShebangOrAnInterpreterForTheExtension() {
        var command = ScriptCommand(path: "/s/a.py", title: "A")
        #expect(command.launch(with: ["x"]) == ("/usr/bin/env", ["python3", "/s/a.py", "x"]))
        command.interpreter = ["/bin/zsh", "-f"]
        #expect(command.launch(with: []) == ("/bin/zsh", ["-f", "/s/a.py"]))
        let bare = ScriptCommand(path: "/s/tool", title: "T")
        #expect(bare.launch(with: ["1"]) == ("/s/tool", ["1"]))
    }
}

@Suite struct ScriptArgumentsTests {
    @Test func splitsWordsAndQuotesAndTheLastTakesTheRest() {
        #expect(ScriptArguments.split("swift concurrency", count: 1) == ["swift concurrency"])
        #expect(ScriptArguments.split("swift concurrency actors", count: 2) == ["swift", "concurrency actors"])
        #expect(ScriptArguments.split("\"hello world\" fr", count: 2) == ["hello world", "fr"])
        #expect(ScriptArguments.split("'a b' 'c d' e", count: 3) == ["a b", "c d", "e"])
        #expect(ScriptArguments.split("one", count: 3) == ["one"])
        #expect(ScriptArguments.split("   ", count: 2) == [])
        #expect(ScriptArguments.split("x", count: 0) == [])
    }

    @Test func requiredValuesMustBeTypedOptionalOnesPassEmpty() {
        let arguments: [ScriptCommand.Argument] = [.init(placeholder: "Query"), .init(placeholder: "Limit", optional: true)]
        #expect(ScriptArguments.resolve("swift", for: arguments) == .success(["swift", ""]))
        #expect(ScriptArguments.resolve("", for: arguments) == .failure(.missing("Query")))
        #expect(ScriptArguments.resolve("", for: [.init()]) == .failure(.missing("argument 1")))
        #expect(ScriptArguments.resolve("anything", for: []) == .success([]))
    }

    @Test func encodesWhereAskedAndMapsDropdownTitles() {
        let encoded: [ScriptCommand.Argument] = [.init(placeholder: "Q", percentEncoded: true)]
        #expect(ScriptArguments.resolve("a b&c/d", for: encoded) == .success(["a%20b%26c%2Fd"]))
        let dropdown: [ScriptCommand.Argument] = [.init(kind: .dropdown, choices: [.init(title: "Large", value: "L")])]
        #expect(ScriptArguments.resolve("large", for: dropdown) == .success(["L"]))
        #expect(ScriptArguments.resolve("XL", for: dropdown) == .success(["XL"]))
    }
}

@Suite struct ScriptOutputTests {
    @Test func dropsColourCodesAndFindsTheLastLine() {
        let text = "\u{1B}[32mfirst\u{1B}[0m\nsecond  \n\n"
        #expect(ScriptOutput.clean(text) == "first\nsecond")
        #expect(ScriptOutput.lines(text) == ["first", "second"])
        #expect(ScriptOutput.lastLine(text) == "second")
        #expect(ScriptOutput.lastLine(" \n") == nil)
    }
}

@Suite struct ScriptIndexAndRunnerTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mestre-scripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func listsTitledScriptsAndSkipsTheRest() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("#!/bin/sh\n# @raycast.title Beta\n", to: dir.appendingPathComponent("b.sh"))
        try write("#!/bin/sh\n# @raycast.title alpha\n", to: dir.appendingPathComponent("a.sh"))
        try write("#!/bin/sh\n# @raycast.title Template\n", to: dir.appendingPathComponent("x.template.sh"))
        try write("#!/bin/sh\n# @raycast.title Hidden\n", to: dir.appendingPathComponent(".hidden.sh"))
        try write("no header", to: dir.appendingPathComponent("README.md"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try write("#!/bin/sh\n# @raycast.title Nested\n", to: dir.appendingPathComponent("sub/n.sh"))
        let files = ScriptIndex.files(in: [dir, dir, dir.appendingPathComponent("missing")])
        let titles = files.compactMap { ScriptIndex.command(at: $0.path) }.sorted(by: ScriptIndex.precedes).map(\.title)
        #expect(titles == ["alpha", "Beta"])
    }

    @Test func runsWithoutTheExecutableBitInItsOwnFolder() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("hello.sh")
        try write("#!/bin/sh\n# @raycast.title Hello\necho \"hi $1\"\npwd\n", to: url)
        let command = try #require(ScriptParser.parse(String(contentsOf: url, encoding: .utf8), path: url.path))
        let outcome = ScriptRunner.run(command, values: ["there"], timeout: 10)
        guard case .finished(let stdout) = outcome else { Issue.record("\(outcome)"); return }
        let lines = stdout.split(separator: "\n").map(String.init)
        #expect(lines.first == "hi there")
        // pwd may print the folder through /private.
        #expect(lines.last.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == dir.resolvingSymlinksInPath().path)
    }

    @Test func reportsFailuresTimeoutsAndThePath() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        var failing = ScriptCommand(path: dir.appendingPathComponent("f.sh").path, title: "F")
        try write("echo out\necho oops >&2\nexit 3\n", to: URL(fileURLWithPath: failing.path))
        #expect(ScriptRunner.run(failing, values: [], timeout: 10) == .failed(status: 3, stdout: "out\n", stderr: "oops\n"))

        let slow = ScriptCommand(path: dir.appendingPathComponent("s.sh").path, title: "S")
        try write("sleep 5\n", to: URL(fileURLWithPath: slow.path))
        let start = Date()
        #expect(ScriptRunner.run(slow, values: [], timeout: 0.3) == .timedOut)
        #expect(Date().timeIntervalSince(start) < 4)

        // A timeout stops what the script started too.
        let parent = ScriptCommand(path: dir.appendingPathComponent("p2.sh").path, title: "P2")
        let pidFile = dir.appendingPathComponent("child.pid")
        try write("sleep 60 &\necho $! > '\(pidFile.path)'\nwait\n", to: URL(fileURLWithPath: parent.path))
        #expect(ScriptRunner.run(parent, values: [], timeout: 0.5) == .timedOut)
        let child = try #require(pid_t(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        usleep(100_000)
        #expect(kill(child, 0) != 0)

        failing.interpreter = ["/no/such/interpreter"]
        if case .couldNotStart = ScriptRunner.run(failing, values: [], timeout: 1) {} else { Issue.record("expected couldNotStart") }

        let path = ScriptCommand(path: dir.appendingPathComponent("p.sh").path, title: "P")
        try write("echo \"$PATH\"\n", to: URL(fileURLWithPath: path.path))
        let outcome = ScriptRunner.run(path, values: [], timeout: 10, extraPath: ["/opt/x"], environment: ["PATH": "/usr/bin:/bin"])
        #expect(outcome == .finished(stdout: "/opt/x:/usr/bin:/bin\n"))
    }

    @Test func workingDirectoryFollowsTheHeader() {
        var command = ScriptCommand(path: "/s/dir/a.sh", title: "A")
        #expect(ScriptRunner.workingDirectory(for: command).path == "/s/dir")
        command.currentDirectoryPath = "/tmp"
        #expect(ScriptRunner.workingDirectory(for: command).path == "/tmp")
        command.currentDirectoryPath = "../other"
        #expect(ScriptRunner.workingDirectory(for: command).path == "/s/other")
    }
}

@Suite struct ScriptsConfigTests {
    @Test func defaultsAndCleanup() throws {
        let defaults = Config().scripts
        #expect(defaults.enabled && defaults.keyword == "script" && defaults.directories == ["~/.config/mestre/scripts"])
        #expect(defaults.timeoutSeconds == 30 && defaults.searchEverywhere)

        let json = #"{"scripts": {"keyword": " Run Now", "directories": ["~/bin", " "], "timeoutSeconds": 0, "editor": " com.microsoft.VSCode "}}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8)).scripts
        #expect(config.keyword == "run")
        #expect(config.directories == ["~/bin"])
        #expect(config.resolvedDirectories.first?.path == NSString(string: "~/bin").expandingTildeInPath)
        #expect(config.timeoutSeconds == 1)
        #expect(config.editor == "com.microsoft.VSCode")
    }
}
