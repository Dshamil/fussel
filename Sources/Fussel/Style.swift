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
    var sheet: Color
    /// The Glass style: the desktop shows through a blur and cards are made of glass.
    var isGlass = false

    /// One color per tool, used for its icon square and its slice of the storage bar.
    func accent(_ module: Module) -> Color {
        switch module {
        case .junk: return Color(hex: 0x3FAE7C)
        case .tidy: return Color(hex: 0xE5484D)
        case .large: return Color(hex: 0x8B78EC)
        case .uninstaller: return Color(hex: 0xE5A33A)
        case .updates: return Color(hex: 0x3D8BE0)
        }
    }

    static let safe = Color(hex: 0x30A46C)
    static let caution = Color(hex: 0xD99A1E)

    static let light = Palette(
        isDark: false,
        content: .white,
        sidebar: Color(hex: 0xF3F3F5),
        selection: Color(hex: 0xE3E3E8),
        card: Color(hex: 0xF7F7F9),
        cardStroke: Color(hex: 0xE6E6EB),
        text: Color(hex: 0x1D1D1F),
        secondary: Color(hex: 0x6E6E73),
        buttonFill: Theme.graphite,
        buttonText: .white,
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
        sheet: Color(hex: 0x1E1E20)
    )

    /// The Oreo style: a white sidebar next to a black main area.
    static let oreoSide: Palette = {
        var p = Palette.light
        p.sidebar = .white
        p.selection = Color(hex: 0xEDEDF0)
        return p
    }()

    /// The main area of Oreo is exactly the Dark style.
    static let oreoMain = Palette.dark

    static let glassLight = Palette(
        isDark: false,
        content: .clear,
        sidebar: Color.white.opacity(0.22),
        selection: Color.white.opacity(0.6),
        card: Color.white.opacity(0.45),
        cardStroke: Color.white.opacity(0.7),
        text: Color(hex: 0x1D1D1F),
        secondary: Color(hex: 0x56565C),
        buttonFill: Theme.graphite,
        buttonText: .white,
        sheet: .white,
        isGlass: true
    )

    static let glassDark = Palette(
        isDark: true,
        content: .clear,
        sidebar: Color.white.opacity(0.04),
        selection: Color.white.opacity(0.14),
        card: Color.white.opacity(0.08),
        cardStroke: Color.white.opacity(0.14),
        text: Color(hex: 0xF2F2F2),
        secondary: Color(hex: 0xA8A8AF),
        buttonFill: Color(hex: 0xF2F2F2),
        buttonText: Color(hex: 0x1D1D1F),
        sheet: Color(hex: 0x1E1E20),
        isGlass: true
    )
}

/// The look picked in Settings: follow the Mac, always light, always dark, or Glass (which follows
/// the Mac's light or dark).
enum AppearanceChoice: String, CaseIterable {
    case system, light, dark, glass, oreo

    static var current: AppearanceChoice {
        AppearanceChoice(rawValue: UserDefaults.standard.string(forKey: SettingsKey.appearance) ?? "") ?? .system
    }

    static func apply() {
        switch current {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark, .oreo: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system, .glass: NSApp.appearance = nil
        }
    }
}

extension View {
    /// A card's surface: a soft fill with a hairline, or real glass in the Glass style.
    func cardSurface(_ palette: Palette, radius: CGFloat) -> some View {
        modifier(CardSurface(palette: palette, radius: radius))
    }
}

private struct CardSurface: ViewModifier {
    let palette: Palette
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // Screenshots can't draw glass, so they get the plain see-through fill below.
        if palette.isGlass && !PreviewRenderer.isRendering {
            // Real glass needs the macOS 26 SDK (Xcode 26); older toolchains build the frosted fallback.
            #if compiler(>=6.2)
            if #available(macOS 26, *) {
                content
                    .glassEffect(.regular, in: shape)
                    .overlay(shape.strokeBorder(palette.cardStroke, lineWidth: 1))
            } else {
                frosted(content, shape)
            }
            #else
            frosted(content, shape)
            #endif
        } else {
            content
                .background(shape.fill(palette.card))
                .overlay(shape.strokeBorder(palette.cardStroke, lineWidth: 1))
        }
    }

    private func frosted(_ content: Content, _ shape: RoundedRectangle) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(palette.cardStroke, lineWidth: 1))
    }
}

/// The Glass style's window background: the desktop, blurred.
struct GlassBackdrop: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            if PreviewRenderer.isRendering {
                // Screenshots can't see the desktop; a plain, neutral stand-in takes its place.
                LinearGradient(colors: palette.isDark ? [Color(hex: 0x34353A), Color(hex: 0x26272B)]
                                                      : [Color(hex: 0xE4E4E7), Color(hex: 0xD2D3D7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                // Just the frosted desktop: no added glow, so the colors are the user's own.
                WindowBlur()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct WindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = SeeThroughView()
        // The see-through kind of frost: everything behind is blurred, but its colors shine through.
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Makes its window see-through while it is shown, and solid again once it goes away.
private final class SeeThroughView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let window {
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
        }
        super.viewWillMove(toWindow: newWindow)
    }
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

/// Wraps a scene's content and picks the palette for the Mac's appearance.
struct StyledRoot<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceChoice.system.rawValue
    @ViewBuilder var content: Content

    var body: some View {
        let glass = appearance == AppearanceChoice.glass.rawValue
        let palette: Palette = appearance == AppearanceChoice.oreo.rawValue ? .oreoMain
            : scheme == .dark ? (glass ? .glassDark : .dark) : (glass ? .glassLight : .light)
        content
            .environment(\.palette, palette)
            .onChange(of: appearance) { AppearanceChoice.apply() }
    }
}

enum Sounds {
    static func play(_ name: String) {
        let enabled = UserDefaults.standard.object(forKey: SettingsKey.sounds) as? Bool ?? false
        guard enabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
