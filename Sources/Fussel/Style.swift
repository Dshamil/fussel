import SwiftUI
import AppKit

/// Every color the custom parts of Fussel use. Calm grays that follow the Mac's light or dark
/// appearance; color is kept for the small tool icons, the storage bar and the safety labels.
struct Palette {
    var isDark: Bool
    var content: Color
    var sidebar: Color
    var selection: Color
    var card: Color
    var cardStroke: Color
    var text: Color
    var secondary: Color
    var buttonFill: Color
    var buttonText: Color
    var mascot: Color
    var speck: Color
    var badge: LinearGradient
    var sheet: Color

    /// One color per tool, used for its icon square and its slice of the storage bar.
    func accent(_ module: Module) -> Color {
        switch module {
        case .junk: return Color(hex: 0x3FAE7C)
        case .tidy: return Color(hex: 0xEC7357)
        case .large: return Color(hex: 0x8B78EC)
        case .uninstaller: return Color(hex: 0xE5A33A)
        case .updates: return Color(hex: 0x3D8BE0)
        case .closet: return Color(hex: 0xE0709F)
        }
    }

    static let safe = Color(hex: 0x30A46C)
    static let caution = Color(hex: 0xD99A1E)

    static let coralGradient = LinearGradient(colors: [Color(hex: 0xF69A84), Color(hex: 0xEC6E56)],
                                              startPoint: .top, endPoint: .bottom)

    static let light = Palette(
        isDark: false,
        content: .white,
        sidebar: Color(hex: 0xF3F3F5),
        selection: Color(hex: 0xE3E3E8),
        card: Color(hex: 0xF7F7F9),
        cardStroke: Color(hex: 0xE6E6EB),
        text: Color(hex: 0x1D1D1F),
        secondary: Color(hex: 0x6E6E73),
        buttonFill: Color(hex: 0x1D1D1F),
        buttonText: .white,
        mascot: .white,
        speck: .white,
        badge: coralGradient,
        sheet: .white
    )

    static let dark = Palette(
        isDark: true,
        content: Color(hex: 0x1E1E20),
        sidebar: Color(hex: 0x262629),
        selection: Color(hex: 0x38383D),
        card: Color(hex: 0x262629),
        cardStroke: Color(hex: 0x333337),
        text: Color(hex: 0xF2F2F2),
        secondary: Color(hex: 0x98989F),
        buttonFill: Color(hex: 0xF2F2F2),
        buttonText: Color(hex: 0x1D1D1F),
        mascot: Color(hex: 0xF4F1EC),
        speck: Color(hex: 0xF4F1EC),
        badge: coralGradient,
        sheet: Color(hex: 0x1E1E20)
    )
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.light
}

private struct AnimationsPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set where an animation is hidden behind something else (e.g. the room under the tutorial).
    var animationsPaused: Bool {
        get { self[AnimationsPausedKey.self] }
        set { self[AnimationsPausedKey.self] = newValue }
    }

    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Wraps a scene's content: picks the palette for the Mac's appearance and the costume Fussel wears.
struct StyledRoot<Content: View>: View {
    @AppStorage(Costume.storageKey) private var storedCostume: String = Costume.auto.rawValue
    @Environment(\.colorScheme) private var scheme
    /// Used for rendering previews without touching the real setting.
    var costumeOverride: Costume? = nil
    @ViewBuilder var content: Content

    /// The crown stays in the closet until it's earned.
    private var wornCostume: Costume {
        let chosen = (Costume(rawValue: storedCostume) ?? .auto).resolved()
        if let badge = chosen.requiredBadge, !Achievements.shared.has(badge) { return .none }
        return chosen
    }

    var body: some View {
        content
            .environment(\.palette, scheme == .dark ? .dark : .light)
            .environment(\.costume, costumeOverride ?? wornCostume)
    }
}

enum Sounds {
    static func play(_ name: String) {
        let enabled = UserDefaults.standard.object(forKey: SettingsKey.sounds) as? Bool ?? false
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
