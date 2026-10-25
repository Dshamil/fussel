import SwiftUI
import AppKit

enum Theme {
    static let coral = Color(hex: 0xF2836B)
    static let coralLight = Color(hex: 0xF69A84)
    static let coralDeep = Color(hex: 0xEC6E56)
    static let ink = Color(hex: 0x2B2B33)

    static var coralGradient: LinearGradient {
        LinearGradient(colors: [coralLight, coralDeep], startPoint: .top, endPoint: .bottom)
    }

    /// Solid deep coral for white-text buttons: white on #C94A33 is 4.7:1, on #B83D27 5.6:1.
    static var actionGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xC94A33), Color(hex: 0xB83D27)], startPoint: .top, endPoint: .bottom)
    }

    /// Coral for text and icons on cards: #C2412A on white is 5.1:1, #F2836B on the dark card 5.8:1.
    static let accentText = Color.dynamic(light: 0xC2412A, dark: 0xF2836B)

    /// System backgrounds, so Fussel follows light, dark and increased-contrast appearances.
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let cardStroke = Color(nsColor: .separatorColor)
}

extension Color {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// Ink pill with white text, for the main action on top of the coral hero (14:1).
struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(15, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 11)
            .background(Capsule().fill(Theme.ink))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
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

/// The big coral pill button used for the main action on each screen.
struct CoralButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(15, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Theme.actionGradient)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
