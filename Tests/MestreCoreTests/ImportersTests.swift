import Foundation
import Testing
@testable import MestreCore

@Suite struct RaycastImportTests {
    @Test func snippetsExport() throws {
        let json = #"[{"name": "Sig", "text": "Cheers,\n{clipboard} {date format=\"yyyy\"}", "keyword": "/sig"}, {"name": "Plain", "text": "hi"}]"#
        let result = try RaycastImport.parse(Data(json.utf8))
        #expect(result.snippets.map(\.name) == ["Sig", "Plain"])
        #expect(result.snippets[0].text == "Cheers,\n{clipboard} {date:yyyy}")
        #expect(RaycastImport.convertPlaceholders(#"{time format="HH:mm"}"#) == "{date:HH:mm}")
        #expect(RaycastImport.unsupportedPlaceholders(in: #"{date offset="+1d"} {argument name="x"}"#).count == 2)
        #expect(result.snippets[0].keyword == "/sig")
        #expect(result.quicklinks.isEmpty)
    }

    @Test func quicklinksExport() throws {
        let json = #"[{"name": "Search DuckDuckGo", "link": "https://duckduckgo.com/?q={argument name=\"Query\"}"}, {"name": "GH", "link": "https://github.com/search?q={Query}", "openWith": "Safari"}]"#
        let result = try RaycastImport.parse(Data(json.utf8))
        #expect(result.quicklinks.map(\.url) == ["https://duckduckgo.com/?q={query}", "https://github.com/search?q={query}"])
        #expect(result.warnings.count == 1)
    }

    @Test func rejectsOtherJSON() {
        #expect(throws: RaycastImport.Failure.notRaycastJSON) { try RaycastImport.parse(Data(#"{"a": 1}"#.utf8)) }
        #expect(throws: RaycastImport.Failure.notRaycastJSON) { try RaycastImport.parse(Data(#"[{"foo": "bar"}]"#.utf8)) }
    }
}

@Suite struct AlfredImportTests {
    @Test func customSearches() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>customSites</key><dict>
          <key>A</key><dict><key>text</key><string>Wiki</string><key>url</key><string>https://en.wikipedia.org/w/index.php?search={query}</string><key>keyword</key><string>w</string><key>enabled</key><true/></dict>
          <key>B</key><dict><key>text</key><string>Off</string><key>url</key><string>https://x.y/{query}</string><key>enabled</key><false/></dict>
        </dict></dict></plist>
        """
        let links = try AlfredImport.customSearches(from: Data(plist.utf8))
        #expect(links.count == 1)
        #expect(links[0].keyword == "w")
        #expect(links[0].takesQuery)
    }

    @Test func snippetFile() throws {
        let json = #"{"alfredsnippet": {"snippet": "Hello {clipboard} {random:uuid}", "uid": "X", "name": "Hi", "keyword": "/hi"}}"#
        let snippet = try #require(try AlfredImport.snippet(from: Data(json.utf8)))
        #expect(snippet.name == "Hi")
        #expect(snippet.text == "Hello {clipboard} {uuid}")
        #expect(snippet.keyword == "/hi")
    }

    @Test func workflowHotkeyToLaunchApp() throws {
        // ⌘⌥⌃⇧ = 0x1E0000 in NSEvent flags; key code 17 is T on US layouts.
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
          <key>objects</key><array>
            <dict><key>type</key><string>alfred.workflow.trigger.hotkey</string><key>uid</key><string>H</string>
              <key>config</key><dict><key>hotkey</key><integer>17</integer><key>hotmod</key><integer>1966080</integer><key>hotstring</key><string>T</string></dict></dict>
            <dict><key>type</key><string>alfred.workflow.action.launchfiles</string><key>uid</key><string>L</string>
              <key>config</key><dict><key>paths</key><array><string>/Applications/Utilities/Terminal.app</string></array></dict></dict>
          </array>
          <key>connections</key><dict><key>H</key><array><dict><key>destinationuid</key><string>L</string></dict></array></dict>
        </dict></plist>
        """
        let result = try AlfredImport.workflowHotkeys(from: Data(plist.utf8))
        #expect(result.hotkeys == ["hyper+t": "Terminal"])
        #expect(result.warnings.isEmpty)
        let disabled = plist.replacingOccurrences(of: "<key>objects</key>", with: "<key>disabled</key><true/><key>objects</key>")
        #expect(try AlfredImport.workflowHotkeys(from: Data(disabled.utf8)).hotkeys.isEmpty)
    }

    @Test func namedDateStylesBecomePlainPlaceholders() {
        #expect(AlfredImport.convertPlaceholders("{date:short} {time:LONG} {date:yyyy} {random:uuid}") == "{date} {time} {date:yyyy} {uuid}")
    }
}

@Suite struct ImportMergeTests {
    @Test func mergeSkipsExistingNamesAndDefaultHotkeys() {
        var config = Config()
        config.snippets.items = [Snippet(name: "Sig", text: "old")]
        config.quicklinks = [Quicklink(name: "GH", url: "https://github.com")]
        var imported = ImportResult()
        imported.snippets = [Snippet(name: "sig", text: "new"), Snippet(name: "Other", text: "x"), Snippet(name: "other", text: "dup within import")]
        imported.quicklinks = [Quicklink(name: "gh", url: "https://x"), Quicklink(name: "DDG", url: "https://ddg.gg/?q={query}")]
        config.hotkeys = ["alt+k": "Notes"]
        imported.hotkeys = ["hyper+t": "Terminal", "ctrl+option+left": "Safari", "option+k": "Mail", "option+space": "Finder"]
        let added = config.merge(imported)
        #expect(added.snippets == 1 && added.quicklinks == 1 && added.hotkeys == 1)
        #expect(config.snippets.items.map(\.text) == ["old", "x"])
        #expect(config.hotkeys == ["alt+k": "Notes", "hyper+t": "Terminal"])  // option+k and the panel hotkey are taken
    }
}
