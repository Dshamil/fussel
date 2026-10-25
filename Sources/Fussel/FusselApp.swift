import SwiftUI

@main
struct FusselApp: App {
    @State private var model = AppModel()
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        Window("Fussel", id: "main") {
            ContentView()
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environment(model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
