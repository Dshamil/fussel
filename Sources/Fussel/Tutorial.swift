import SwiftUI

enum TutorialKey {
    static let seen = "tutorialSeen"
}

/// A five-page welcome tour with Fussel, shown on first launch and from Help › Show Tutorial.
struct TutorialOverlay: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var page = 0
    @State private var forward = true
    @State private var burstDate: Date?
    @State private var finishing = false

    private let lastPage = 4

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}

            VStack(spacing: 0) {
                ZStack {
                    Rectangle().fill(palette.badge)
                    ParticleField(mode: page == 1 ? .vacuum : .drift, tint: palette.speck,
                                  center: UnitPoint(x: 0.5, y: 0.52), burstDate: burstDate)
                    illustration
                        .id(page)
                        .transition(slide)
                }
                .frame(height: 236)
                .clipped()

                VStack(spacing: 8) {
                    Text(title)
                        .font(.rounded(26, .heavy))
                        .foregroundStyle(palette.text)
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    extras
                        .padding(.top, 6)
                }
                .padding(.horizontal, 40)
                .padding(.top, 22)
                .id("text-\(page)")
                .transition(slide)

                Spacer(minLength: 12)

                footer
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
            }
            .frame(width: 540, height: 500)
            .background(palette.sheet)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 16)
        }
        .accessibilityAddTraits(.isModal)
    }

    private var slide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var title: String {
        switch page {
        case 0: return "Hi, I'm Fussel!"
        case 1: return "I hunt for fluff"
        case 2: return "Nothing gets lost"
        case 3: return "Your Mac at a glance"
        default: return "One more thing"
        }
    }

    private var message: String {
        switch page {
        case 0:
            return "A tiny ball of fluff who loves a tidy Mac. I'll keep yours light and quick. Go on, poke me!"
        case 1:
            return "One click and I go hunting: caches, logs, giant files and forgotten downloads. I slurp them all up."
        case 2:
            return "Everything I clean goes to the Trash first. Changed your mind? Just put it back."
        case 3:
            return "Free space, memory, battery, CPU and network, live on the main screen. Tap a tile for more."
        default:
            return "Give me Full Disk Access so I can reach every speck, and pick the look you like best."
        }
    }

    @ViewBuilder
    private var illustration: some View {
        switch page {
        case 0: WelcomeScene(color: palette.mascot)
        case 1: FusselMascot(mood: .busy, size: 140, color: palette.mascot)
        case 2: TrashScene(color: palette.mascot)
        case 3: StatsScene(color: palette.mascot)
        default: KeyScene(color: palette.mascot)
        }
    }

    @ViewBuilder
    private var extras: some View {
        if page == lastPage {
            VStack(spacing: 12) {
                if !app.hasFullDiskAccess {
                    Button("Open Full Disk Access Settings") { Permissions.openFullDiskAccessSettings() }
                        .controlSize(.regular)
                } else {
                    Label("Full Disk Access is on", systemImage: "checkmark.circle.fill")
                        .font(.rounded(13, .semibold))
                        .foregroundStyle(palette.secondary)
                }
                StyleSwitcher()
            }
        }
    }

    private var footer: some View {
        HStack {
            if page < lastPage {
                Button("Skip") { finish(celebrate: false) }
                    .buttonStyle(.plain)
                    .font(.rounded(13, .semibold))
                    .foregroundStyle(palette.secondary)
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0...lastPage, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Theme.coral : palette.text.opacity(0.18))
                        .frame(width: i == page ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(duration: 0.4, bounce: 0.5), value: page)
            .accessibilityElement()
            .accessibilityLabel("Page \(page + 1) of \(lastPage + 1)")
            Spacer()
            HStack(spacing: 10) {
                if page > 0 {
                    Button("Back") { go(to: page - 1) }
                        .buttonStyle(.plain)
                        .font(.rounded(13, .semibold))
                        .foregroundStyle(palette.secondary)
                }
                Button(page == lastPage ? "Let's Go!" : "Next") {
                    if page == lastPage { finish(celebrate: true) } else { go(to: page + 1) }
                }
                .buttonStyle(HeroButtonStyle(fill: palette.heroButtonFill, text: palette.heroButtonText))
                .keyboardShortcut(.defaultAction)
                .disabled(finishing)
            }
        }
    }

    private func go(to newPage: Int) {
        forward = newPage > page
        Sounds.play("Tink")
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) { page = newPage }
    }

    private func finish(celebrate: Bool) {
        UserDefaults.standard.set(true, forKey: TutorialKey.seen)
        guard celebrate else {
            withAnimation(.easeOut(duration: 0.25)) { app.showTutorial = false }
            return
        }
        finishing = true
        burstDate = Date()
        Sounds.play("Glass")
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            withAnimation(.easeOut(duration: 0.3)) { app.showTutorial = false }
        }
    }
}

// MARK: - Scenes

/// Fussel drops in from above, bounces, and says hello.
private struct WelcomeScene: View {
    let color: Color
    @State private var landed = false
    @State private var greeting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FusselMascot(mood: .idle, size: 150, color: color, interactive: true)
            .offset(y: landed ? 0 : -300)
            .overlay(alignment: .topTrailing) {
                if greeting {
                    Text("Hello!")
                        .font(.rounded(14, .heavy))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.white))
                        .offset(x: 46, y: 6)
                        .transition(.scale(scale: 0.3, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
            .onAppear {
                if reduceMotion {
                    landed = true
                    greeting = true
                    return
                }
                withAnimation(.spring(duration: 0.8, bounce: 0.55).delay(0.15)) { landed = true }
                withAnimation(.spring(duration: 0.4, bounce: 0.5).delay(0.9)) { greeting = true }
            }
    }
}

/// Fussel happily tosses little fluffs into the Trash.
private struct TrashScene: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            FusselMascot(mood: .happy, size: 120, color: color)
                .offset(x: -120)
            ZStack {
                Circle().fill(.white).frame(width: 86, height: 86)
                Image(systemName: "trash.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .offset(x: 120, y: 10)
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<3, id: \.self) { k in
                        let p = (t * 0.55 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                        FusselBody(mood: .happy, color: color)
                            .frame(width: 30, height: 30)
                            .rotationEffect(.degrees(p * 360))
                            .offset(x: -80 + 200 * p, y: -10 - 80 * sin(.pi * p))
                            .scaleEffect(1 - 0.4 * p)
                            .opacity(p < 0.85 ? 1 : (1 - p) / 0.15)
                    }
                }
            }
        }
    }
}

/// Little stat bubbles pop up around Fussel and bob gently.
private struct StatsScene: View {
    let color: Color
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let kinds: [StatKind] = [.disk, .memory, .battery, .cpu, .network]

    var body: some View {
        ZStack {
            FusselMascot(mood: .idle, size: 110, color: color)
                .offset(y: 30)
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(Array(kinds.enumerated()), id: \.offset) { index, kind in
                        let angle = Double.pi * (1.1 + 0.8 * Double(index) / Double(kinds.count - 1))
                        ZStack {
                            Circle().fill(kind.pastel)
                            Image(systemName: kind.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                        }
                        .frame(width: 50, height: 50)
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .scaleEffect(shown ? 1 : 0.01)
                        .animation(.spring(duration: 0.5, bounce: 0.6).delay(0.12 * Double(index) + 0.2), value: shown)
                        .offset(x: cos(angle) * 160,
                                y: 40 + sin(angle) * 130 + 5 * sin(t * 2 + Double(index)))
                    }
                }
            }
        }
        .onAppear { shown = true }
    }
}

/// Fussel with a wiggling key: Full Disk Access.
private struct KeyScene: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            FusselMascot(mood: .idle, size: 130, color: color)
                .offset(x: -40)
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    Circle().fill(Color(hex: 0xF9E3A0)).frame(width: 64, height: 64)
                    Image(systemName: "key.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
                .rotationEffect(.degrees(15 * sin(t * 3)))
                .offset(x: 80, y: -40 + 6 * sin(t * 2))
            }
        }
    }
}
