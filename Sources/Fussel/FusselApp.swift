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
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 580)
        .commands {
            FusselCommands(model: model)
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environment(model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("Fussel")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

/// Every main action is also reachable from the menu bar, with keyboard shortcuts.
struct FusselCommands: Commands {
    let model: AppModel

    private var busy: Bool {
        model.stage == .scanning || model.stage == .cleaning
    }

    var body: some Commands {
        CommandMenu("Clean") {
            Button("Scan Mac") {
                Task { await model.smartScan() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(busy)

            Button("Clean Selected Items…") {
                model.confirmCleanRequested = true
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(busy || model.selectedTotal == 0)

            Divider()

            Button("Open Full Disk Access Settings…") {
                Permissions.openFullDiskAccessSettings()
            }
        }
    }
}
