import SwiftUI
import AppKit

/// Fussel's single main screen: a hero with Fussel and one big action, four cards below.
struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var openModule: Module?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        VStack(spacing: 18) {
            HeroCard()

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Array(Module.allCases.enumerated()), id: \.element) { index, module in
                    ModuleCard(module: module, index: index) { openModule = module }
                }
            }

            HStack(alignment: .center, spacing: 12) {
                if !app.hasFullDiskAccess {
                    FullDiskAccessHint()
                }
                Spacer(minLength: 0)
                StyleSwitcher()
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 22)
        .padding(.top, 8)
        .frame(minWidth: 700, idealWidth: 760, maxWidth: .infinity,
               minHeight: 520, maxHeight: .infinity, alignment: .top)
        .background { palette.canvas.ignoresSafeArea() }
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

// MARK: - Hero

private struct HeroCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var confirming = false
    @State private var lookAt: CGVector?
    @State private var bubble: String?
    @State private var bubbleID = 0
    @State private var burstDate: Date?

    private let mascotSize: CGFloat = 168
    private let mascotCenter = CGPoint(x: 22 + 8 + 84, y: 115)

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
                             lookAt: lookAt, interactive: true) {
                    Sounds.play("Pop")
                    say(Self.pokeLines.randomElement() ?? "Boop!")
                }
                .overlay(alignment: .top) {
                    if let bubble {
                        SpeechBubble(text: bubble)
                            .offset(x: 58, y: -18)
                            .transition(.scale(scale: 0.4, anchor: .bottomLeading).combined(with: .opacity))
                    }
                }
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
                ParticleField(mode: particleMode, tint: palette.speck,
                              center: UnitPoint(x: 0.15, y: 0.5), burstDate: burstDate)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                let dx = point.x - mascotCenter.x
                let dy = point.y - mascotCenter.y
                let length = max(1, hypot(dx, dy))
                let reach = min(1, length / 160)
                lookAt = CGVector(dx: dx / length * reach, dy: dy / length * reach)
            case .ended:
                lookAt = nil
            }
        }
        .animation(.spring(duration: 0.4), value: app.stage)
        .onChange(of: app.stage) { _, stage in
            switch stage {
            case .done(let freed, _):
                burstDate = Date()
                Sounds.play("Glass")
                say(freed > 0 ? "Ahh, so fresh!" : "Squeaky clean!")
            case .ready:
                say(app.foundTotal > 0 ? "Found you, fluff!" : "Spotless already!")
            default:
                break
            }
        }
        .onChange(of: app.confirmCleanRequested) { _, requested in
            guard requested else { return }
            app.confirmCleanRequested = false
            if app.selectedTotal > 0 { confirming = true }
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

    private var particleMode: ParticleField.Mode {
        switch app.stage {
        case .scanning, .cleaning: return .vacuum
        default: return .drift
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
            Text("Hi, I'm Fussel!")
        case .scanning:
            Text("On the hunt…")
        case .ready:
            if app.foundTotal > 0 {
                HStack(spacing: 0) {
                    Text("Found ")
                    CountingBytes(value: Double(app.foundTotal))
                        .animation(.easeOut(duration: 1.2), value: app.foundTotal)
                }
            } else {
                Text("Already fluff-free!")
            }
        case .cleaning:
            Text("Tidying up…")
        case .done(let freed, _):
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
    }

    @ViewBuilder
    private var subline: some View {
        switch app.stage {
        case .idle:
            Text("Let's find the fluff hiding on your Mac. Psst: you can poke me.")
        case .scanning, .cleaning:
            TimelineView(.periodic(from: .now, by: 1.6)) { context in
                let index = Int(context.date.timeIntervalSinceReferenceDate / 1.6) % Self.scanLines.count
                Text(app.stage == .cleaning ? "Carrying everything to the Trash…" : Self.scanLines[index])
                    .id(index)
                    .transition(.opacity)
            }
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

    @ViewBuilder
    private var action: some View {
        let style = HeroButtonStyle(fill: palette.heroButtonFill, text: palette.heroButtonText)
        switch app.stage {
        case .idle:
            Button("Start Scan") { Task { await app.smartScan() } }
                .buttonStyle(style)
                .keyboardShortcut(.defaultAction)
        case .scanning, .cleaning:
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
                        .buttonStyle(.plain)
                        .font(.rounded(13, .semibold))
                        .foregroundStyle(palette.heroText)
                }
            } else {
                Button("Scan Again") { Task { await app.smartScan() } }
                    .buttonStyle(style)
            }
        case .done:
            Button("Scan Again") { Task { await app.smartScan() } }
                .buttonStyle(style)
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

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(palette.tint(module))
                    Image(systemName: module.symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(palette.icon(module))
                        .symbolEffect(.bounce, value: bounces)
                        .symbolEffect(.pulse, isActive: isBusy)
                }
                .frame(width: 48, height: 48)
                .rotationEffect(.degrees(hovering ? -6 : 0))

                VStack(alignment: .leading, spacing: 4) {
                    Text(module.title)
                        .font(.rounded(15, .bold))
                        .foregroundStyle(palette.text)
                    status
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.secondary)
                    .offset(x: hovering ? 3 : 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(palette.card)
                    .shadow(color: .black.opacity(hovering ? 0.12 : 0.04), radius: hovering ? 14 : 5, y: hovering ? 7 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(palette.cardStroke, lineWidth: 1)
            )
            .scaleEffect(hovering ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { hovering = inside }
            if inside { bounces += 1 }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(duration: 0.55, bounce: 0.35).delay(0.08 * Double(index) + 0.1)) {
                    appeared = true
                }
            }
        }
    }

    private var isBusy: Bool {
        guard module != .uninstaller else { return false }
        let phase = app.model(for: module).phase
        return phase == .scanning || phase == .cleaning
    }

    @ViewBuilder
    private var status: some View {
        if module == .uninstaller {
            Text("Remove apps and their leftovers")
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
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(palette.card))
        .overlay(Capsule().strokeBorder(palette.cardStroke, lineWidth: 1))
    }
}
