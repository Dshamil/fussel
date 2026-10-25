import SwiftUI
import AppKit

@main
struct FusselApp: App {
    @State private var model = AppModel()
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    init() {
        // Used by the build pipeline to render screenshots of every style.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-previews"), i + 1 < args.count {
            PreviewRenderer.renderAll(to: args[i + 1])
            exit(0)
        }
    }

    var body: some Scene {
        Window("Fussel", id: "main") {
            StyledRoot {
                ContentView()
            }
            .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 550)
        .commands {
            FusselCommands(model: model)
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            StyledRoot {
                MenuBarView()
            }
            .environment(model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("Fussel")
        }
        .menuBarExtraStyle(.window)

        Settings {
            StyledRoot {
                SettingsView()
            }
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
