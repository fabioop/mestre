import AppKit
import MestreCore

@main
@MainActor
enum MestreApp {
    // NSApplication.delegate is weak, so the delegate must be owned here.
    private static let delegate = AppDelegate()

    static func main() {
        // `mestre --show-config [--default] [--docs]`: print and leave before the app, the config
        // store (which writes on first launch) or the panel exist.
        let arguments = CommandLine.arguments
        if arguments.contains("--show-config") {
            let config = arguments.contains("--default") ? Config() : ConfigStore.readCurrent()
            do {
                print(try ConfigDocs.dump(config, docs: arguments.contains("--docs")), terminator: "")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Could not encode the config: \(error)\n".utf8))
                exit(1)
            }
        }
        let app = NSApplication.shared
        app.delegate = delegate
        // Menu-bar app: no Dock icon, no app menu. LSUIElement in Info.plist does the
        // same for the bundled build; this covers `swift run` too.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
