import SwiftUI

/// A short welcome tour over the main window, shown once on the very first start after installing.
/// Five small cards; Skip (or Esc) closes it at any point.
struct Tutorial: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var blink = false

    private struct Card {
        let title: String
        let text: String
        let symbol: String?
    }

    private let cards = [
        Card(title: "Hi, I'm Fussel.",
             text: "I help you free up space on your Mac, calmly. Here's how it works, in four quick steps.",
             symbol: nil),
        Card(title: "First, I take a look",
             text: "Click Scan and I check caches, logs, the Trash, old downloads and big files. Nothing is removed yet.",
             symbol: "magnifyingglass"),
        Card(title: "Every file gets a label",
             text: "I tell you what each item is. Safe to Clean can go without a second look. Check First is never picked for you.",
             symbol: "checkmark.seal"),
        Card(title: "Clean, and change your mind",
             text: "Everything goes to the Trash first. Changed your mind? Undo puts it right back.",
             symbol: "arrow.uturn.backward"),
        Card(title: "Let me see everything",
             text: "With Full Disk Access I can reach the Trash and every hidden cache. You can allow it now or later.",
             symbol: "lock.open"),
    ]

    private var isLast: Bool { step == cards.count - 1 }

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
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.graphite)
                                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(Color.white.opacity(palette.isDark ? 0.14 : 0), lineWidth: 1))
                            FusselBody(blink: blink).equatable().frame(width: 76, height: 76)
                        }
                        .frame(width: 84, height: 84)
                    }
                    Text(card.title)
                        .font(.rounded(24, .bold))
                        .foregroundStyle(palette.text)
                    Text(card.text)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 340)
                    if step == 2 {
                        HStack(spacing: 8) {
                            SafetyLabel(safe: true)
                            SafetyLabel(safe: false)
                        }
                    }
                    if isLast {
                        Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 250)
                .id(step)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(x: 24)),
                                                                   removal: .opacity.combined(with: .offset(x: -24))))

                HStack {
                    HStack(spacing: 6) {
                        ForEach(cards.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == step ? palette.text : palette.text.opacity(0.18))
                                .frame(width: i == step ? 16 : 6, height: 6)
                        }
                    }
                    Spacer()
                    if step > 0 {
                        Button("Back") { go(step - 1) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Button(isLast ? "Get Started" : "Next") { isLast ? finish() : go(step + 1) }
                        .buttonStyle(ActionButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 18)
            }
            .padding(24)
            .frame(width: 460)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.sheet))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.cardStroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
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

    private func go(_ index: Int) {
        withAnimation(.spring(duration: 0.25)) { step = index }
    }

    private func finish() {
        withAnimation(.easeOut(duration: 0.2)) { app.showTutorial = false }
    }
}
