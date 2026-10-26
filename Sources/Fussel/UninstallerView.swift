import SwiftUI
import AppKit

struct UninstallerView: View {
    let model: UninstallerModel
    @State private var search = ""
    @State private var confirming = false
    @State private var askToQuit = false

    private var filteredApps: [InstalledApp] {
        guard !search.isEmpty else { return model.apps }
        return model.apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HStack(spacing: 0) {
            appList
                .frame(width: 260)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            if model.apps.isEmpty { await model.loadApps() }
        }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            TextField("Search apps", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            if model.loadingApps {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            } else {
                List(filteredApps, selection: Binding(
                    get: { model.selectedApp },
                    set: { app in Task { await model.select(app) } }
                )) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable()
                            .frame(width: 24, height: 24)
                        Text(app.name)
                            .lineLimit(1)
                    }
                    .tag(app)
                }
                .listStyle(.sidebar)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if model.working {
            BusyState(text: "Saying goodbye…")
        } else if let app = model.selectedApp {
            appDetail(app)
        } else if let result = model.lastResult {
            VStack(spacing: 16) {
                StateIcon(symbol: "checkmark", celebrate: true, size: 96)
                Text("\(result.name) is gone")
                    .font(.rounded(24, .bold))
                Text("Fussel cleared \(result.freed.byteString).")
                    .foregroundStyle(.secondary)
                if !result.failures.isEmpty {
                    Text("\(result.failures.count) item(s) couldn't be removed. Apps in /Applications may need your admin password: try dragging them to the Trash in Finder.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
            }
        } else {
            VStack(spacing: 18) {
                StateIcon(symbol: "xmark.bin", size: 96)
                Text("Pick an app to remove")
                    .font(.rounded(22, .bold))
                Text("Fussel finds its support files, caches and preferences too.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func appDetail(_ app: InstalledApp) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.rounded(22, .bold))
                    Text(app.bundleID)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider()

            if model.loadingLeftovers {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            } else {
                List {
                    ForEach(model.leftovers) { item in
                        ItemRow(
                            item: item,
                            isOn: Binding(
                                get: { model.selected.contains(item.url) },
                                set: { model.setSelected(item, $0) }
                            )
                        )
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Text("Removed files go to the Trash.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Uninstall \(model.selectedSize.byteString)") {
                    if model.isRunning(app) { askToQuit = true } else { confirming = true }
                }
                .buttonStyle(ActionButtonStyle())
                .disabled(model.selected.isEmpty || model.loadingLeftovers)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .confirmationDialog("Uninstall \(app.name)?", isPresented: $confirming) {
            Button("Move to Trash") { Task { await model.uninstall() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(model.selected.count) items (\(model.selectedSize.byteString)) will be moved to the Trash.")
        }
        .alert("\(app.name) is still running", isPresented: $askToQuit) {
            Button("Quit \(app.name)") { model.quit(app) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Quit the app first, then uninstall it.")
        }
    }
}
