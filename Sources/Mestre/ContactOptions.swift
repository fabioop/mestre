import MestreCore
import SwiftUI

/// Settings › Features › Contacts.
struct ContactOptions: View {
    @ObservedObject var settings: ConfigStore

    private static let defaultActions = ContactActions.Kind.allCases.map { (value: $0, title: $0.title) }

    var body: some View {
        KeywordField(label: "Keyword", value: $settings.config.contacts.keyword, placeholder: "contact").setting("contacts.keyword")
        Toggle("Also answer ordinary searches", isOn: $settings.config.contacts.searchEverywhere).setting("contacts.everywhere")
        PresetPicker(label: "Return", value: $settings.config.contacts.defaultAction, options: Self.defaultActions).setting("contacts.default")
        Caption("macOS asks for access the first time you use the keyword. Contacts stay in memory on this Mac; photos aren't read.")
    }
}
