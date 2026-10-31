import SwiftUI

/// "Launch at login" switch backed by SMAppService; shared by Settings and the welcome window.
struct LaunchAtLoginToggle: View {
    let settings: ConfigStore
    @State private var enabled = LaunchAtLogin.isEnabled
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at login", isOn: binding)
                .disabled(!LaunchAtLogin.isAvailable)
            if !LaunchAtLogin.isAvailable {
                Caption("Available when running from the .app bundle (make bundle).")
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        // Settings and the welcome window each have one; the status can change in the other
        // or in System Settings, and showing a window activates the app.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            enabled = LaunchAtLogin.isEnabled
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { enabled },
            set: { wanted in
                do {
                    try LaunchAtLogin.setEnabled(wanted)
                    enabled = wanted
                    settings.config.startup.launchAtLogin = wanted
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                }
            }
        )
    }
}
