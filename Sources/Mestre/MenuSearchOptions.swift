import SwiftUI
import MestreCore

/// Settings › Features › Menu Search. The rest of `menus` is file-only (docs/configuration.md).
struct MenuSearchOptions: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        KeywordField(label: "Keyword", value: $settings.config.menus.keyword, placeholder: "menu").setting("menus.keyword")
        Toggle("Menu items in ordinary searches", isOn: $settings.config.menus.searchEverywhere).setting("menus.everywhere")
        PresetPicker(label: "Submenu levels read", value: $settings.config.menus.maxDepth,
                     options: [(1, "Top menus only"), (2, "2"), (3, "3"), (4, "4"), (6, "6")])
            .setting("menus.depth")
        AccessibilityAccessRow().setting("menus.permission")
        Caption("Reads the menus of the app in front when \(settings.config.menus.readOnOpen ? "the panel opens" : "the keyword is typed"). Disabled items are left out.")
    }
}

/// "Accessibility access: Granted / Grant…", for every feature page that needs it.
struct AccessibilityAccessRow: View {
    @State private var isGranted = Accessibility.isTrusted

    var body: some View {
        LabeledContent("Accessibility access") {
            if isGranted {
                Text("Granted").foregroundStyle(.secondary)
            } else {
                Button("Grant…") { Accessibility.requestAccess() }
            }
        }
        .onAppear { isGranted = Accessibility.isTrusted }
    }
}
