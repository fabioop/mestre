import Foundation
import Testing
@testable import MestreCore

@Suite struct SettingsPanesTests {
    @Test func derivesTitlesForUnknownIdentifiers() {
        #expect(SettingsPanes.title(for: "com.apple.Software-Update-Settings.extension") == "Software Update")
        #expect(SettingsPanes.title(for: "com.apple.LoginItems-Settings.extension") == "Login Items")
        #expect(SettingsPanes.title(for: "com.apple.Game-Center-Settings.extension") == "Game Center")
        #expect(SettingsPanes.title(for: "com.apple.NewThingSettings") == "New Thing")
        #expect(SettingsPanes.title(for: "com.apple.Something.FancySettingsExtension") == "Fancy")
        #expect(SettingsPanes.title(for: "com.apple.wifi-settings-extension") == "wifi")
    }

    @Test func scanFindsTheRealPanesWithKnownTitles() {
        let panes = SettingsPanes.scan()
        #expect(panes.count > 20)
        #expect(panes.contains { $0.title == "Displays" })
        #expect(panes.contains { $0.title == "Wi-Fi" })
        #expect(panes.contains { $0.title == "Privacy & Security" })
        #expect(panes.first { $0.title == "Keyboard" }?.url.absoluteString == "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        #expect(Set(panes.map(\.title)).count == panes.count, "titles are unique")
        #expect(panes.allSatisfy { !$0.title.contains(".") && !$0.title.hasSuffix("Extension") && !$0.title.contains("settings") })
    }

    @Test func visibilityHidesCaseInsensitivelyAndHonoursEnabled() {
        let items = ["Game Center", "Displays"]
        #expect(Visibility(true, hidden: ["game center"]).filter(items) { [$0] } == ["Displays"])
        #expect(Visibility(false, hidden: []).filter(items) { [$0] }.isEmpty)
        #expect(Visibility(true, hidden: []).filter(items) { [$0] } == items)
    }

    @Test func settingsPanesConfigDecodes() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"settingsPanes": {"hidden": ["Game Center"]}}"#.utf8))
        #expect(config.settingsPanes.hidden == ["Game Center"])
        #expect(config.settingsPanes.enabled)
    }
}
