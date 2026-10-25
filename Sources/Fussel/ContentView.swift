import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @State private var selection: Module? = .junk

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Module.allCases) { module in
                    Label(module.title, systemImage: module.symbol)
                        .font(.rounded(13, .medium))
                        .tag(module)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .safeAreaInset(edge: .bottom) {
                if !app.hasFullDiskAccess {
                    FullDiskAccessHint()
                        .padding(12)
                }
            }
        } detail: {
            Group {
                switch selection {
                case .uninstaller:
                    UninstallerView(model: app.uninstaller)
                case let module?:
                    ModuleView(model: app.model(for: module))
                case nil:
                    FusselMascot(mood: .idle, size: 120)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshAccess()
        }
    }
}

struct FullDiskAccessHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Full Disk Access", systemImage: "lock")
                .font(.rounded(12, .semibold))
            Text("Allow it so Fussel can see the Trash and every hidden speck.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary))
    }
}
