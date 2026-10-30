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

/// Fussel's window: a bar across the top, the selected page, and a sidebar with the tools that can be
/// shown or hidden (hidden at first; tools then open from the overview's tiles).
struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var page: Page
    @State private var didAutoScan = false
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceChoice.system.rawValue
    @AppStorage("sidebarWidth") private var sidebarWidth = 248.0
    @AppStorage(SettingsKey.showSidebar) private var showSidebar = false

    init(page: Page = .overview) {
        _page = State(initialValue: page)
    }

    var body: some View {
        // The page needs about 572 pt (what it gets in the smallest window), so in a narrow window
        // the sidebar stops growing before it pushes the page out of the window.
        GeometryReader { window in
        let widest = min(SidebarDivider.range.upperBound,
                         max(SidebarDivider.range.lowerBound, window.size.width - 572))
        HStack(spacing: 0) {
            if showSidebar {
            // The sidebar and its dividing line slide in and out as one piece.
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
                .frame(width: min(sidebarWidth, widest))
                SidebarDivider(width: $sidebarWidth, widest: widest)
            }
            .transition(.move(edge: .leading))
            }
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
        // A setting kept in UserDefaults changes outside withAnimation, so the slide is set here.
        .animation(.spring(duration: 0.35, bounce: 0.1), value: showSidebar)
        }
        // Screenshots have no window title bar, so they get the room it takes in the app.
        .safeAreaInset(edge: .top, spacing: 0) {
            if PreviewRenderer.isRendering { Color.clear.frame(height: TopBar.height) }
        }
        // The bar sits in the window's title bar, next to the window buttons.
        .overlay(alignment: .top) {
            TopBar(page: $page, showSidebar: $showSidebar)
                .ignoresSafeArea(edges: .top)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background { if palette.isGlass { GlassBackdrop() } else { palette.content } }
        .overlay(alignment: .bottom) { CleanToast() }
        .overlay { if app.showTutorial { Tutorial().transition(.opacity) } }
        .overlay { if app.showPermissions { PermissionsView().transition(.opacity) } }
        .overlay { if let version = app.justUpdatedTo { UpdatedView(version: version).transition(.opacity) } }
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
    /// How wide the sidebar may get in this window.
    var widest: Double
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
                            if start == nil { start = min(width, widest) }
                            width = min(max((start ?? width) + drag.translation.width, Self.range.lowerBound),
                                        widest)
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
            row(.overview, title: "Overview", symbol: "square.grid.2x2", trailing: nil)
            section("Clean")
            toolRow(.junk)
            toolRow(.tidy)
            section("Review")
            toolRow(.large)
            toolRow(.duplicates)
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
        .padding(.top, 6)
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
        case .junk, .large, .tidy, .duplicates:
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
    /// Woken up by a click at night, for a few seconds.
    @State private var awake = false
    /// One whole turn after a big clean-up.
    @State private var spins = 0

    private func mood(night: Bool) -> MascotMood {
        if busy { return .busy }
        if cheering { return .happy }
        if night && !awake { return .sleepy }
        return app.healthMood == .sleepy ? .sleepy : .idle
    }

    var body: some View {
        // Bedtime is checked once a minute; that's all this needs.
        TimelineView(.everyMinute) { minute in
            let night = Bedtime.isNight(minute.date) && !PreviewRenderer.isRendering
            badge(mood: mood(night: night))
                .overlay(alignment: .topTrailing) {
                    if night && !awake && !busy && !reduceMotion && !paused { Snooze() }
                }
        }
        .help("Hi, I'm Fussel!")
        .accessibilityHidden(true)
    }

    private func badge(mood: MascotMood) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                .fill(Theme.graphite)
                .overlay(RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                    .strokeBorder(Color.white.opacity(palette.isDark ? 0.14 : 0), lineWidth: 1))
            // While scanning the curl swings ±16° every 1.1 s and the eyes look slowly from side to side,
            // resting a moment at each side; frames only run during the scan.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !busy || reduceMotion || paused)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let swing = 16 * sin(t * 2 * .pi / 1.1)
                let glance = sin(t * 2 * .pi / 2.8)
                let look = 3.2 * CGFloat(glance.sign == .minus ? -1 : 1) * CGFloat(pow(abs(glance), 0.45))
                FusselBody(mood: mood, blink: blink && !cheering,
                           curlTilt: busy && !reduceMotion ? swing : (hovering ? -18 : 0),
                           look: busy && !reduceMotion ? look : 0)
                    .equatable()
                    .frame(width: 34, height: 34)
            }
            .offset(y: cheering && !reduceMotion ? -3 : 0)
        }
        .frame(width: 34, height: 34)
        .rotationEffect(.degrees(Double(spins) * 360))
        .scaleEffect(hovering ? 1.1 : 1)
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.spring(duration: 0.3, bounce: 0.5)) { hovering = inside } }
        .onTapGesture {
            Sounds.play("Pop")
            if Bedtime.now && !awake { wake() } else { cheer(for: 1.2) }
        }
        .onChange(of: app.stage) { old, stage in
            if case .done(let freed, _) = stage, freed > 0 {
                cheer(for: 2.4)
                // A big clean-up (over 1 GB) earns a whole turn.
                if freed > 1_000_000_000, !reduceMotion {
                    withAnimation(.spring(duration: 0.9, bounce: 0.25)) { spins += 1 }
                }
            }
            // Done looking: one happy hop.
            if old == .scanning, stage == .ready { cheer(for: 1.0) }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 3...6)))
                blink = true
                try? await Task.sleep(for: .milliseconds(140))
                blink = false
            }
        }
    }

    /// Opens his eyes for a few seconds, then dozes off again.
    private func wake() {
        withAnimation(.spring(duration: 0.3)) { awake = true }
        Task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.easeInOut(duration: 0.6)) { awake = false }
        }
    }

    private func cheer(for seconds: Double) {
        withAnimation(.spring(duration: 0.35, bounce: 0.6)) { cheering = true }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            withAnimation(.spring(duration: 0.4)) { cheering = false }
        }
    }
}

/// Three little z's drifting up from a sleeping Fussel, one after another, fading as they rise.
private struct Snooze: View {
    @Environment(\.palette) private var palette

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .bottomLeading) {
                ForEach(0..<3, id: \.self) { i in
                    // Each z takes 3 s to rise, the next one starts a second later.
                    let phase = (t / 3 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Text("z")
                        .font(.rounded(7 + 3 * phase, .heavy))
                        .foregroundStyle(palette.secondary)
                        .opacity(phase < 0.15 ? phase / 0.15 : 1 - (phase - 0.15) / 0.85)
                        .offset(x: 4 + 8 * phase, y: -14 * phase)
                }
            }
            .frame(width: 22, height: 18, alignment: .bottomLeading)
        }
        .offset(x: 14, y: -6)
        .allowsHitTesting(false)
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
                    Label("Safe to remove", systemImage: "checkmark.circle.fill")
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
                 ? CleanHistory.shared.permanentNote(for: app.selectedItems)
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
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) { actions }
        }
        .padding(.horizontal, 32)
        .padding(.top, 14)
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
    /// While set, the greeting shows this instead of the found total: it counts up to it.
    @State private var countingFound: Int64?
    /// The tool pointed at, in the storage bar or on its tile: both light up.
    @State private var highlighted: Module?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PreviewSafeScroll {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    UpdateBanner(updater: app.updater)
                        .animation(.spring(duration: 0.4), value: app.updater.state)
                    if !app.hasFullDiskAccess {
                        AccessBanner()
                    }

                    HStack(alignment: .bottom) {
                        Greeting(counting: countingFound, celebrations: celebrations)
                        Spacer(minLength: 16)
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack(spacing: 8) { actions }
                            // While scanning, this counts what's found so far, four times a second.
                            TimelineView(.animation(minimumInterval: 0.25, paused: app.stage != .scanning)) { _ in
                                Text(status)
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 300, alignment: .trailing)
                            }
                        }
                        .padding(.bottom, 2)
                    }
                    .padding(.top, 14)

                    StorageBar(grown: shown, highlighted: $highlighted)
                        .padding(.top, 4)

                    ToolTiles(page: $page, highlighted: $highlighted, shown: shown)

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
        .onChange(of: app.stage) { old, stage in
            if case .done(let freed, _) = stage, freed > 0 {
                celebrations += 1
                // The freed amount rolls in like a counter, once.
                if !reduceMotion { countUp(from: 0, to: freed) }
            }
            if old == .scanning, stage == .ready, !reduceMotion {
                countUp(from: min(ScanProgress.shared.snapshot.bytes, app.foundTotal), to: app.foundTotal)
            }
        }
        .cleanConfirmation(isPresented: $confirming)
    }

    private var actions: some View {
        ScanAndClean(scanning: app.stage == .scanning, cleaning: app.stage == .cleaning,
                     cleanSize: app.stage == .ready ? app.selectedTotal : 0, permanent: app.selectionIncludesPermanent,
                     scan: { Task { await app.smartScan() } }, clean: { Task { await app.cleanAll() } },
                     askWithDialog: { confirming = true })
    }

    /// Up to the final total (found or freed), easing out over about half a second.
    private func countUp(from first: Int64, to last: Int64) {
        let start = Double(first), end = Double(last)
        guard end > start else { return }
        Task { @MainActor in
            for step in 1...14 {
                let t = Double(step) / 14
                countingFound = Int64(start + (end - start) * (1 - pow(1 - t, 3)))
                try? await Task.sleep(for: .milliseconds(40))
            }
            countingFound = nil
        }
    }

    private var status: String {
        switch app.stage {
        case .idle: return "Not scanned yet"
        case .scanning:
            let found = ScanProgress.shared.snapshot
            guard found.bytes > 0 else { return "Looking around…" }
            // Just the last two folders of where Fussel is looking, like "Caches/com.spotify.client".
            let place = found.path.split(separator: "/").suffix(2).joined(separator: "/")
            return place.isEmpty ? "\(found.bytes.byteString) found so far"
                                 : "\(found.bytes.byteString) found so far · \(place)"
        case .cleaning: return "Cleaning…"
        case .ready: return "Scanned just now"
        case .done: return "Cleaned just now"
        }
    }
}

/// Fussel says hi and what he found, with the free space below. It reads the live disk values itself,
/// so their update every two seconds redraws only this, not the whole overview.
private struct Greeting: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    /// While the found total counts up after a scan, the number to show.
    let counting: Int64?
    let celebrations: Int

    var body: some View {
        let s = app.monitor.sample
        VStack(alignment: .leading, spacing: 4) {
            Text(UserName.current.isEmpty ? UserName.timeOfDay : "Hi \(UserName.current),")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.secondary)
            Text(headline)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.6)
                .monospacedDigit()
                .foregroundStyle(palette.text)
                // Digits roll while a total counts up (once, after a scan or a clean-up), never for live values.
                .contentTransition(counting == nil ? .identity : .numericText(value: Double(counting ?? 0)))
                .animation(.snappy(duration: 0.18), value: counting)
                .modifier(TextShimmer(active: app.stage == .scanning || app.stage == .cleaning))
                .overlay(alignment: .leading) { SparkleBurst(trigger: celebrations).frame(width: 60) }
            Text(app.stage == .ready && app.selectedTotal > 0
                 ? "\(app.selectedTotal.byteString) safe to remove · \(s.diskFree.byteString) free of \(s.diskTotal.byteString)"
                 : "\(s.diskFree.byteString) free of \(s.diskTotal.byteString)")
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        switch app.stage {
        case .idle: return "Ready when you are"
        case .scanning: return "Looking for fluff…"
        case .cleaning: return "Cleaning up…"
        case .ready:
            return app.foundTotal > 0 ? "I found \((counting ?? app.foundTotal).byteString) of fluff" : "Not a speck of fluff"
        case .done(let freed, _): return freed > 0 ? "\((counting ?? freed).byteString) freed" : "All tidy"
        }
    }
}

/// A calm band of light that runs across text while Fussel is busy.
private struct TextShimmer: ViewModifier {
    let active: Bool
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationsPaused) private var paused
    @State private var phase = 0.0

    func body(content: Content) -> some View {
        content.overlay {
            if active && !reduceMotion && !paused {
                GeometryReader { geo in
                    let band = max(60, geo.size.width * 0.35)
                    LinearGradient(colors: [.clear, .white.opacity(palette.isDark ? 0.55 : 0.75), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: band)
                        .offset(x: -band + phase * (geo.size.width + band))
                }
                .mask(content)
                .allowsHitTesting(false)
                .onAppear {
                    phase = 0
                    withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1 }
                }
                .transition(.opacity)
            }
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
    @Binding var highlighted: Module?
    /// Where the pointer is over the bar, for the little label saying what that part is.
    @State private var pointer: CGFloat?

    var body: some View {
        let s = app.monitor.sample
        let total = max(1, Double(s.diskTotal))
        let used = Double(max(0, s.diskTotal - s.diskFree))
        let slices: [(Module, Double)] = Module.overview.filter(\.inStorageBar).map { module in
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
                            .opacity(highlighted == nil || highlighted == module ? 1 : 0.3)
                            .frame(width: max(3, w * bytes / total))
                    }
                }
                Rectangle()
                    .fill(palette.secondary.opacity(0.55))
                    .frame(width: max(0, w * (used - known) / total))
                Spacer(minLength: 0)
            }
            .frame(width: grown ? w : 0, alignment: .leading)
            .clipped()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.text.opacity(0.08))
            .overlay { if app.stage == .scanning { Shimmer() } }
            .clipShape(Capsule())
            // macOS tooltips don't stay up on a bar that redraws every two seconds, so Fussel shows its own.
            .contentShape(Rectangle())
            .onContinuousHover { phase in hover(phase, width: w, total: total, slices: slices) }
            .overlay(alignment: .topLeading) {
                if let x = pointer, grown {
                    Text(part(at: x, width: w, total: total, used: used, slices: slices))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(palette.sheet))
                        .overlay(Capsule().strokeBorder(palette.cardStroke, lineWidth: 1))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                        .fixedSize()
                        .position(x: min(max(x, 70), max(70, w - 70)), y: -16)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: pointer == nil)
        }
        .frame(height: 10)
        .animation(.spring(duration: 0.8), value: known)
        .accessibilityElement()
        .accessibilityLabel("Disk: \(Int64(used).byteString) used of \(s.diskTotal.byteString)")
    }
}

extension StorageBar {
    /// Follows the pointer for the label, and lights up the tile of the tool under it.
    fileprivate func hover(_ phase: HoverPhase, width w: CGFloat, total: Double, slices: [(Module, Double)]) {
        if case .active(let point) = phase { pointer = point.x } else { pointer = nil }
        let under = pointer.flatMap { tool(at: $0, width: w, total: total, slices: slices) }
        if under != highlighted { withAnimation(.easeOut(duration: 0.15)) { highlighted = under } }
    }

    /// The tool whose slice lies under the pointer, if any.
    fileprivate func tool(at x: CGFloat, width w: CGFloat, total: Double, slices: [(Module, Double)]) -> Module? {
        var edge: CGFloat = 0
        for (module, bytes) in slices where bytes > 0 {
            edge += max(3, w * bytes / total) + 1.5
            if x < edge { return module }
        }
        return nil
    }

    /// What lies under the pointer: a tool's find, everything else that's used, or free space.
    fileprivate func part(at x: CGFloat, width w: CGFloat, total: Double, used: Double,
                          slices: [(Module, Double)]) -> String {
        var edge: CGFloat = 0
        for (module, bytes) in slices where bytes > 0 {
            edge += max(3, w * bytes / total) + 1.5
            if x < edge { return "\(module.title): \(Int64(bytes).byteString)" }
        }
        let known = slices.reduce(0) { $0 + $1.1 }
        let other = max(0, used - known)
        edge += w * other / total
        if x < edge { return "Apps, documents and macOS: \(Int64(other).byteString)" }
        return "Free: \(Int64(max(0, total - used)).byteString)"
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

/// A tile per tool with what it found. Pointing at a tile or at its part of the storage bar
/// lights both up; the other tools turn grey for a moment.
private struct ToolTiles: View {
    @Binding var page: Page
    @Binding var highlighted: Module?
    let shown: Bool

    var body: some View {
        // The four tools that free space in a row, the two that look after apps below as wider tiles.
        let space = Module.overview.filter(\.inStorageBar)
        VStack(spacing: 10) {
            row(space, from: 0, minWidth: 0)
            row(Module.overview.filter { !$0.inStorageBar }, from: space.count, minWidth: 0)
        }
    }

    private func row(_ modules: [Module], from start: Int, minWidth: CGFloat) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(modules.enumerated()), id: \.element) { index, module in
                ToolTile(module: module, highlighted: $highlighted) { page = .tool(module) }
                    .frame(minWidth: minWidth, idealWidth: minWidth, maxWidth: .infinity)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 10)
                    .animation(.spring(duration: 0.5, bounce: 0.25).delay(0.05 * Double(start + index) + 0.15), value: shown)
            }
        }
    }
}

private struct ToolTile: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let module: Module
    @Binding var highlighted: Module?
    let open: () -> Void
    @State private var hovering = false
    @State private var bounce = 0

    var body: some View {
        let facts = CategoryFacts(app: app, module: module)
        let lit = highlighted == module
        let flat = !module.inStorageBar
        Button(action: open) {
            Group {
                if flat {
                    // The Uninstaller and App Updates: a wide, low tile, everything on one line.
                    HStack(spacing: 12) {
                        ToolIcon(module: module, size: 30, bounce: bounce, muted: highlighted != nil && !lit)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(module.sidebarTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.text)
                            Text(facts.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.secondary)
                        }
                        .lineLimit(1)
                        Spacer(minLength: 8)
                        value(facts)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ToolIcon(module: module, size: 30, bounce: bounce, muted: highlighted != nil && !lit)
                        Spacer(minLength: 14)
                        // Everything below the gap has a fixed height, so the numbers line up across the tiles.
                        value(facts)
                            .frame(height: 24, alignment: .leading)
                        Text(module.sidebarTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(height: 16, alignment: .leading)
                            .padding(.top, 2)
                        Text(facts.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(height: 28, alignment: .topLeading)
                            .padding(.top, 1)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: flat ? 0 : 148, alignment: .topLeading)
            // The tile that's pointed at, here or in the storage bar, turns a lighter grey.
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(lit ? (palette.isDark ? 0.06 : 0.9) : 0)))
            .cardSurface(palette, radius: 14)
            .offset(y: hovering ? -2 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { hovering = inside }
            // Only tools with a part in the storage bar light it up; the Uninstaller and App Updates have none.
            if module.inStorageBar {
                withAnimation(.easeOut(duration: 0.15)) { highlighted = inside ? module : nil }
            }
        }
        .animation(.snappy, value: facts.value)
        .animation(.spring(duration: 0.4, bounce: 0.5), value: facts.isWorking)
        // A little hop when a scan for this tool comes back.
        .onChange(of: facts.isWorking) { _, working in if !working { bounce += 1 } }
    }

    @ViewBuilder
    private func value(_ facts: CategoryFacts) -> some View {
        if facts.isWorking {
            Spinner(tint: palette.accent(module))
                .transition(.scale.combined(with: .opacity))
        } else {
            Text(facts.value)
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }
}

/// What the overview says about one tool: its value and a line of detail.
@MainActor
private struct CategoryFacts {
    let app: AppModel
    let module: Module

    var isWorking: Bool {
        if let model { return model.phase == .scanning || model.phase == .cleaning }
        if module == .updates, case .checking = app.appUpdates.phase { return true }
        return false
    }

    var model: ModuleModel? {
        switch module {
        case .junk, .large, .tidy, .duplicates: return app.model(for: module)
        default: return nil
        }
    }

    var value: String {
        if let model {
            switch model.phase {
            case .results: return model.totalSize.byteString
            case .scanning, .cleaning: return "…"
            case .done(let freed, _): return freed > 0 ? freed.byteString : "0 KB"
            case .idle: return "—"
            }
        }
        if module == .uninstaller { return app.uninstaller.apps.isEmpty ? "—" : "\(app.uninstaller.apps.count) apps" }
        if case .idle = app.appUpdates.phase { return "—" }
        let updates = app.appUpdates.updates.count
        return updates == 1 ? "1 update" : "\(updates) updates"
    }

    var detail: String {
        switch module {
        case .junk, .tidy:
            guard let model else { return "" }
            switch model.phase {
            case .results: return model.items.isEmpty ? module.spotless : "\(model.selectedSize.byteString) safe to remove"
            case .scanning: return "Looking…"
            case .cleaning: return "Cleaning…"
            case .done(let freed, _): return freed > 0 ? "\(freed.byteString) freed" : module.spotless
            case .idle: return "Not scanned yet"
            }
        case .large:
            guard let model else { return "" }
            if model.phase == .results { return model.items.count == 1 ? "1 file to look at" : "\(model.items.count) files to look at" }
            return model.phase == .scanning ? "Looking…" : "Big and forgotten files"
        case .duplicates:
            guard let model else { return "" }
            if model.phase == .results {
                let sets = model.groups.count
                return sets == 0 ? "No copies found" : sets == 1 ? "1 file twice" : "\(sets) files more than once"
            }
            return model.phase == .scanning ? "Looking…" : "Files you have twice"
        case .uninstaller:
            return "Apps and their leftovers"
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
    /// The tools on the overview, in order.
    static let overview: [Module] = [.junk, .tidy, .large, .duplicates, .uninstaller, .updates]

    /// Whether the tool has its own part in the storage bar, for what it found.
    var inStorageBar: Bool { self == .junk || self == .tidy || self == .large || self == .duplicates }

    /// A name short enough for the sidebar.
    var sidebarTitle: String { self == .large ? "Large Files" : title }
}

/// A small rounded square in the tool's color with its symbol, like an app icon.
struct ToolIcon: View {
    @Environment(\.palette) private var palette
    let module: Module
    var size: CGFloat = 28
    var bounce = 0
    /// Grey instead of the tool's color, while another tool is pointed at.
    var muted = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(muted ? palette.secondary.opacity(0.4).gradient : palette.accent(module).gradient)
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

/// "Safe to Remove" or "Review First", so it's clear what can go without a second look.
struct SafetyLabel: View {
    let safe: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        // Review First uses its own darker amber text on a pale amber chip, so it stays readable.
        let text = safe ? Palette.safe : Color(hex: palette.isDark ? 0xF0C15C : 0x9A6A0C)
        let fill = safe ? Palette.safe.opacity(0.14) : Color(hex: palette.isDark ? 0x3A2E14 : 0xFBF1DC)
        Text(safe ? "Safe to Remove" : "Review First")
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

// MARK: - After a clean-up

/// For a few seconds after a clean-up, a small card at the bottom says what went to the Trash and
/// offers Undo right there. A thin line runs down while it waits.
private struct CleanToast: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var shown: CleanRecord?
    @State private var left = 1.0
    private static let seconds = 6.0

    var body: some View {
        Group {
            if let record = shown {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.safe)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Palette.safe.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Moved \(record.freed.byteString) to the Trash")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.text)
                        Text("\(record.itemCount == 1 ? "1 item" : "\(record.itemCount) items") · you can put them back")
                            .font(.system(size: 11)).foregroundStyle(palette.secondary)
                    }
                    Spacer(minLength: 16)
                    Button {
                        shown = nil
                        Task { await app.undo(record) }
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut("z", modifiers: .command)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(width: 420)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.sheet))
                .overlay(alignment: .bottomLeading) {
                    Capsule().fill(palette.secondary.opacity(0.35))
                        .frame(width: max(0, 392 * left), height: 2)
                        .padding(.horizontal, 14).padding(.bottom, 4)
                }
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.cardStroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(record.id)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: shown?.id)
        .onChange(of: CleanHistory.shared.records.first?.id) { _, _ in
            // Only a clean-up that just happened and can still be put back.
            guard let record = CleanHistory.shared.records.first, record.canUndo,
                  Date().timeIntervalSince(record.date) < 5 else { return }
            shown = record
            left = 1
            withAnimation(.linear(duration: Self.seconds)) { left = 0 }
            Task {
                try? await Task.sleep(for: .seconds(Self.seconds))
                if shown?.id == record.id { shown = nil }
            }
        }
    }
}

// MARK: - Scan and Clean

/// Scan, and Clean once there is something to clean. Until then Scan is the main (white or dark)
/// key; when Clean slides in, Scan steps back to a quiet one. While busy, the button at work shows
/// a spinner instead of fading out. Clean asks right where it is ("Move … to Trash?"); only a selection
/// that would delete something for good gets the full dialog, since that can't be undone.
struct ScanAndClean: View {
    @Environment(\.palette) private var palette
    let scanning: Bool
    let cleaning: Bool
    /// What Clean would remove; 0 hides it.
    let cleanSize: Int64
    /// The selection includes things deleted for good: ask with the full dialog instead.
    var permanent = false
    let scan: () -> Void
    let clean: () -> Void
    var askWithDialog: () -> Void = {}
    @State private var asking = false

    var body: some View {
        let showClean = cleaning || (cleanSize > 0 && !scanning)
        HStack(spacing: 8) {
            if asking && showClean && !cleaning {
                Button("Cancel") { asking = false }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .transition(.opacity)
                Button {
                    asking = false
                    clean()
                } label: {
                    Label("Move \(cleanSize.byteString) to Trash", systemImage: "trash")
                }
                .buttonStyle(ActionButtonStyle())
                .keyboardShortcut(.defaultAction)
                .animation(.spring(duration: 0.35, bounce: 0.2), value: cleanSize)
                .transition(.opacity)
            } else {
            if showClean {
                scanButton.buttonStyle(SecondaryButtonStyle())
            } else {
                scanButton.buttonStyle(ActionButtonStyle())
            }
            if showClean {
                Button {
                    if permanent { askWithDialog() } else { asking = true }
                } label: {
                    busyLabel(cleaning, "Cleaning…", idle: "Clean \(cleanSize.byteString)", symbol: "trash",
                              tint: palette.buttonText)
                }
                .buttonStyle(ActionButtonStyle())
                .allowsHitTesting(!cleaning)
                // Grows and shrinks smoothly as the size in its label changes.
                .animation(.spring(duration: 0.35, bounce: 0.2), value: cleanSize)
                .transition(.asymmetric(insertion: .scale(scale: 0.6, anchor: .trailing).combined(with: .opacity),
                                        removal: .opacity))
            }
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.25), value: showClean)
        .animation(.spring(duration: 0.35, bounce: 0.2), value: asking)
        // Nothing left to ask about (a new scan, or the selection emptied): back to the usual buttons.
        .onChange(of: showClean) { _, shown in if !shown { asking = false } }
    }

    private var scanButton: some View {
        let quiet = cleaning || (cleanSize > 0 && !scanning)
        return Button(action: scan) {
            busyLabel(scanning, "Scanning…", idle: "Scan", symbol: "arrow.clockwise",
                      tint: quiet ? palette.text : palette.buttonText)
        }
        .allowsHitTesting(!scanning && !cleaning)
        .keyboardShortcut("r", modifiers: [.command, .shift])
    }

    @ViewBuilder
    private func busyLabel(_ busy: Bool, _ busyText: String, idle: String, symbol: String, tint: Color) -> some View {
        if busy {
            HStack(spacing: 7) {
                Spinner(tint: tint, size: 13)
                Text(busyText)
            }
        } else {
            Label(idle, systemImage: symbol)
        }
    }
}

// MARK: - Top bar

/// One bar across the top, next to the window buttons: the sidebar button, Fussel and where you are,
/// and, while the sidebar is hidden, a way back to the overview plus History and Settings.
private struct TopBar: View {
    static let height: CGFloat = 52
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceChoice.system.rawValue
    @Binding var page: Page
    @Binding var showSidebar: Bool
    @State private var showingHistory = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if PreviewRenderer.isRendering {
                    // Stand-ins for the window buttons, which screenshots don't draw.
                    HStack(spacing: 8) {
                        ForEach([0xFF5F57, 0xFEBC2E, 0x28C840] as [UInt32], id: \.self) {
                            Circle().fill(Color(hex: $0)).frame(width: 12, height: 12)
                        }
                    }
                    .padding(.leading, 2)
                    .padding(.trailing, 6)
                } else {
                    // Room for the window buttons.
                    Color.clear.frame(width: 60, height: 1)
                }
                RoundButton(symbol: "sidebar.left", help: showSidebar ? "Hide Sidebar (⌃⌘S)" : "Show Sidebar (⌃⌘S)") {
                    showSidebar.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                if !showSidebar && page != .overview {
                    RoundButton(symbol: "chevron.left", help: "Back to Overview") { page = .overview }
                        .keyboardShortcut("[", modifiers: .command)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                SidebarFussel(busy: app.stage == .scanning || app.stage == .cleaning)
                    .padding(.leading, 4)
                Wordmark()
            }
            // Oreo: over the light sidebar, these take the sidebar's colors.
            .modifier(OreoSide(on: showSidebar && appearance == AppearanceChoice.oreo.rawValue))

            if !showSidebar, let place {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                Text(place)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
            Spacer(minLength: 12)
            if !showSidebar {
                RoundButton(symbol: "clock.arrow.circlepath", help: "History", label: "History") { showingHistory = true }
                    .popover(isPresented: $showingHistory, arrowEdge: .bottom) { HistoryList().environment(app) }
                RoundButton(symbol: "gearshape", help: "Settings", label: "Settings") { page = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 24)
        .frame(height: Self.height)
        .animation(.spring(duration: 0.3), value: page)
        .animation(.spring(duration: 0.3), value: showSidebar)
    }

    /// Where you are, after "Fussel ›", on every page but the overview.
    private var place: String? {
        switch page {
        case .overview: return nil
        case .tool(let module): return module.sidebarTitle
        case .settings: return "Settings"
        }
    }
}

/// "Fussel" in SF Pro Rounded Heavy, set a little tight.
private struct Wordmark: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Text("Fussel")
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .tracking(-0.7)
            .foregroundStyle(palette.text)
    }
}

private struct OreoSide: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content.environment(\.palette, .oreoSide).environment(\.colorScheme, .light)
        } else {
            content
        }
    }
}

/// A small round button for the top bar.
private struct RoundButton: View {
    @Environment(\.palette) private var palette
    let symbol: String
    let help: String
    /// Slides out next to the symbol while the pointer is on the button.
    var label: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let open = hovering && label != nil
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                if open, let label {
                    Text(label)
                        .fixedSize()
                        .transition(.opacity.combined(with: .offset(x: -6)))
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(hovering ? palette.text : palette.secondary)
            .padding(.horizontal, open ? 11 : 0)
            .frame(minWidth: 30, minHeight: 30, maxHeight: 30)
            .background(Capsule().fill(palette.card))
            .overlay(Capsule().strokeBorder(palette.cardStroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.2), value: hovering)
    }
}
