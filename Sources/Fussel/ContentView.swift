import SwiftUI
import AppKit

enum FirstLaunch {
    static let seen = "tutorialSeen"
}

/// What the main area shows: the overview, one tool, or the settings.
enum Page: Hashable {
    case overview
    case tool(Module)
    case settings
}

/// Fussel's window: a sidebar with the tools on the left, the selected page on the right.
struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var page: Page
    @State private var didAutoScan = false
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceChoice.system.rawValue
    @AppStorage("sidebarWidth") private var sidebarWidth = 248.0

    init(page: Page = .overview) {
        _page = State(initialValue: page)
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if appearance == AppearanceChoice.oreo.rawValue {
                    // Oreo: the sidebar stays light while the rest of the window is dark.
                    Sidebar(page: $page)
                        .environment(\.palette, .oreoSide)
                        .environment(\.colorScheme, .light)
                } else {
                    Sidebar(page: $page)
                }
            }
            .frame(width: sidebarWidth)
            SidebarDivider(width: $sidebarWidth)
            Group {
                switch page {
                case .overview: OverviewPage(page: $page)
                case .tool(let module): ToolPage(module: module)
                case .settings: SettingsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(palette.content)
            .id(page)
            .transition(.opacity.combined(with: .offset(y: 6)))
        }
        .animation(.easeOut(duration: 0.2), value: page)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background { if palette.isGlass { GlassBackdrop() } else { palette.content } }
        .overlay { if app.showTutorial { Tutorial().transition(.opacity) } }
        .overlay { if app.showPermissions { PermissionsView().transition(.opacity) } }
        .environment(\.animationsPaused, !app.windowVisible)
        .onAppear {
            UserDefaults.standard.set(true, forKey: FirstLaunch.seen)
            // Like opening the app should: Fussel takes a look right away.
            if !didAutoScan, app.stage == .idle, !PreviewRenderer.isRendering {
                didAutoScan = true
                Task { await app.smartScan() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshAccess()
        }
    }
}

// MARK: - Sidebar

/// The line between the sidebar and the page. Drag it to make the sidebar wider or narrower;
/// double-click it to go back to the usual width. The width is remembered.
private struct SidebarDivider: View {
    @Binding var width: Double
    @Environment(\.palette) private var palette
    @State private var start: Double?
    @State private var hovering = false

    static let range = 200.0...340.0
    static let standard = 248.0

    var body: some View {
        Rectangle()
            .fill(hovering || start != nil ? palette.secondary.opacity(0.5) : palette.cardStroke)
            .frame(width: 1)
            // A wider, invisible strip to grab, so the 1 pt line is easy to hit.
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hovering = inside
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            if start == nil { start = width }
                            width = min(max((start ?? width) + drag.translation.width, Self.range.lowerBound),
                                        Self.range.upperBound)
                        }
                        .onEnded { _ in start = nil })
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(duration: 0.25)) { width = Self.standard }
                    }
            }
            .animation(.easeOut(duration: 0.15), value: hovering)
            // Run all the way up under the title bar, like the backgrounds on either side.
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .zIndex(1)
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Binding var page: Page

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                SidebarFussel(busy: app.stage == .scanning || app.stage == .cleaning)
                // The wordmark: SF Pro Rounded Heavy, set a little tight.
                Text("Fussel")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(palette.text)
            }
            .padding(.leading, 16)
            .padding(.top, 40)
            .padding(.bottom, 16)

            row(.overview, title: "Overview", symbol: "square.grid.2x2", trailing: nil)
            section("Clean")
            toolRow(.junk)
            toolRow(.tidy)
            section("Review")
            toolRow(.large)
            toolRow(.uninstaller)
            toolRow(.updates)

            Spacer(minLength: 12)

            row(.settings, title: "Settings", symbol: "gearshape", trailing: nil)
            HistoryRow()
            // The overview shows the disk and its Clean button right in the page, so the sidebar
            // doesn't repeat them there; every other page keeps this summary.
            if page != .overview {
                DiskSummary()
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 16)
        .animation(.easeOut(duration: 0.2), value: page == .overview)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.sidebar)
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.secondary)
            .padding(.leading, 24)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    private func toolRow(_ module: Module) -> some View {
        row(.tool(module), title: module.sidebarTitle, symbol: module.symbol, trailing: summary(for: module))
    }

    private func row(_ target: Page, title: String, symbol: String, trailing: String?) -> some View {
        SidebarRow(title: title, symbol: symbol, trailing: trailing, selected: page == target) {
            page = target
        }
    }

    /// The size (or count) shown next to a tool, once there is something to show.
    private func summary(for module: Module) -> String? {
        switch module {
        case .junk, .large, .tidy:
            let model = app.model(for: module)
            guard model.phase == .results else { return nil }
            return model.items.isEmpty ? "0 KB" : model.totalSize.byteString
        case .uninstaller:
            return app.uninstaller.apps.isEmpty ? nil : "\(app.uninstaller.apps.count) apps"
        case .updates:
            return app.appUpdates.updates.isEmpty ? nil : "\(app.appUpdates.updates.count)"
        }
    }
}

private struct SidebarRow: View {
    @Environment(\.palette) private var palette
    let title: String
    let symbol: String
    let trailing: String?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(selected ? palette.text : palette.secondary)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(palette.secondary)
                        .contentTransition(.numericText())
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? palette.selection : (hovering ? palette.selection.opacity(0.5) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.spring(duration: 0.4), value: trailing)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The Fussel badge at the top of the sidebar. Blinks now and then, flicks his curl when you point at him,
/// swings it while he scans, hops when clicked, smiles after cleaning and gets sleepy on a low battery.
private struct SidebarFussel: View {
    let busy: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationsPaused) private var paused
    @State private var blink = false
    @State private var hovering = false
    @State private var cheering = false

    private var mood: MascotMood {
        if busy { return .busy }
        if cheering { return .happy }
        return app.healthMood == .sleepy ? .sleepy : .idle
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.graphite)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(palette.isDark ? 0.14 : 0), lineWidth: 1))
            // While scanning the curl swings ±16° every 1.1 s; frames only run during the scan.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !busy || reduceMotion || paused)) { timeline in
                let swing = 16 * sin(timeline.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.1)
                FusselBody(mood: mood, blink: blink && !cheering,
                           curlTilt: busy && !reduceMotion ? swing : (hovering ? -18 : 0))
                    .equatable()
                    .frame(width: 28, height: 28)
            }
            .offset(y: cheering && !reduceMotion ? -3 : 0)
        }
        .frame(width: 28, height: 28)
        .scaleEffect(hovering ? 1.1 : 1)
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.spring(duration: 0.3, bounce: 0.5)) { hovering = inside } }
        .onTapGesture {
            Sounds.play("Pop")
            cheer(for: 1.2)
        }
        .onChange(of: app.stage) { _, stage in
            if case .done(let freed, _) = stage, freed > 0 { cheer(for: 2.4) }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 3...6)))
                blink = true
                try? await Task.sleep(for: .milliseconds(140))
                blink = false
            }
        }
        .help("Hi, I'm Fussel!")
        .accessibilityHidden(true)
    }

    private func cheer(for seconds: Double) {
        withAnimation(.spring(duration: 0.35, bounce: 0.6)) { cheering = true }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            withAnimation(.spring(duration: 0.4)) { cheering = false }
        }
    }
}

/// Free space and the one-click clean at the bottom of the sidebar.
private struct DiskSummary: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var confirming = false

    var body: some View {
        let s = app.monitor.sample
        let used = s.diskTotal > 0 ? 1 - Double(s.diskFree) / Double(s.diskTotal) : 0
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.text.opacity(0.1))
                    Capsule().fill(palette.secondary)
                        .frame(width: geo.size.width * used)
                        .animation(.spring(duration: 0.9), value: used)
                }
            }
            .frame(height: 5)
            HStack {
                Text("\(Int64(Double(s.diskTotal) * used).byteString) used")
                Spacer()
                Text("\(s.diskFree.byteString) free")
            }
            .font(.system(size: 11))
            .foregroundStyle(palette.secondary)
            .monospacedDigit()
            if app.selectedTotal > 0 {
                HStack {
                    Label("Safe to clean", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Palette.safe)
                    Spacer()
                    CountingBytes(value: Double(app.selectedTotal))
                        .animation(.easeOut(duration: 0.8), value: app.selectedTotal)
                        .foregroundStyle(palette.text)
                }
                .font(.system(size: 12, weight: .semibold))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Button {
                confirming = true
            } label: {
                Label("Clean Safe Items", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(app.selectedTotal == 0 || app.stage == .cleaning)
        }
        .animation(.spring(duration: 0.4), value: app.selectedTotal > 0)
        .cleanConfirmation(isPresented: $confirming)
    }
}

/// The clean-up history, from a row at the bottom of the sidebar.
private struct HistoryRow: View {
    @Environment(AppModel.self) private var app
    @State private var showing = false

    var body: some View {
        SidebarRow(title: "History", symbol: "clock.arrow.circlepath", trailing: nil, selected: false) {
            showing = true
        }
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            HistoryList().environment(app)
        }
    }
}

extension View {
    /// Asks before cleaning everything that's selected, and says what happens to it.
    func cleanConfirmation(isPresented: Binding<Bool>) -> some View {
        modifier(CleanConfirmation(isPresented: isPresented))
    }
}

private struct CleanConfirmation: ViewModifier {
    @Environment(AppModel.self) private var app
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.confirmationDialog("Clean \(app.selectedTotal.byteString)?", isPresented: $isPresented) {
            Button(app.selectionIncludesPermanent ? "Clean and Delete Permanently" : "Move to Trash",
                   role: app.selectionIncludesPermanent ? .destructive : nil) {
                Task { await app.cleanAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(app.selectionIncludesPermanent
                 ? "Items already in the Trash are deleted permanently. Everything else goes to the Trash."
                 : "Everything selected goes to the Trash, so you can still change your mind.")
        }
    }
}

// MARK: - Page header

/// Title, a line of detail and the page's actions, at the top of every page.
struct PageHeader<Actions: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(palette.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) { actions }
        }
        .padding(.horizontal, 32)
        .padding(.top, 32)
        .padding(.bottom, 16)
    }
}

// MARK: - Overview

private struct OverviewPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Binding var page: Page
    @State private var confirming = false
    /// Screenshots show the finished state right away; the app animates into it.
    @State private var shown = PreviewRenderer.isRendering
    @State private var celebrations = 0

    var body: some View {
        let s = app.monitor.sample
        let usedBytes = max(0, s.diskTotal - s.diskFree)
        PreviewSafeScroll {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Overview", subtitle: status) {
                    Button { Task { await app.smartScan() } } label: {
                        Label("Scan", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(app.stage == .scanning || app.stage == .cleaning)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    Button { confirming = true } label: {
                        Label(app.selectedTotal > 0 ? "Clean \(app.selectedTotal.byteString)" : "Clean", systemImage: "trash")
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(app.selectedTotal == 0 || app.stage == .cleaning)
                }

                VStack(alignment: .leading, spacing: 18) {
                    UpdateBanner(updater: app.updater)
                        .animation(.spring(duration: 0.4), value: app.updater.state)
                    if !app.hasFullDiskAccess {
                        AccessBanner()
                    }

                    HStack(alignment: .firstTextBaseline) {
                        CountingBytes(value: shown ? Double(usedBytes) : 0)
                            .animation(.easeOut(duration: 1.0), value: shown)
                            .animation(.easeOut(duration: 1.2), value: usedBytes)
                            .font(.system(size: 30, weight: .bold))
                            .tracking(-0.6)
                            .foregroundStyle(palette.text)
                            .overlay { SparkleBurst(trigger: celebrations) }
                        Text("used of \(s.diskTotal.byteString)")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.secondary)
                        Spacer()
                        Text("\(s.diskFree.byteString) free")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.secondary)
                    }
                    .monospacedDigit()

                    StorageBar(grown: shown)
                        .padding(.top, 4)

                    CategoryList(page: $page, shown: shown)

                    StatsLine()
                        .padding(.top, 2)

                    HStack(alignment: .top, spacing: 16) {
                        BiggestFolders()
                        RecentCleanups()
                            .frame(width: 290)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 1.0, bounce: 0.2).delay(0.1)) { shown = true }
        }
        .task { if app.folders.isEmpty { await app.measureFolders() } }
        .onChange(of: app.hasFullDiskAccess) { _, allowed in
            if allowed { Task { await app.measureFolders() } }
        }
        .onChange(of: app.stage) { _, stage in
            if case .done(let freed, _) = stage, freed > 0 { celebrations += 1 }
        }
        .cleanConfirmation(isPresented: $confirming)
    }

    private var status: String {
        switch app.stage {
        case .idle: return "Not scanned yet"
        case .scanning: return "Scanning…"
        case .cleaning: return "Cleaning…"
        case .ready: return app.foundTotal > 0 ? "Scanned just now · \(app.foundTotal.byteString) found" : "Scanned just now · all clean"
        case .done(let freed, _): return freed > 0 ? "Cleaned \(freed.byteString)" : "All tidy"
        }
    }
}

/// A handful of sparkles that fly out and fade, each time `trigger` goes up. One animation, no timer.
private struct SparkleBurst: View {
    let trigger: Int
    @State private var flying = false
    @State private var visible = false
    private static let colors: [Color] = [Color(hex: 0x3FAE7C), Color(hex: 0xEC7357), Color(hex: 0x8B78EC),
                                          Color(hex: 0xE5A33A), Color(hex: 0x3D8BE0)]

    var body: some View {
        ZStack {
            if visible {
                ForEach(0..<12, id: \.self) { i in
                    let angle = Double(i) / 12 * 2 * .pi + 0.3
                    let reach = 46.0 + Double(i % 3) * 18
                    Image(systemName: i % 2 == 0 ? "sparkle" : "circle.fill")
                        .font(.system(size: i % 2 == 0 ? 13 : 5, weight: .bold))
                        .foregroundStyle(Self.colors[i % Self.colors.count])
                        .offset(x: flying ? cos(angle) * reach * 1.6 : 0, y: flying ? sin(angle) * reach : 0)
                        .scaleEffect(flying ? 0.4 : 1.2)
                        .opacity(flying ? 0 : 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            flying = false
            visible = true
            // Let the sparkles appear at the start first, then send them flying.
            Task {
                try? await Task.sleep(for: .milliseconds(20))
                withAnimation(.easeOut(duration: 1.0)) { flying = true }
                try? await Task.sleep(for: .seconds(1.1))
                visible = false
            }
        }
    }
}

/// One bar for the whole disk, with a slice per tool and the rest of what's used.
private struct StorageBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let grown: Bool

    var body: some View {
        let s = app.monitor.sample
        let total = max(1, Double(s.diskTotal))
        let used = Double(max(0, s.diskTotal - s.diskFree))
        let slices: [(Module, Double)] = [Module.junk, .tidy, .large].map { module in
            let model = app.model(for: module)
            let shown = model.phase == .results || model.phase == .cleaning
            return (module, shown ? Double(model.totalSize) : 0)
        }
        let known = slices.reduce(0) { $0 + $1.1 }
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 1.5) {
                ForEach(slices, id: \.0) { module, bytes in
                    if bytes > 0 {
                        Rectangle()
                            .fill(palette.accent(module))
                            .frame(width: max(3, w * bytes / total))
                            .help("\(module.title): \(Int64(bytes).byteString)")
                    }
                }
                Rectangle()
                    .fill(palette.secondary.opacity(0.55))
                    .frame(width: max(0, w * (used - known) / total))
                    .help("Everything else: \(Int64(max(0, used - known)).byteString)")
                Spacer(minLength: 0)
            }
            .frame(width: grown ? w : 0, alignment: .leading)
            .clipped()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.text.opacity(0.08))
            .overlay { if app.stage == .scanning { Shimmer() } }
            .clipShape(Capsule())
        }
        .frame(height: 10)
        .animation(.spring(duration: 0.8), value: known)
        .accessibilityElement()
        .accessibilityLabel("Disk: \(Int64(used).byteString) used of \(s.diskTotal.byteString)")
    }
}

/// A soft band of light sweeping across, while Fussel is still looking.
private struct Shimmer: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.3)
                .offset(x: phase * geo.size.width)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.1 }
        }
    }
}

/// A row per tool with what it found, its share of the disk and how safe it is to clean.
private struct CategoryList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Binding var page: Page
    let shown: Bool

    private let modules: [Module] = [.junk, .tidy, .large, .uninstaller, .updates]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(modules.enumerated()), id: \.element) { index, module in
                if index > 0 {
                    Rectangle().fill(palette.cardStroke).frame(height: 1).padding(.leading, 58)
                }
                CategoryRow(module: module) { page = .tool(module) }
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 10)
                    .animation(.spring(duration: 0.5, bounce: 0.25).delay(0.05 * Double(index) + 0.15), value: shown)
            }
        }
        .cardSurface(palette, radius: 12)
    }
}

private struct CategoryRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let module: Module
    let open: () -> Void
    @State private var hovering = false
    @State private var bounce = 0

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                ToolIcon(module: module, size: 30, bounce: bounce)
                    .scaleEffect(hovering ? 1.08 : 1)
                    .rotationEffect(.degrees(hovering ? -6 : 0))
                VStack(alignment: .leading, spacing: 2) {
                    // Safe to Clean / Check First belong to single files, so the tools themselves carry no label.
                    Text(module.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                if let share {
                    Text(share)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(palette.secondary)
                }
                Group {
                    if isWorking {
                        Spinner(tint: palette.accent(module))
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text(value)
                            .font(.system(size: 15, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(palette.text)
                            .contentTransition(.numericText())
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .frame(minWidth: 70, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.secondary)
                    .offset(x: hovering ? 3 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(hovering ? palette.text.opacity(0.04) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.spring(duration: 0.3, bounce: 0.4)) { hovering = inside } }
        .animation(.snappy, value: value)
        .animation(.spring(duration: 0.4, bounce: 0.5), value: isWorking)
        // A little hop when a scan for this tool comes back.
        .onChange(of: isWorking) { _, working in if !working { bounce += 1 } }
    }

    private var isWorking: Bool {
        if let model { return model.phase == .scanning || model.phase == .cleaning }
        if module == .updates, case .checking = app.appUpdates.phase { return true }
        return false
    }

    private var model: ModuleModel? {
        switch module {
        case .junk, .large, .tidy: return app.model(for: module)
        default: return nil
        }
    }

    private var value: String {
        if let model {
            switch model.phase {
            case .results: return model.totalSize.byteString
            case .scanning, .cleaning: return "…"
            case .done(let freed, _): return freed > 0 ? freed.byteString : "0 KB"
            case .idle: return "—"
            }
        }
        if module == .uninstaller { return app.uninstaller.apps.isEmpty ? "—" : "\(app.uninstaller.apps.count)" }
        return "\(app.appUpdates.updates.count)"
    }

    private var share: String? {
        guard let model, model.phase == .results, app.monitor.sample.diskTotal > 0 else { return nil }
        let percent = Double(model.totalSize) / Double(app.monitor.sample.diskTotal) * 100
        return String(format: "%.1f %%", percent)
    }

    private var detail: String {
        switch module {
        case .junk, .tidy:
            guard let model else { return "" }
            switch model.phase {
            case .results: return model.items.isEmpty ? "Nothing to clean" : "\(model.selectedSize.byteString) safe to clean"
            case .scanning: return "Looking…"
            case .cleaning: return "Cleaning…"
            case .done(let freed, _): return freed > 0 ? "\(freed.byteString) freed" : "Nothing to clean"
            case .idle: return "Not scanned yet"
            }
        case .large:
            guard let model else { return "" }
            if model.phase == .results { return model.items.count == 1 ? "1 file to look at" : "\(model.items.count) files to look at" }
            return model.phase == .scanning ? "Looking…" : "Big and forgotten files"
        case .uninstaller:
            return "Remove apps with their leftovers"
        case .updates:
            switch app.appUpdates.phase {
            case .checking: return "Checking…"
            case .done: return app.appUpdates.updates.isEmpty ? "All up to date" : "Updates waiting"
            case .idle: return "Updates for your apps"
            }
        }
    }
}

extension Module {
    /// A name short enough for the sidebar.
    var sidebarTitle: String { self == .large ? "Large Files" : title }
}

/// A small rounded square in the tool's color with its symbol, like an app icon.
struct ToolIcon: View {
    @Environment(\.palette) private var palette
    let module: Module
    var size: CGFloat = 28
    var bounce = 0

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(palette.accent(module).gradient)
            .overlay(
                Image(systemName: module.symbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: bounce)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A small arc going round, drawn in SwiftUI so it takes the tool's color.
struct Spinner: View {
    let tint: Color
    var size: CGFloat = 16
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 1)
            .stroke(tint, style: StrokeStyle(lineWidth: size * 0.14, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
            .accessibilityLabel("Working")
    }
}

/// "Safe to Clean" or "Check First", so it's clear what can go without a second look.
struct SafetyLabel: View {
    let safe: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        // Check First uses its own darker amber text on a pale amber chip, so it stays readable.
        let text = safe ? Palette.safe : Color(hex: palette.isDark ? 0xF0C15C : 0x9A6A0C)
        let fill = safe ? Palette.safe.opacity(0.14) : Color(hex: palette.isDark ? 0x3A2E14 : 0xFBF1DC)
        Text(safe ? "Safe to Clean" : "Check First")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
    }
}

/// Without Full Disk Access some places stay hidden; say so plainly, with the way to fix it.
private struct AccessBanner: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(Palette.caution)
            VStack(alignment: .leading, spacing: 2) {
                Text("Fussel can't see everything yet")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text("Allow Full Disk Access so the Trash and every cache can be scanned.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
            Spacer()
            Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.caution.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.caution.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Tool and settings pages

private struct ToolPage: View {
    @Environment(AppModel.self) private var app
    let module: Module

    var body: some View {
        switch module {
        case .uninstaller:
            VStack(spacing: 0) {
                PageHeader(title: module.title, subtitle: "Remove apps together with their support files") { EmptyView() }
                UninstallerView(model: app.uninstaller)
            }
        case .updates:
            VStack(spacing: 0) {
                PageHeader(title: module.title, subtitle: "Updates for apps from the App Store and the web") { EmptyView() }
                AppUpdatesView(model: app.appUpdates)
            }
        default:
            ModuleView(model: app.model(for: module))
        }
    }
}

private struct SettingsPage: View {
    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Settings", subtitle: "How Fussel looks for fluff") { EmptyView() }
            PreviewSafeScroll {
                SettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
