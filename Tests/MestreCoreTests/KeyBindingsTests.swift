import AppKit
import Carbon.HIToolbox
import Testing
@testable import MestreCore

@Suite struct KeyBindingsTests {
    let codes: [Character: UInt16] = ["p": 35, "n": 45, "q": 12, "k": 40, "h": 4, "c": 8, "w": 13]
    let registry = ActionTable(providerActions: [("apps", [
        ItemAction(id: "quit", title: "Quit", defaultKeys: ["cmd+q"]), ItemAction(id: "hide", title: "Hide", defaultKeys: ["cmd+h"]),
        .reveal, .copyPath,
    ])])

    @Test func defaultsCoverPanelAndItemActions() {
        let bindings = KeyBindings(keys: Config.Keys(), actions: registry, keyCodes: codes)
        #expect(bindings.binding(forKeyCode: UInt16(kVK_UpArrow), modifiers: []) == .panel(.moveUp))
        #expect(bindings.binding(forKeyCode: 35, modifiers: .control) == .panel(.moveUp))
        #expect(bindings.binding(forKeyCode: UInt16(kVK_Return), modifiers: []) == .panel(.open))
        #expect(bindings.binding(forKeyCode: 40, modifiers: .command) == .panel(.actions))
        #expect(bindings.binding(forKeyCode: UInt16(kVK_Return), modifiers: .command) == .item("reveal"))
        #expect(bindings.binding(forKeyCode: 12, modifiers: .command) == .item("quit"))
        #expect(bindings.binding(forKeyCode: 8, modifiers: [.command, .shift]) == .item("copyPath"))
        #expect(bindings.binding(forKeyCode: UInt16(kVK_Escape), modifiers: []) == .panel(.close))
        #expect(bindings.invalid.isEmpty && bindings.conflicts.isEmpty && bindings.unknownActions.isEmpty)
        #expect(bindings.hint(for: ItemAction(id: "quit", title: "Quit"), isDefault: false) == "⌘Q")
        #expect(bindings.hint(for: ItemAction(id: "open", title: "Open"), isDefault: true) == "↩")
        #expect(bindings.effective.count == PanelAction.allCases.count + 4)
    }

    @Test func ignoresIrrelevantModifiersAndUnboundKeys() {
        let bindings = KeyBindings(keys: Config.Keys(), actions: registry, keyCodes: codes)
        #expect(bindings.binding(forKeyCode: UInt16(kVK_UpArrow), modifiers: [.numericPad, .function]) == .panel(.moveUp))
        #expect(bindings.binding(forKeyCode: UInt16(kVK_UpArrow), modifiers: .shift) == nil)
        #expect(bindings.binding(forKeyCode: 12, modifiers: []) == nil)
    }

    @Test func overridesReplaceDefaultsAndReportBadOnes() {
        var keys = Config.Keys()
        keys[.open] = ["tab", "nonsense+key"]
        keys["copyPath"] = ["cmd+shift+p"]
        let bindings = KeyBindings(keys: keys, actions: registry, keyCodes: codes)
        #expect(bindings.binding(forKeyCode: UInt16(kVK_Tab), modifiers: []) == .panel(.open))
        #expect(bindings.binding(forKeyCode: UInt16(kVK_Return), modifiers: []) == nil)
        #expect(bindings.binding(forKeyCode: 35, modifiers: [.command, .shift]) == .item("copyPath"))
        #expect(bindings.binding(forKeyCode: 8, modifiers: [.command, .shift]) == nil)
        #expect(bindings.invalid == ["nonsense+key"])
        #expect(bindings.hint(for: .open) == "⇥")
        #expect(bindings.effective.first { $0.name == "open" }?.isOverride == true)
    }

    @Test func userOverrideBeatsADefaultOnTheSameKey() {
        var keys = Config.Keys()
        keys["copyPath"] = ["return"]  // the default for open
        let bindings = KeyBindings(keys: keys, actions: registry, keyCodes: codes)
        #expect(bindings.binding(forKeyCode: UInt16(kVK_Return), modifiers: []) == .item("copyPath"))
        #expect(bindings.conflicts == ["return"])
        #expect(bindings.hint(for: .open) == nil)
    }

    @Test func unknownNamesAreReportedAndNotBound() {
        var keys = Config.Keys()
        keys["qiut"] = ["cmd+q"]
        let bindings = KeyBindings(keys: keys, actions: registry, keyCodes: codes)
        #expect(bindings.unknownActions == ["qiut"])
        #expect(bindings.binding(forKeyCode: 12, modifiers: .command) == .item("quit"))
    }

    @Test func keysSectionDecodesOverridesOnly() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"keys": {"quit": ["cmd+w"], "close": "cmd+."}}"#.utf8))
        #expect(config.keys["quit"] == ["cmd+w"])
        #expect(config.keys[.close] == ["cmd+."])
        #expect(config.keys[.open] == nil)
    }

    @Test func emptyKeysEncodeAsEmptyObject() throws {
        let data = try JSONEncoder().encode(Config.Keys())
        #expect(String(decoding: data, as: UTF8.self) == "{}")
    }
}

@Suite struct ActionTableTests {
    private let quit = ItemAction(id: "quit", title: "Quit", icon: "xmark.circle", defaultKeys: ["cmd+q"])
    private let quickLook = ItemAction(id: "quickLook", title: "Quick Look", icon: "eye", defaultKeys: ["cmd+y"])

    @Test func panelActionsComeFirstThenProvidersMergeByID() {
        let table = ActionTable(providerActions: [("apps", [quit, .reveal]), ("files", [.reveal, quickLook])])
        #expect(table.entries.prefix(PanelAction.allCases.count).map(\.id) == PanelAction.allCases.map(\.rawValue))
        #expect(table["reveal"]?.providers == ["apps", "files"])
        #expect(table["reveal"]?.defaultKeys == ["cmd+return"])
        #expect(table["quickLook"]?.title == "Quick Look" && table["quickLook"]?.providers == ["files"])
        #expect(table["open"]?.isPanel == true && table["quit"]?.isPanel == false)
    }

    @Test func bindingsComeFromTheTableAndOverridesAreMarked() {
        let table = ActionTable(providerActions: [("apps", [quit, .reveal, ItemAction(id: "hide", title: "Hide")])])
        var keys = Config.Keys(); keys["quit"] = ["cmd+w"]; keys["hide"] = ["cmd+h"]
        let bindings = KeyBindings(keys: keys, actions: table, keyCodes: ["w": 13, "h": 4])
        #expect(bindings.combos(for: "quit")?.combos == ["cmd+w"] && bindings.combos(for: "quit")?.isOverride == true)
        #expect(bindings.combos(for: "hide")?.combos == ["cmd+h"])
        #expect(bindings.combos(for: "reveal")?.isOverride == false)
        #expect(bindings.combos(for: "nothing") == nil && bindings.unknownActions.isEmpty)
    }
}

@Suite struct QuickKeysTests {
    @Test func generatesInitialsThenFallsBack() {
        let keys = QuickKeys.assign(titles: [("lockScreen", "Lock Screen"), ("logOut", "Log Out"), ("sleep", "Sleep"), ("shutDown", "Shut Down")], overrides: [:])
        #expect(keys["lockScreen"] == "ls" && keys["logOut"] == "lo")  // initials of "Log Out"
        #expect(keys["sleep"] == "sl" && keys["shutDown"] == "sd")
    }

    @Test func userKeysWinAndBlockGeneratedOnes() {
        let keys = QuickKeys.assign(titles: [("sleep", "Sleep"), ("slack", "Slack")], overrides: ["sl": "slack", "zz": "nothing", "sa": "slack"])
        #expect(keys["slack"] == "sa" && keys["sleep"] == "se")  // "sa" < "sl", so it wins; "sl" stays reserved
        #expect(!keys.values.contains("zz"))
    }

    @Test func collisionsPickTheNextCandidate() {
        let keys = QuickKeys.assign(titles: [("a", "Clipboard History"), ("b", "Colour Converter"), ("c", "Calculator")], overrides: [:])
        #expect(keys["a"] == "ch" && keys["b"] == "cc" && keys["c"] == "ca")
        #expect(Set(keys.values).count == 3)
    }
}

@Suite struct CompletionActionTests {
    @Test func tabAndArrowsAreBoundByDefault() {
        let bindings = KeyBindings(keys: Config.Keys(), actions: ActionTable())
        #expect(bindings.binding(forKeyCode: UInt16(kVK_Tab), modifiers: []) == .panel(.complete))
        #expect(bindings.binding(forKeyCode: UInt16(kVK_LeftArrow), modifiers: []) == .panel(.moveLeft))
        #expect(bindings.hint(for: .complete) == "⇥")
        #expect(bindings.binding(forKeyCode: UInt16(kVK_Delete), modifiers: []) == .panel(.back))
    }
}

@Suite struct DefaultKeyConflictTests {
    @Test func twoItemActionsWithOneDefaultKeyAreReportedAsAConflict() {
        let a = ItemAction(id: "copyPath", title: "Copy Path", defaultKeys: ["cmd+shift+c"])
        let b = ItemAction(id: "copyArgument", title: "Copy Argument", defaultKeys: ["cmd+shift+c"])
        let bindings = KeyBindings(keys: Config.Keys(), actions: ActionTable(providerActions: [("files", [a]), ("scripts", [b])]), keyCodes: ["c": 8])
        #expect(bindings.conflicts == ["cmd+shift+c"])
        #expect(bindings.binding(forKeyCode: 8, modifiers: [.command, .shift]) == .item("copyArgument"))  // alphabetical: the wrong one wins
    }

    @Test func anItemActionNamedLikeAPanelActionMergesIntoIt() {
        let table = ActionTable(providerActions: [("scripts", [ItemAction(id: "complete", title: "Complete")])])
        #expect(table["complete"]?.isPanel == true && table["complete"]?.title == "Complete or Unfold")
    }
}
