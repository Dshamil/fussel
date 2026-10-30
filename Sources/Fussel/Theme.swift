import SwiftUI
import AppKit

/// Fussel's grid. Spacing: 4, 8, 12, 16, 24, 32 pt. Type: 11 labels, 12 secondary, 13 body,
/// 15 emphasis, 22 titles, 30 the big number. Corners: 6 chips, 8 buttons and rows, 12 cards, 16 sheets.
enum Theme {
    /// Fussel's color, the same as the app icon's tile.
    static let graphite = Color(hex: 0x2B2D33)
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

/// The main action: a solid rounded key, dark on light and light on dark. It stands on a darker
/// base a few points deep and sinks onto it when pressed, so a click feels like pressing a real key.
struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TactileKey(pressed: configuration.isPressed) { configuration.label }
    }
}

/// The look of `ActionButtonStyle`, also drawn on its own for screenshots of the pressed state.
struct TactileKey<Label: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    let pressed: Bool
    @ViewBuilder var label: Label
    /// How far the key stands above its base.
    private let depth: CGFloat = 3

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.buttonText)
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(shape.fill(palette.buttonFill))
            // A thin light edge along the top, as if light fell on the key.
            .overlay(shape.stroke(Color.white.opacity(palette.isDark ? 0.5 : 0.16), lineWidth: 1).offset(y: 1).clipShape(shape))
            .modifier(HoverTint(color: palette.buttonText.opacity(0.1)))
            .offset(y: pressed ? depth : 0)
            // The base sits below the key without taking up room, so the button keeps its height in a row.
            .background(shape.fill(palette.buttonFill).overlay(shape.fill(.black.opacity(palette.isDark ? 0.28 : 0.45))).offset(y: depth))
            .opacity(isEnabled ? 1 : 0.4)
            .animation(pressed ? .easeOut(duration: 0.07) : .spring(duration: 0.3, bounce: 0.35), value: pressed)
    }
}

/// A quieter action next to the main one.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 16)
            .frame(height: 30)
            .cardSurface(palette, radius: 8)
            .modifier(HoverTint(color: palette.text.opacity(0.06)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.4), value: configuration.isPressed)
    }
}

/// Under the pointer, a button lights up a touch. Nothing moves, so passing over it stays calm.
struct HoverTint: ViewModifier {
    let color: Color
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering && isEnabled ? color : .clear))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Text that counts up to a byte size instead of jumping.
struct CountingBytes: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(Int64(value).byteString)
    }
}

/// Presses squish a little and spring back.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.55), value: configuration.isPressed)
    }
}
