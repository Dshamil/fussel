import SwiftUI
import AppKit

/// Fussel's single main screen: a hero with Fussel and one big action, four cards below.
struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var openModule: Module?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    /// A small heading over a row of cards, so cleaning and tools read as two groups.
    private func cardGroup(_ title: String, _ modules: [Module], startIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.rounded(13, .bold))
                .foregroundStyle(palette.text)
                .padding(.leading, 4)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(modules.enumerated()), id: \.element) { index, module in
                    ModuleCard(module: module, index: startIndex + index) { openModule = module }
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            UpdateBanner(updater: app.updater)
                .animation(.spring(duration: 0.4), value: app.updater.state)

            HeroCard()

            StatsRow()

            cardGroup("Clean up", [.junk, .large, .tidy], startIndex: 0)
            cardGroup("Tools", [.uninstaller, .updates, .closet], startIndex: 3)

            HStack(alignment: .center, spacing: 12) {
                if !app.hasFullDiskAccess {
                    FullDiskAccessHint()
                }
                Spacer(minLength: 0)
                HistoryPill()
                StyleSwitcher()
                SettingsButton()
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 22)
        .padding(.top, 8)
        .frame(minWidth: 700, idealWidth: 760, maxWidth: .infinity,
               minHeight: 820, maxHeight: .infinity, alignment: .top)
        .background { Backdrop().ignoresSafeArea() }
        .environment(\.animationsPaused, !app.windowVisible)
        .overlay {
            if app.showTutorial {
                TutorialOverlay()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .animation(.spring(duration: 0.4), value: app.showTutorial)
        .onAppear {
            if !UserDefaults.standard.bool(forKey: TutorialKey.seen) {
                app.showTutorial = true
            }
        }
        .sheet(item: $openModule) { module in
            DetailSheet(module: module)
                .environment(app)
                .environment(\.palette, palette)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshAccess()
        }
    }
}

/// The canvas with two soft color clouds, so the window isn't a flat sheet. Static, so it costs nothing.
private struct Backdrop: View {
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let reach = max(geo.size.width, geo.size.height) * 0.6
            ZStack {
                Rectangle().fill(palette.canvas)
                RadialGradient(colors: [palette.blobs.0, .clear], center: UnitPoint(x: 0.95, y: 0.3),
                               startRadius: 0, endRadius: reach)
                RadialGradient(colors: [palette.blobs.1, .clear], center: UnitPoint(x: 0.02, y: 0.98),
                               startRadius: 0, endRadius: reach)
            }
        }
    }
}

// MARK: - Hero

private struct HeroCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var confirming = false
    @State private var bubble: String?
    @State private var bubbleID = 0
    @State private var burstDate: Date?
    @State private var liveBytes: Int64 = 0
    @State private var livePath = ""
    @State private var puff: CGFloat = 1

    private let mascotSize: CGFloat = 168

    private static let pokeLines = [
        "Hehe, that tickles!", "Boop!", "Wheee!", "I'm 100% fluff.",
        "Careful, I'm delicate!", "Again! Again!", "Need a scan?", "*happy fluff noises*",
    ]
    private static let scanLines = [
        "Peeking into caches…", "Checking under the sofa…", "Counting dust bunnies…",
        "Sniffing out big files…", "Shaking out the logs…", "Looking behind the Trash…",
    ]

    var body: some View {
        HStack(spacing: 24) {
                FusselMascot(mood: app.mood, size: mascotSize, color: palette.mascot,
                             followsPointer: true, interactive: true) {
                    Sounds.play("Pop")
                    Achievements.shared.record(.poked)
                    say(Self.pokeLines.randomElement() ?? "Boop!")
                }
                .overlay(alignment: .top) {
                    if let bubble {
                        SpeechBubble(text: bubble)
                            .offset(x: 58, y: -18)
                            .transition(.scale(scale: 0.4, anchor: .bottomLeading).combined(with: .opacity))
                    }
                }
                .scaleEffect(puff)
                .padding(.leading, 8)
                .offset(y: 8)

                VStack(alignment: .leading, spacing: 8) {
                    headline
                        .font(.rounded(31, .heavy))
                        .foregroundStyle(palette.heroText)
                    subline
                        .font(.rounded(14, .medium))
                        .foregroundStyle(palette.heroText)
                        .fixedSize(horizontal: false, vertical: true)
                    action
                        .padding(.top, 10)
                }
                Spacer(minLength: 0)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, minHeight: 230)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(palette.heroFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(palette.heroStroke, lineWidth: 1)
                    )
                    .shadow(color: palette.isDark ? .black.opacity(0.35) : Theme.coralDeep.opacity(0.25),
                            radius: 18, y: 10)
                FusselWorld(pile: pile, isDark: palette.isDark)
                    .animation(.spring(duration: 1.2, bounce: 0.3), value: pile)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                ParticleField(mode: particleMode, tint: palette.speck,
                              center: UnitPoint(x: 0.15, y: 0.5), burstDate: burstDate)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        // Nothing to animate while the tutorial covers the hero or the window is hidden.
        .environment(\.animationsPaused, app.showTutorial || !app.windowVisible)
        .animation(.spring(duration: 0.4), value: app.stage)
        .task(id: app.stage) {
            // While scanning, read the live counter a few times a second and puff Fussel up.
            guard app.stage == .scanning else {
                withAnimation(.spring(duration: 0.6, bounce: 0.6)) { puff = 1 }
                return
            }
            while !Task.isCancelled && app.stage == .scanning {
                let snap = ScanProgress.shared.snapshot
                let gigabytes = Double(snap.bytes) / 1_000_000_000
                withAnimation(.spring(duration: 0.35, bounce: 0.4)) {
                    liveBytes = snap.bytes
                    puff = 1 + min(0.3, log2(1 + gigabytes) * 0.08)
                }
                livePath = snap.path
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        .onChange(of: Achievements.shared.justEarned) { _, badge in
            guard let badge else { return }
            Achievements.shared.justEarned = nil
            burstDate = Date()
            Sounds.play("Hero")
            say("Badge unlocked: \(badge.title)!")
        }
        .onChange(of: app.undoMessage) { _, message in
            guard let message else { return }
            say(message)
            app.undoMessage = nil
        }
        .onChange(of: app.healthMood) { _, mood in
            guard app.stage == .idle else { return }
            switch mood {
            case .stuffed: say("Oof, I'm so full!")
            case .hot: say("Is it warm in here?")
            case .sleepy: say("*yawn*")
            default: break
            }
        }
        .onChange(of: app.stage) { _, stage in
            switch stage {
            case .done(let freed, _):
                burstDate = Date()
                Sounds.play("Glass")
                say(freed > 0 ? "Ahh, so fresh!" : "Squeaky clean!")
            case .ready:
                Sounds.play(app.foundTotal > 0 ? "Bottle" : "Tink")
                say(app.foundTotal > 0 ? "*burp* Found you, fluff!" : "Spotless already!")
            default:
                break
            }
        }
        .confirmationDialog("Clean \(app.selectedTotal.byteString)?", isPresented: $confirming) {
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

    /// How much fluff lies on the floor: a little always, more the more a scan finds, none after cleaning.
    private var pile: Double {
        let bytes: Int64
        switch app.stage {
        case .idle: bytes = max(app.pendingFluff, 1_500_000_000)
        case .scanning: bytes = liveBytes
        case .ready: bytes = app.foundTotal
        case .cleaning, .done: bytes = 0
        }
        return min(1, log10(1 + Double(bytes) / 1_000_000_000) / 1.1)
    }

    private var particleMode: ParticleField.Mode {
        switch app.stage {
        case .scanning, .cleaning: return .vacuum
        default: return .drift
        }
    }

    private func chipTitle(_ module: Module) -> String {
        switch module {
        case .junk: return "Junk"
        case .large: return "Big Files"
        default: return "Trash"
        }
    }

    private func say(_ text: String) {
        bubbleID += 1
        let id = bubbleID
        withAnimation(.spring(duration: 0.35, bounce: 0.45)) { bubble = text }
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if bubbleID == id {
                withAnimation(.easeOut(duration: 0.2)) { bubble = nil }
            }
        }
    }

    @ViewBuilder
    private var headline: some View {
        switch app.stage {
        case .idle:
            if app.pendingFluff > 0 {
                Text("Psst, \(app.pendingFluff.byteString) of fluff!")
            } else {
                healthHeadline
            }
        case .scanning:
            scanningHeadline
        case .ready:
            readyHeadline
        case .cleaning:
            Text("Tidying up…")
        case .done(let freed, _):
            doneHeadline(freed)
        }
    }

    @ViewBuilder
    private var healthHeadline: some View {
            switch app.healthMood {
            case .stuffed: Text("I'm stuffed!")
            case .hot: Text("Phew, it's hot!")
            case .sleepy: Text("So sleepy…")
            default: Text("Hi, I'm Fussel!")
            }
    }

    private var scanningHeadline: some View {
        HStack(spacing: 0) {
            Text("Found ")
            Text(liveBytes.byteString)
                .contentTransition(.numericText(value: Double(liveBytes)))
            Text("…")
        }
    }

    @ViewBuilder
    private var readyHeadline: some View {
        if app.foundTotal > 0 {
            HStack(spacing: 0) {
                Text("Found ")
                CountingBytes(value: Double(app.foundTotal))
                    .animation(.easeOut(duration: 1.2), value: app.foundTotal)
            }
        } else {
            Text("Already fluff-free!")
        }
    }

    @ViewBuilder
    private func doneHeadline(_ freed: Int64) -> some View {
        if freed > 0 {
            HStack(spacing: 0) {
                Text("Cleared ")
                CountingBytes(value: Double(freed))
                    .animation(.easeOut(duration: 1.2), value: freed)
                Text("!")
            }
        } else {
            Text("All tidy!")
        }
    }

    @ViewBuilder
    private var subline: some View {
        switch app.stage {
        case .idle where app.pendingFluff > 0:
            Text("I found it during my weekly check while you were away. Start a scan to see everything.")
        case .idle:
            switch app.healthMood {
            case .stuffed:
                Text("Your disk is almost full, only \(app.monitor.sample.diskFree.byteString) left. Let's make some room.")
            case .hot:
                Text("Your Mac is running hot. Quitting a hungry app in the memory tile might help.")
            case .sleepy:
                Text("Your battery is almost empty. Plug me in before I nod off completely.")
            default:
                Text("Let's find the fluff hiding on your Mac. Psst: you can poke me.")
            }
        case .scanning:
            VStack(alignment: .leading, spacing: 4) {
                TimelineView(.periodic(from: .now, by: 1.6)) { context in
                    let index = Int(context.date.timeIntervalSinceReferenceDate / 1.6) % Self.scanLines.count
                    Text(Self.scanLines[index])
                }
                Text(livePath.isEmpty ? " " : livePath)
                    .font(.system(size: 11, design: .monospaced))
                    .opacity(0.7)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 380, alignment: .leading)
            }
        case .cleaning:
            Text("Carrying everything to the Trash…")
        case .ready:
            if app.foundTotal == 0 {
                Text("Nothing to clean right now. Your Mac is in great shape.")
            } else if app.selectedTotal > 0 {
                Text("\(app.selectedTotal.byteString) is ready to go. Open a card to fine-tune.")
            } else {
                Text("Open a card below to choose what to clean.")
            }
        case .done(_, let failures):
            Text(failures.isEmpty
                 ? "Your Mac feels lighter already."
                 : "\(failures.count) item(s) couldn't be removed. Everything else is in the Trash.")
        }
    }

    /// The quieter action next to the big button.
    private func secondary(_ symbol: String) -> NudgeButtonStyle {
        NudgeButtonStyle(tint: palette.heroText, badgeText: palette.isDark ? Theme.ink : .white,
                         symbol: symbol, size: 13)
    }

    @ViewBuilder
    private var action: some View {
        let style = HeroButtonStyle(fill: palette.heroButtonFill, text: palette.heroButtonText)
        switch app.stage {
        case .idle:
            Button("Start Scan") { Task { await app.smartScan() } }
                .buttonStyle(style)
                .keyboardShortcut(.defaultAction)
        case .scanning:
            HStack(spacing: 8) {
                ForEach([Module.junk, .large, .tidy], id: \.self) { module in
                    ScanChip(title: chipTitle(module), done: app.isFinished(module), tint: palette.heroText)
                }
            }
            .frame(height: 42)
        case .cleaning:
            ProgressView()
                .controlSize(.small)
                .tint(palette.heroText)
                .frame(height: 42)
        case .ready:
            if app.selectedTotal > 0 {
                HStack(spacing: 14) {
                    Button("Clean \(app.selectedTotal.byteString)") { confirming = true }
                        .buttonStyle(style)
                        .keyboardShortcut(.defaultAction)
                    Button("Scan Again") { Task { await app.smartScan() } }
                        .buttonStyle(secondary("arrow.clockwise"))
                }
            } else {
                Button("Scan Again") { Task { await app.smartScan() } }
                    .buttonStyle(style)
            }
        case .done:
            HStack(spacing: 14) {
                Button("Scan Again") { Task { await app.smartScan() } }
                    .buttonStyle(style)
                if let record = app.lastRecord, record.canUndo {
                    Button("Undo") { Task { _ = await app.undo(record) } }
                    .buttonStyle(secondary("arrow.uturn.backward"))
                    .help("Put everything back from the Trash")
                }
            }
        }
    }
}

/// The main pill on the hero. Lifts on hover, squishes when pressed.
struct HeroButtonStyle: ButtonStyle {
    var fill: Color
    var text: Color

    func makeBody(configuration: Configuration) -> some View {
        HeroButton(configuration: configuration, fill: fill, text: text)
    }

    private struct HeroButton: View {
        let configuration: ButtonStyleConfiguration
        let fill: Color
        let text: Color
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.rounded(15, .bold))
                .foregroundStyle(text)
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
                .background(Capsule().fill(fill))
                .shadow(color: .black.opacity(hovering ? 0.22 : 0.12), radius: hovering ? 10 : 6, y: hovering ? 5 : 3)
                .scaleEffect(configuration.isPressed ? 0.94 : (hovering ? 1.04 : 1))
                .opacity(isEnabled ? 1 : 0.5)
                .animation(.spring(duration: 0.25, bounce: 0.5), value: configuration.isPressed)
                .animation(.spring(duration: 0.3, bounce: 0.4), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// Cards squish a little when pressed and spring back.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.55), value: configuration.isPressed)
    }
}

/// One of the three progress chips during a scan: spinner, then a bouncy checkmark.
private struct ScanChip: View {
    let title: String
    let done: Bool
    let tint: Color
    @State private var spinning = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                } else {
                    // Drawn in SwiftUI (not ProgressView), so it matches the tint and shows up in previews.
                    Circle()
                        .trim(from: 0.2, to: 1)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .padding(1.5)
                        .rotationEffect(.degrees(spinning ? 360 : 0))
                        .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spinning)
                        .onAppear { spinning = true }
                }
            }
            .frame(width: 14, height: 14)
            Text(title)
        }
        .font(.rounded(12, .bold))
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(done ? 0.16 : 0.08)))
        .animation(.spring(duration: 0.45, bounce: 0.6), value: done)
    }
}

/// A little speech bubble next to Fussel.
private struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.rounded(13, .bold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                BubbleShape()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            )
            .fixedSize()
    }
}

private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 12, style: .continuous)
        // Tail pointing down-left towards Fussel.
        path.move(to: CGPoint(x: rect.minX + 14, y: rect.maxY - 1))
        path.addLine(to: CGPoint(x: rect.minX + 6, y: rect.maxY + 9))
        path.addLine(to: CGPoint(x: rect.minX + 26, y: rect.maxY - 1))
        path.closeSubpath()
        return path
    }
}

// MARK: - Cards

private struct ModuleCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let module: Module
    let index: Int
    let open: () -> Void
    @State private var hovering = false
    @State private var bounces = 0
    @State private var appeared = false
    /// -0.5…0.5 on both axes: where the pointer is on the card, for the tilt.
    @State private var tilt = CGSize.zero
    @State private var cardSize = CGSize(width: 1, height: 1)

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(palette.isDark ? palette.tint(module) : .white.opacity(0.75))
                        Image(systemName: module.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(palette.icon(module))
                            .symbolEffect(.bounce, value: bounces)
                            .symbolEffect(.pulse, isActive: isBusy)
                    }
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(hovering ? -8 : 0))
                    .scaleEffect(hovering ? 1.08 : 1)

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.icon(module))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(palette.isDark ? palette.tint(module) : .white.opacity(0.75)))
                        .opacity(hovering ? 1 : 0)
                        .scaleEffect(hovering ? 1 : 0.6)
                        .offset(x: hovering ? 0 : -6)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(module.title)
                        .font(.rounded(15, .bold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    status
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background {
                ZStack {
                    shape.fill(palette.card)
                    shape.fill(palette.isDark ? Palette.pastel(module).opacity(0.13) : Palette.pastel(module))
                    // Light falls from the top, like on a soft plastic toy.
                    shape.fill(LinearGradient(colors: [.white.opacity(palette.isDark ? 0.05 : 0.55), .clear],
                                              startPoint: .top, endPoint: .center))
                }
                .shadow(color: shadowColor.opacity(hovering ? 0.28 : 0.1), radius: hovering ? 16 : 6, y: hovering ? 10 : 3)
            }
            .overlay(shape.strokeBorder(palette.isDark ? palette.tint(module) : .white.opacity(0.7), lineWidth: 1))
            // Fussel peeks over the top edge while the pointer is on the card.
            .background(alignment: .topTrailing) {
                FusselBody(mood: .idle, color: palette.isDark ? palette.mascot : Palette.pastel(module),
                           look: CGSize(width: -0.6, height: -1.1))
                    .frame(width: 46, height: 46)
                    .rotationEffect(.degrees(hovering ? 8 : 0))
                    .offset(x: -54, y: hovering ? -28 : 2)
                    .opacity(hovering ? 1 : 0)
                    .animation(.spring(duration: 0.45, bounce: 0.5).delay(hovering ? 0.08 : 0), value: hovering)
            }
            .contentShape(shape)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
        }
        .buttonStyle(CardPressStyle())
        .scaleEffect(hovering ? 1.02 : 1)
        .rotation3DEffect(.degrees(Double(hypot(tilt.width, tilt.height)) * 10),
                          axis: (x: -tilt.height, y: tilt.width, z: 0), perspective: 0.6)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                guard !reduceMotion else { return }
                withAnimation(.interactiveSpring(duration: 0.3)) {
                    tilt = CGSize(width: point.x / cardSize.width - 0.5, height: point.y / cardSize.height - 0.5)
                }
            case .ended:
                withAnimation(.spring(duration: 0.5, bounce: 0.4)) { tilt = .zero }
            }
        }
        .onHover { inside in
            withAnimation(.spring(duration: 0.35, bounce: 0.45)) { hovering = inside }
            if inside { bounces += 1 }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.94)
        .offset(y: appeared ? 0 : 22)
        .blur(radius: appeared ? 0 : 6)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(duration: 0.6, bounce: 0.35).delay(0.06 * Double(index) + 0.15)) {
                    appeared = true
                }
            }
        }
    }

    private var shadowColor: Color {
        palette.isDark ? .black : Palette.shadow(module)
    }

    private var isBusy: Bool {
        if module == .updates, case .checking = app.appUpdates.phase { return true }
        guard module != .uninstaller, module != .updates, module != .closet else { return false }
        let phase = app.model(for: module).phase
        return phase == .scanning || phase == .cleaning
    }

    @ViewBuilder
    private var status: some View {
        if module == .uninstaller {
            Text("Remove apps and their leftovers")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
        } else if module == .updates {
            switch app.appUpdates.phase {
            case .idle:
                Text(shortBlurb)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            case .checking(let done, let total):
                Text("Checking \(done) of \(total)…")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            case .done:
                if app.appUpdates.updates.isEmpty {
                    Label("All up to date", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                } else {
                    Text("\(app.appUpdates.updates.count) waiting")
                        .font(.rounded(19, .heavy))
                        .foregroundStyle(palette.text)
                }
            }
        } else if module == .closet {
            Text("\(Achievements.shared.earned.count) of \(Achievements.all.count) badges")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
        } else {
            let model = app.model(for: module)
            switch model.phase {
            case .idle:
                Text(shortBlurb)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            case .scanning, .cleaning:
                Text(model.phase == .scanning ? "Sniffing around…" : "Cleaning…")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            case .results:
                if model.items.isEmpty {
                    Label("All tidy", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        CountingBytes(value: Double(model.totalSize))
                            .animation(.easeOut(duration: 1.0), value: model.totalSize)
                            .font(.rounded(19, .heavy))
                            .foregroundStyle(palette.text)
                        Text(model.selected.isEmpty ? "nothing selected" : "\(model.selectedSize.byteString) selected")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.secondary)
                    }
                }
            case .done(let freed, _):
                Label(freed > 0 ? "Cleared \(freed.byteString)" : "All tidy", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private var shortBlurb: String {
        switch module {
        case .junk: return "Caches, logs and build crumbs"
        case .large: return "Big files and forgotten ones"
        case .tidy: return "Trash and old downloads"
        case .uninstaller: return "Remove apps and their leftovers"
        case .updates: return "Updates for your apps"
        case .closet: return "Costumes, icons and badges"
        }
    }
}

// MARK: - Detail sheet

private struct DetailSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let module: Module

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.tint(module))
                    Image(systemName: module.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.icon(module))
                }
                .frame(width: 28, height: 28)
                Text(module.title)
                    .font(.rounded(17, .bold))
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            Group {
                if module == .uninstaller {
                    UninstallerView(model: app.uninstaller)
                } else if module == .updates {
                    AppUpdatesView(model: app.appUpdates)
                } else if module == .closet {
                    ClosetView()
                } else {
                    ModuleView(model: app.model(for: module))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 520)
        .background(palette.sheet)
    }
}

// MARK: - Full Disk Access

struct FullDiskAccessHint: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundStyle(palette.text)
            Text("Give Fussel Full Disk Access to reach the Trash and every hidden speck.")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
                .buttonStyle(NudgeButtonStyle(tint: palette.text, badgeText: palette.isDark ? Theme.ink : .white,
                                              symbol: "arrow.up.right"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(palette.card))
        .overlay(Capsule().strokeBorder(palette.cardStroke, lineWidth: 1))
    }
}
