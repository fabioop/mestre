import MestreCore
import SwiftUI

/// Settings › Features › Reminders.
struct ReminderOptions: View {
    @ObservedObject var settings: ConfigStore
    let provider: RemindersProvider
    @State private var lists: [String] = []
    @State private var hasAccess = false

    var body: some View {
        KeywordField(label: "Keyword", value: $settings.config.reminders.keyword, placeholder: "remind").setting("reminders.keyword")
        KeywordField(label: "Open reminders", value: $settings.config.reminders.listKeyword, placeholder: "todo").setting("reminders.listKeyword")
        Group {
            if !hasAccess {
                LabeledContent("New reminders go to") {
                    Button("Allow Reminders Access…") {
                        Task {
                            await provider.requestAccess()
                            await refresh()
                        }
                    }
                }
            } else {
                Picker("New reminders go to", selection: $settings.config.reminders.defaultList) {
                    Text("Default list").tag("")
                    ForEach(lists, id: \.self) { Text($0).tag($0) }
                    // A name in the file that matches no list still shows as chosen.
                    let chosen = settings.config.reminders.defaultList
                    if !chosen.isEmpty, !lists.contains(chosen) { Text(chosen).tag(chosen) }
                }
            }
        }
        .setting("reminders.defaultList")
        CommittedField(label: "Time for a day alone", value: $settings.config.reminders.defaultTime,
                       render: { $0 },
                       parse: Config.Reminders.validTime,
                       placeholder: "all day", width: 80)
            .setting("reminders.defaultTime")
        Toggle("Show on the home screen", isOn: shownInHome)
        Caption("remind call mum fri 5pm adds one; ! to !!! set the priority and #list picks the list. Empty time leaves a reminder with only a day all-day. macOS asks for access the first time you use the keyword.")
            .task { await refresh() }
    }

    /// Edits `home.hidden`, the one list of rows left off the home screen.
    private var shownInHome: Binding<Bool> {
        Binding(
            get: { !Visibility(true, hidden: settings.config.home.hidden).hides([provider.id]) },
            set: { shown in
                settings.config.home.hidden.removeAll { $0.lowercased() == provider.id }
                if !shown { settings.config.home.hidden.append(provider.id) }
            })
    }

    private func refresh() async {
        hasAccess = provider.hasAccess
        // Two accounts can both have a "Reminders"; the picker names it once.
        var seen = Set<String>()
        lists = await provider.listNames().filter { seen.insert($0).inserted }
    }
}
