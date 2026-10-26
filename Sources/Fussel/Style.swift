import SwiftUI
import AppKit

/// The four looks of Fussel, plus following the system.
enum AppStyle: String, CaseIterable, Identifiable {
    case system, light, dark, coral, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Automatic"
        case .light: return "White"
        case .dark: return "Dark"
        case .coral: return "Coral"
        case .graphite: return "Graphite"
        }
    }

    /// The system appearance each style runs on.
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light, .coral: return NSAppearance(named: .aqua)
        case .dark, .graphite: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Every color the custom parts of Fussel use. System controls (lists, checkboxes) follow the
/// appearance that the style sets.
struct Palette {
    var isDark: Bool
    var canvas: LinearGradient
    var card: Color
    var cardStroke: Color
    var text: Color
    var secondary: Color
    var heroFill: LinearGradient
    var heroStroke: Color
    var heroText: Color
    var heroButtonFill: Color
    var heroButtonText: Color
    var mascot: Color
    var speck: Color
    var badge: LinearGradient
    var sheet: Color
    /// Two soft color clouds behind everything: top right and bottom left.
    var blobs: (Color, Color)
    /// Pastel per card, borrowed from the first icon sketches.
    var tint: (Module) -> Color
    var icon: (Module) -> Color
    /// False for Graphite: cards and tiles drop their pastels and stay gray.
    var colorful = true

    static func pastel(_ module: Module) -> Color {
        switch module {
        case .junk: return Color(hex: 0xCFE8DC)        // mint
        case .large: return Color(hex: 0xDCD5F7)       // lavender
        case .uninstaller: return Color(hex: 0xF9E3A0) // butter
        case .updates: return Color(hex: 0xCDE4F7)     // sky
        case .closet: return Color(hex: 0xF8D0E4)      // pink
        case .tidy: return Color(hex: 0xFFD3C4)        // peach
        }
    }

    /// A deeper shade of each pastel, so cards cast a colored glow instead of a gray smudge.
    static func shadow(_ module: Module) -> Color {
        switch module {
        case .junk: return Color(hex: 0x3E9A72)
        case .large: return Color(hex: 0x6A55C8)
        case .uninstaller: return Color(hex: 0xC99A1C)
        case .updates: return Color(hex: 0x3B82C4)
        case .closet: return Color(hex: 0xC8508A)
        case .tidy: return Color(hex: 0xE0603F)
        }
    }

    static let coralGradient = LinearGradient(colors: [Color(hex: 0xF69A84), Color(hex: 0xEC6E56)],
                                              startPoint: .top, endPoint: .bottom)
    static func solid(_ hex: UInt32) -> LinearGradient {
        LinearGradient(colors: [Color(hex: hex), Color(hex: hex)], startPoint: .top, endPoint: .bottom)
    }

    /// White: clean and bright, coral only in the hero.
    static let white = Palette(
        isDark: false,
        canvas: solid(0xFFFFFF),
        card: Color(hex: 0xF5F5F7),
        cardStroke: Color(hex: 0xE8E8ED),
        text: Color(hex: 0x1D1D22),
        secondary: Color(hex: 0x5F5F6B),
        heroFill: coralGradient,
        heroStroke: .clear,
        heroText: Theme.ink,
        heroButtonFill: Theme.ink,
        heroButtonText: .white,
        mascot: .white,
        speck: .white,
        badge: coralGradient,
        sheet: Color(hex: 0xFFFFFF),
        blobs: (Theme.coral.opacity(0.13), Color(hex: 0xDCD5F7).opacity(0.55)),
        tint: { pastel($0) },
        icon: { _ in Theme.ink }
    )

    /// Dark: the night-blue of the dark app icon, coral as the glowing accent.
    static let dark = Palette(
        isDark: true,
        canvas: LinearGradient(colors: [Color(hex: 0x1B1C24), Color(hex: 0x131419)], startPoint: .top, endPoint: .bottom),
        card: Color(hex: 0x23242D),
        cardStroke: Color(hex: 0x30313C),
        text: Color(hex: 0xF4F1EC),
        secondary: Color(hex: 0xA6A6B2),
        heroFill: LinearGradient(colors: [Color(hex: 0x363A5E), Color(hex: 0x1E1F31)], startPoint: .topLeading, endPoint: .bottomTrailing),
        heroStroke: .white.opacity(0.07),
        heroText: Color(hex: 0xF4F1EC),
        heroButtonFill: Theme.coral,
        heroButtonText: Theme.ink,
        mascot: Color(hex: 0xF4F1EC),
        speck: Color(hex: 0xF4F1EC),
        badge: LinearGradient(colors: [Color(hex: 0x33364F), Color(hex: 0x1B1C2B)], startPoint: .top, endPoint: .bottom),
        sheet: Color(hex: 0x1C1D24),
        blobs: (Color(hex: 0x3A3F6E).opacity(0.7), Theme.coral.opacity(0.08)),
        tint: { pastel($0).opacity(0.16) },
        icon: { pastel($0) }
    )

    /// Coral: the whole window wears the brand color.
    static let coral = Palette(
        isDark: false,
        canvas: LinearGradient(colors: [Color(hex: 0xF79C86), Color(hex: 0xEA6A52)], startPoint: .top, endPoint: .bottom),
        card: .white.opacity(0.9),
        cardStroke: .white.opacity(0.6),
        text: Theme.ink,
        secondary: Color(hex: 0x5C4743),
        heroFill: LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
        heroStroke: .white.opacity(0.4),
        heroText: Theme.ink,
        heroButtonFill: Theme.ink,
        heroButtonText: .white,
        mascot: .white,
        speck: .white,
        badge: coralGradient,
        sheet: Color(hex: 0xFFF6F2),
        blobs: (.white.opacity(0.28), Color(hex: 0xF9E3A0).opacity(0.25)),
        tint: { pastel($0) },
        icon: { _ in Theme.ink }
    )

    /// Graphite: one calm dark gray, no gradients, color only where it means something.
    static let graphite = Palette(
        isDark: true,
        canvas: solid(0x1C1C1E),
        card: Color(hex: 0x2A2A2D),
        cardStroke: Color(hex: 0x37373B),
        text: Color(hex: 0xF2F2F2),
        secondary: Color(hex: 0xA1A1A6),
        heroFill: solid(0x2A2A2D),
        heroStroke: .white.opacity(0.06),
        heroText: Color(hex: 0xF2F2F2),
        heroButtonFill: Color(hex: 0xF2F2F2),
        heroButtonText: Color(hex: 0x1C1C1E),
        mascot: Color(hex: 0xF4F1EC),
        speck: Color(hex: 0xC7C7CC),
        badge: solid(0x2A2A2D),
        sheet: Color(hex: 0x232325),
        blobs: (.clear, .clear),
        tint: { _ in .white.opacity(0.07) },
        icon: { _ in Color(hex: 0xD1D1D6) },
        colorful: false
    )

    static func resolve(_ style: AppStyle, scheme: ColorScheme) -> Palette {
        switch style {
        case .light: return .white
        case .dark: return .dark
        case .coral: return .coral
        case .graphite: return .graphite
        case .system: return scheme == .dark ? .dark : .white
        }
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.white
}

private struct StyleKey: EnvironmentKey {
    static let defaultValue = AppStyle.system
}

private struct AnimationsPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set where an animation is hidden behind something else (e.g. the hero under the tutorial).
    var animationsPaused: Bool {
        get { self[AnimationsPausedKey.self] }
        set { self[AnimationsPausedKey.self] = newValue }
    }

    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
    var appStyle: AppStyle {
        get { self[StyleKey.self] }
        set { self[StyleKey.self] = newValue }
    }
}

/// Wraps a scene's content: resolves the palette and applies the style's appearance app-wide.
struct StyledRoot<Content: View>: View {
    @AppStorage(SettingsKey.appStyle) private var storedStyle: AppStyle = .system
    @AppStorage(Costume.storageKey) private var storedCostume: String = Costume.auto.rawValue
    @Environment(\.colorScheme) private var scheme
    /// Used for rendering previews without touching the real setting.
    var override: AppStyle?
    var costumeOverride: Costume? = nil
    @ViewBuilder var content: Content

    private var style: AppStyle { override ?? storedStyle }

    /// The crown stays in the closet until it's earned.
    private var wornCostume: Costume {
        let chosen = (Costume(rawValue: storedCostume) ?? .auto).resolved()
        if let badge = chosen.requiredBadge, !Achievements.shared.has(badge) { return .none }
        return chosen
    }

    var body: some View {
        content
            .environment(\.palette, Palette.resolve(style, scheme: scheme))
            .environment(\.appStyle, style)
            .environment(\.costume, costumeOverride ?? wornCostume)
            .onAppear { apply(style) }
            .onChange(of: storedStyle) { _, newStyle in apply(newStyle) }
    }

    private func apply(_ style: AppStyle) {
        guard override == nil else { return }
        NSApplication.shared.appearance = style.appearance
    }
}

/// Four little dots to switch styles right from the window.
struct StyleSwitcher: View {
    @AppStorage(SettingsKey.appStyle) private var style: AppStyle = .system
    @Environment(\.appStyle) private var activeStyle
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppStyle.allCases) { option in
                Button {
                    withAnimation(.spring(duration: 0.35)) { style = option }
                    Achievements.shared.record(.restyled)
                    Sounds.play("Tink")
                } label: {
                    swatch(option)
                        .frame(width: 18, height: 18)
                        .padding(3)
                        .overlay(
                            Circle().strokeBorder(palette.text.opacity(activeStyle == option ? 0.7 : 0), lineWidth: 1.5)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(option.title)
                .accessibilityLabel("\(option.title) style")
                .accessibilityAddTraits(activeStyle == option ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(palette.card))
        .overlay(Capsule().strokeBorder(palette.cardStroke, lineWidth: 1))
    }

    @ViewBuilder
    private func swatch(_ option: AppStyle) -> some View {
        switch option {
        case .system:
            Circle()
                .fill(LinearGradient(colors: [.white, .white, Color(hex: 0x23242D), Color(hex: 0x23242D)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
        case .light:
            Circle().fill(.white)
                .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
        case .dark:
            Circle().fill(LinearGradient(colors: [Color(hex: 0x363A5E), Color(hex: 0x1B1C2B)], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        case .coral:
            Circle().fill(Palette.coralGradient)
        case .graphite:
            Circle().fill(Color(hex: 0x3A3A3E))
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        }
    }
}

enum Sounds {
    static func play(_ name: String) {
        let enabled = UserDefaults.standard.object(forKey: SettingsKey.sounds) as? Bool ?? true
        guard enabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

/// Frame rate budget for Fussel's animations: smooth when it matters, calm otherwise.
enum AnimationBudget {
    /// FUSSEL_STILL=1 freezes all animations (used to measure what they cost).
    static let still = ProcessInfo.processInfo.environment["FUSSEL_STILL"] != nil

    /// Seconds between frames. Fast moves (a poke, scanning, a happy hop, confetti) get 60 fps; calm
    /// floating looks the same at 30 and costs half. A window behind others runs at half the rate.
    /// Specks drift slowly, so they get the calm rate.
    static func driftInterval(active: ControlActiveState) -> Double {
        active == .inactive ? 1.0 / 15 : 1.0 / 30
    }

    static func interval(busy: Bool, active: ControlActiveState) -> Double {
        let fps: Double = busy ? 60 : 30
        return active == .inactive ? 2 / fps : 1 / fps
    }
}
