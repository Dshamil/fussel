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

    /// Warm off-white in light mode, deep ink in dark mode.
    static let canvas = Color.dynamic(light: 0xF6F3EE, dark: 0x1B1C22)
    static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x262730)
    static let cardStroke = Color.dynamic(light: 0xEAE5DE, dark: 0x33343E)
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

/// White pill with coral text, for use on top of the coral hero.
struct WhiteButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(15, .semibold))
            .foregroundStyle(Theme.coralDeep)
            .padding(.horizontal, 24)
            .padding(.vertical, 11)
            .background(Capsule().fill(.white))
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
    var byteString: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
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
                Capsule().fill(Theme.coralGradient)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
