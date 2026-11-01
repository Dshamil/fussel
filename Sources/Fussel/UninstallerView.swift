import SwiftUI
import AppKit

struct UninstallerView: View {
    let model: UninstallerModel
    @Environment(\.palette) private var palette
    @State private var search = ""
    @State private var confirming = false
    @State private var askToQuit = false
    @FocusState private var listFocused: Bool
    @State private var dropping = PreviewRenderer.uninstallerDrop.targeted
    @State private var refusal = PreviewRenderer.uninstallerDrop.refusal
    /// Goes up by one for each refused drop, which shakes the note.
    @State private var shakes = 0

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
        .overlay { if dropping { dropTarget.transition(.opacity) } }
        .overlay(alignment: .bottom) {
            if let refusal {
                Text(refusal.message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(palette.sheet))
                    .overlay(Capsule().strokeBorder(palette.cardStroke, lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .modifier(HeadShake(shakes: CGFloat(shakes)))
                    // Above the row with the Uninstall button.
                    .padding(.bottom, 64)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .modifier(AppDrop(take: { url in Task { await take(url) } },
                          targeted: { inside in withAnimation(.easeOut(duration: 0.15)) { dropping = inside } }))
        .task {
            if model.apps.isEmpty { await model.loadApps() }
        }
    }

    /// While an app is dragged over the window: one quiet frame around everything.
    private var dropTarget: some View {
        ZStack {
            palette.content.opacity(0.85)
            RoundedRectangle(cornerRadius: palette.radius(14), style: .continuous)
                .strokeBorder(palette.accent(.uninstaller), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                .padding(16)
            VStack(spacing: 10) {
                ToolIcon(module: .uninstaller, size: 44)
                Text("Drop to see what it left behind")
                    .font(.rounded(17, .bold))
                    .foregroundStyle(palette.text)
                Text("Nothing is removed until you say so.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
        }
        .allowsHitTesting(false)
    }

    /// Opens a dropped app as if it had been picked from the list, or says why not.
    private func take(_ url: URL) async {
        if model.apps.isEmpty { await model.loadApps() }
        switch UninstallerModel.dropped(url, among: model.apps) {
        case .success(let app):
            search = ""
            withAnimation(.spring(duration: 0.25)) { refusal = nil }
            await model.select(app)
        case .failure(let reason):
            Sounds.play("Funk")
            withAnimation(.spring(duration: 0.25)) { refusal = reason }
            withAnimation(.linear(duration: 0.4)) { shakes += 1 }
            try? await Task.sleep(for: .seconds(3))
            if refusal == reason { withAnimation(.easeOut(duration: 0.25)) { refusal = nil } }
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
                    .onChange(of: model.selectedApp) { _, app in
                        if let app { withAnimation { scroller.scrollTo(app.id) } }
                    }
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
                Text("Pick an app, or drag one here")
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
                .animation(.spring(duration: 0.35, bounce: 0.2), value: model.selectedSize)
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

/// Takes a file dragged onto the view. Screenshots can't draw the system's drop area, so they go without.
private struct AppDrop: ViewModifier {
    let take: (URL) -> Void
    let targeted: (Bool) -> Void

    func body(content: Content) -> some View {
        if PreviewRenderer.isRendering {
            content
        } else {
            content.dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                take(url)
                return true
            } isTargeted: { targeted($0) }
        }
    }
}

/// A small shake of the head.
private struct HeadShake: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(shakes * .pi * 6) * (1 - shakes.truncatingRemainder(dividingBy: 1)), y: 0))
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
