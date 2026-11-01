import SwiftUI

/// A short welcome tour over the main window, shown once on the very first start after installing.
/// Four small cards; Skip (or Esc) closes it at any point. On the first start the permissions screen follows.
struct Tutorial: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = PreviewRenderer.tutorialStep
    @State private var blink = false
    /// The step player: how long this card has been up, whether it plays, and a pause while pointed at.
    @State private var elapsed: TimeInterval = PreviewRenderer.isRendering ? 3.4 : 0
    @State private var playing = true
    @State private var pointedAt = false
    private let cardSeconds: TimeInterval = 8
    @AppStorage(UserName.key) private var name = UserName.suggested

    private struct Card {
        let title: String
        let text: String
        let symbol: String?
    }

    private let cards = [
        Card(title: "Hi, I'm Fussel.",
             text: "I help you free up space on your Mac, without any fuss. Here's how it works, in three quick steps.",
             symbol: nil),
        Card(title: "First, I take a look",
             text: "Click Scan and I check caches, logs, the Trash, old downloads and big files. Nothing is removed yet.",
             symbol: "magnifyingglass"),
        Card(title: "Every file gets a label",
             text: "I tell you what each item is. Safe to Remove can go without a second look. Review First is never picked for you.",
             symbol: "checkmark.seal"),
        Card(title: "Clean, and change your mind",
             text: "Everything goes to the Trash first. Changed your mind? Undo puts it right back.",
             symbol: "arrow.uturn.backward"),
    ]

    private var isLast: Bool { step == cards.count - 1 }
    /// The first card asks for a name and the last one waits for Get Started, so only those between run on.
    private var runsOn: Bool { step > 0 && !isLast && !reduceMotion }
    private var running: Bool { runsOn && playing && !pointedAt && !PreviewRenderer.isRendering }

    var body: some View {
        ZStack {
            Color.black.opacity(palette.isDark ? 0.45 : 0.25)
                .ignoresSafeArea()
                .onTapGesture {}

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { finish() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .keyboardShortcut(.cancelAction)
                        .opacity(isLast ? 0 : 1)
                }
                .padding(.bottom, 4)

                let card = cards[step]
                VStack(spacing: 14) {
                    if let symbol = card.symbol {
                        StateIcon(symbol: symbol, size: 84)
                    } else {
                        FusselMark(blink: blink, background: palette.sheet, side: 84, cornerRadius: 22, bodySide: 76)
                    }
                    Text(card.title)
                        .font(.rounded(22, .bold))
                        .foregroundStyle(palette.text)
                    Text(card.text)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 340)
                    if step == 0 {
                        VStack(spacing: 6) {
                            Text("What should I call you?")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.text)
                            TextField("", text: $name, prompt: Text("Your name (optional)"))
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                                .frame(width: 200)
                                .onChange(of: name) { _, new in
                                    if new.count > UserName.limit { name = String(new.prefix(UserName.limit)) }
                                }
                        }
                        .padding(.top, 4)
                    }
                    if step == 2 {
                        HStack(spacing: 8) {
                            SafetyLabel(safe: true)
                            SafetyLabel(safe: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 250)
                .contentShape(Rectangle())
                .onHover { pointedAt = $0 }
                .id(step)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(x: 24)),
                                                                   removal: .opacity.combined(with: .offset(x: -24))))

                HStack {
                    stepPlayer
                    Spacer()
                    if step > 0 {
                        Button("Back") { go(step - 1) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Button(isLast ? "Get Started" : "Next") { isLast ? finish() : go(step + 1) }
                        .buttonStyle(ActionButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 16)
            }
            .padding(24)
            .frame(width: 460)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.sheet))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.cardStroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
        }
        .task(id: "\(step) \(running)") {
            guard running else { return }
            while !Task.isCancelled, elapsed < cardSeconds {
                try? await Task.sleep(for: .milliseconds(50))
                if !Task.isCancelled { elapsed += 0.05 }
            }
            if !Task.isCancelled { go(step + 1) }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.5...5)))
                blink = true
                try? await Task.sleep(for: .milliseconds(140))
                blink = false
            }
        }
    }

    /// A row of dots: the current one stretches into a bar that fills while the card is up, then eases
    /// over to the next dot. Beside it, a small button to pause.
    private var stepPlayer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(cards.indices, id: \.self) { i in
                    Capsule()
                        .fill(palette.text.opacity(i == step && !runsOn ? 1 : 0.18))
                        .frame(width: i == step ? 40 : 6, height: 6)
                        .overlay(alignment: .leading) {
                            if i == step && runsOn {
                                Capsule()
                                    .fill(palette.text)
                                    .frame(width: max(6, 40 * min(1, elapsed / cardSeconds)))
                                    .animation(.linear(duration: 0.05), value: elapsed)
                            }
                        }
                }
            }
            Button { playing.toggle() } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(playing ? "Pause" : "Play")
            .accessibilityLabel(playing ? "Pause" : "Play")
            .opacity(runsOn ? 1 : 0)
            .disabled(!runsOn)
        }
    }

    private func go(_ index: Int) {
        elapsed = 0
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) { step = index }
    }

    private func finish() {
        withAnimation(.easeOut(duration: 0.2)) {
            app.showTutorial = false
            // First start: ask for what Fussel needs right after the tour.
            if app.permissionsAfterTour {
                app.permissionsAfterTour = false
                app.showPermissions = true
            }
        }
    }
}
