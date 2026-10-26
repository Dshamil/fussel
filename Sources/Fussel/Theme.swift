import SwiftUI
import AppKit

enum Theme {
    static let coral = Color(hex: 0xF2836B)
    static let coralDeep = Color(hex: 0xEC6E56)
    static let ink = Color(hex: 0x2B2B33)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Int64 {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false // "0 KB", not "Zero KB"
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f
    }()

    var byteString: String {
        Self.byteFormatter.string(fromByteCount: self)
    }
}

/// A light action without a pill: bold tinted text and a small round badge with a symbol.
/// On hover the badge grows and nudges forward; pressing squishes it.
struct NudgeButtonStyle: ButtonStyle {
    var tint: Color
    /// Color of the symbol inside the badge.
    var badgeText: Color
    var symbol = "arrow.right"
    var size: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        NudgeButton(configuration: configuration, style: self)
    }

    private struct NudgeButton: View {
        let configuration: ButtonStyleConfiguration
        let style: NudgeButtonStyle
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            HStack(spacing: style.size * 0.5) {
                configuration.label
                    .font(.rounded(style.size, .bold))
                    .foregroundStyle(style.tint)
                Image(systemName: style.symbol)
                    .font(.system(size: style.size * 0.7, weight: .heavy))
                    .foregroundStyle(style.badgeText)
                    .frame(width: style.size * 1.45, height: style.size * 1.45)
                    .background(Circle().fill(style.tint))
                    .scaleEffect(hovering ? 1.18 : 1)
                    .offset(x: hovering ? 2 : 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.spring(duration: 0.22, bounce: 0.5), value: configuration.isPressed)
            .animation(.spring(duration: 0.3, bounce: 0.55), value: hovering)
            .onHover { hovering = $0 }
        }
    }
}

/// The main action on each detail screen: the same pill as on the hero, in the style's colors.
struct ActionButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        HeroButtonStyle(fill: palette.heroButtonFill, text: palette.heroButtonText)
            .makeBody(configuration: configuration)
    }
}
