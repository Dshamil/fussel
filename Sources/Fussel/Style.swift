import SwiftUI
import AppKit

/// The three looks of Fussel, plus following the system.
enum AppStyle: String, CaseIterable, Identifiable {
    case system, light, dark, coral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Automatic"
        case .light: return "White"
        case .dark: return "Dark"
        case .coral: return "Coral"
        }
    }

    /// The system appearance each style runs on.
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light, .coral: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
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
    /// Pastel per card, borrowed from the first icon sketches.
    var tint: (Module) -> Color
    var icon: (Module) -> Color

    static func pastel(_ module: Module) -> Color {
        switch module {
        case .junk: return Color(hex: 0xCFE8DC)        // mint
        case .large: return Color(hex: 0xDCD5F7)       // lavender
        case .uninstaller: return Color(hex: 0xF9E3A0) // butter
        case .tidy: return Color(hex: 0xFFD3C4)        // peach
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
        tint: { pastel($0) },
        icon: { _ in Theme.ink }
    )

    static func resolve(_ style: AppStyle, scheme: ColorScheme) -> Palette {
        switch style {
        case .light: return .white
        case .dark: return .dark
        case .coral: return .coral
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

extension EnvironmentValues {
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
    @Environment(\.colorScheme) private var scheme
    /// Used for rendering previews without touching the real setting.
    var override: AppStyle?
    @ViewBuilder var content: Content

    private var style: AppStyle { override ?? storedStyle }

    var body: some View {
        content
            .environment(\.palette, Palette.resolve(style, scheme: scheme))
            .environment(\.appStyle, style)
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
