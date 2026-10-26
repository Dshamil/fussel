import SwiftUI
import AppKit

struct UninstallerView: View {
    let model: UninstallerModel
    @Environment(\.palette) private var palette
    @State private var search = ""
    @State private var confirming = false
    @State private var askToQuit = false
    @FocusState private var listFocused: Bool

    private var filteredApps: [InstalledApp] {
        guard !search.isEmpty else { return model.apps }
        return model.apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HStack(spacing: 0) {
            appList
                .frame(width: 260)
            Rectangle().fill(palette.cardStroke).frame(width: 1)
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
                .padding(12)
            if model.loadingApps {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            } else {
                // A plain list in the style's own colors, picked like a row in the sidebar.
                // Once an app is picked, the arrow keys move through the list.
                ScrollViewReader { scroller in
                    PreviewSafeScroll {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredApps) { app in
                                AppRow(app: app, selected: model.selectedApp == app) {
                                    listFocused = true
                                    Task { await model.select(app) }
                                }
                                .id(app.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                    .focusable()
                    .focusEffectDisabled()
                    .focused($listFocused)
                    .onKeyPress(.downArrow) { step(1, scroller); return .handled }
                    .onKeyPress(.upArrow) { step(-1, scroller); return .handled }
                }
            }
        }
    }

    /// Picks the app above or below the current one and keeps it in view.
    private func step(_ offset: Int, _ scroller: ScrollViewProxy) {
        let apps = filteredApps
        guard !apps.isEmpty else { return }
        let current = model.selectedApp.flatMap { apps.firstIndex(of: $0) }
        let next = min(max((current ?? -1) + offset, 0), apps.count - 1)
        let app = apps[next]
        scroller.scrollTo(app.id)
        Task { await model.select(app) }
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
                    .font(.rounded(22, .bold))
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
            .padding(.vertical, 16)

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
                // Let the style's own background show instead of the list's.
                .scrollContentBackground(.hidden)
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

/// One app in the Uninstaller's list: icon and name, highlighted like a sidebar row.
private struct AppRow: View {
    let app: InstalledApp
    let selected: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 24, height: 24)
            Text(app.name)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(palette.text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selected ? palette.selection : (hovering ? palette.selection.opacity(0.5) : .clear)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { action() }
    }
}
