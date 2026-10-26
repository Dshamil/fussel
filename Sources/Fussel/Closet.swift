import SwiftUI
import AppKit

// MARK: - Costumes

enum Costume: String, CaseIterable, Identifiable {
    case auto, none, santa, witch, party, sunglasses, crown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Seasonal"
        case .none: return "Just Fluff"
        case .santa: return "Santa Hat"
        case .witch: return "Witch Hat"
        case .party: return "Party Hat"
        case .sunglasses: return "Shades"
        case .crown: return "Crown"
        }
    }

    /// The crown has to be earned.
    var requiredBadge: String? { self == .crown ? "gb-50" : nil }

    /// What Fussel actually wears today. "Seasonal" follows the calendar.
    func resolved(on date: Date = Date()) -> Costume {
        guard self == .auto else { return self }
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        switch (parts.month ?? 0, parts.day ?? 0) {
        case (12, _): return .santa
        case (1, 1): return .party
        case (10, 15...31): return .witch
        case (6...8, _): return .sunglasses
        default: return .none
        }
    }

    static let storageKey = "costume"

    static var current: Costume {
        let stored = Costume(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .auto
        return stored.resolved()
    }
}

private struct CostumeKey: EnvironmentKey {
    static let defaultValue = Costume.none
}

extension EnvironmentValues {
    /// The costume Fussel wears right now (already resolved for "Seasonal").
    var costume: Costume {
        get { self[CostumeKey.self] }
        set { self[CostumeKey.self] = newValue }
    }
}

/// Draws a costume on top of Fussel, in the same 100×100 design space as the body.
enum CostumeArt {
    static func draw(_ costume: Costume, in ctx: GraphicsContext, scale s: CGFloat) {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        func shape(_ points: [(CGFloat, CGFloat)]) -> Path {
            var p = Path()
            p.addLines(points.map { pt($0.0, $0.1) })
            p.closeSubpath()
            return p
        }
        func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s))
        }

        switch costume {
        case .santa:
            ctx.fill(shape([(37, 36), (63, 35), (66, 22), (71, 13), (60, 20), (48, 24)]), with: .color(Color(hex: 0xE5484D)))
            ctx.fill(shape([(35, 33.5), (65, 32.5), (65.5, 38.5), (35.5, 39.5)]), with: .color(.white))
            ctx.fill(dot(71, 13, 3.6), with: .color(.white))
        case .witch:
            ctx.fill(Path(ellipseIn: CGRect(x: 31 * s, y: 30.2 * s, width: 38 * s, height: 7.6 * s)), with: .color(Color(hex: 0x3B2466)))
            ctx.fill(shape([(40, 34), (60, 34), (56, 22), (60, 8), (50, 18)]), with: .color(Color(hex: 0x4B2E83)))
            ctx.fill(shape([(40.5, 30.5), (59.5, 30.5), (59, 33.5), (41, 33.5)]), with: .color(Color(hex: 0xF5A524)))
        case .party:
            ctx.fill(shape([(42, 34), (58, 34), (50, 12)]), with: .color(Color(hex: 0x7CC4F2)))
            ctx.fill(shape([(44, 28.5), (56, 28.5), (54.9, 25.9), (45.1, 25.9)]), with: .color(Color(hex: 0xF9E3A0)))
            ctx.fill(shape([(46.4, 21.9), (53.6, 21.9), (52.6, 19.3), (47.4, 19.3)]), with: .color(Color(hex: 0xF9E3A0)))
            ctx.fill(dot(50, 11, 3), with: .color(Color(hex: 0xF2836B)))
        case .sunglasses:
            for ex in [45.0, 55.0] as [CGFloat] {
                ctx.fill(shape([(ex - 4.3, 48.2), (ex + 4.3, 48.2), (ex + 3.6, 54.2), (ex - 3.6, 54.2)]),
                         with: .color(Color(hex: 0x1F1F26)))
                ctx.fill(shape([(ex - 2.8, 49.2), (ex - 1.2, 49.2), (ex - 2.2, 52.4), (ex - 3.2, 52.4)]),
                         with: .color(.white.opacity(0.6)))
            }
            ctx.fill(shape([(48.6, 49.2), (51.4, 49.2), (51.4, 50.2), (48.6, 50.2)]), with: .color(Color(hex: 0x1F1F26)))
        case .crown:
            ctx.fill(shape([(39, 35), (61, 35), (62, 22), (56.5, 28), (50, 19), (43.5, 28), (38, 22)]),
                     with: .color(Color(hex: 0xF5C542)))
            ctx.fill(dot(44, 31.5, 1.4), with: .color(Color(hex: 0x7CC4F2)))
            ctx.fill(dot(50, 31.5, 1.4), with: .color(Color(hex: 0xE5484D)))
            ctx.fill(dot(56, 31.5, 1.4), with: .color(Color(hex: 0x7CC4F2)))
        case .auto, .none:
            break
        }
    }
}

// MARK: - App icon

enum AppIconVariant: String, CaseIterable, Identifiable {
    case pur, plastisch, glas, abendhimmel, dark, tinted, santa, witch, party, sunglasses, crown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pur: return "Classic"
        case .plastisch: return "Plush"
        case .glas: return "Glass"
        case .abendhimmel: return "Sunset"
        case .dark: return "Night"
        case .tinted: return "Graphite"
        case .santa: return "Santa"
        case .witch: return "Spooky"
        case .party: return "Party"
        case .sunglasses: return "Summer"
        case .crown: return "Royal"
        }
    }

    var requiredBadge: String? { self == .crown ? "gb-50" : nil }

    var image: NSImage? {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "AppIcons") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    static let storageKey = "appIconVariant"

    static var current: AppIconVariant {
        AppIconVariant(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .pur
    }
}

enum IconChanger {
    /// Gives Fussel.app a new icon in Finder, Programme and Spotlight.
    @discardableResult
    static func apply(_ variant: AppIconVariant) -> Bool {
        let path = Bundle.main.bundlePath
        let ok: Bool
        if variant == .pur {
            ok = NSWorkspace.shared.setIcon(nil, forFile: path, options: [])
        } else if let image = variant.image {
            ok = NSWorkspace.shared.setIcon(image, forFile: path, options: [])
        } else {
            ok = false
        }
        if ok {
            UserDefaults.standard.set(variant.rawValue, forKey: AppIconVariant.storageKey)
            NSApp.applicationIconImage = variant.image
        }
        return ok
    }

    /// After an update the installer brings the classic icon back; restore the chosen one.
    static func reapplyIfNeeded() {
        let variant = AppIconVariant.current
        guard variant != .pur else { return }
        apply(variant)
    }
}

// MARK: - Badges

struct Badge: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
}

enum BadgeEvent {
    case scanned, cleaned, uninstalled, undid, poked, restyled, speedTest, checkedUpdates
}

/// Little achievements. Earned badges are stored in UserDefaults.
@Observable
@MainActor
final class Achievements {
    static let shared = Achievements()

    static let all: [Badge] = [
        Badge(id: "first-scan", title: "First Sniff", detail: "Run your first scan", symbol: "magnifyingglass", tint: Color(hex: 0xCDE4F7)),
        Badge(id: "first-clean", title: "Fluff Buster", detail: "Clean up for the first time", symbol: "sparkles", tint: Color(hex: 0xCFE8DC)),
        Badge(id: "gb-1", title: "Gigabyte Gobbler", detail: "Clear 1 GB in total", symbol: "externaldrive", tint: Color(hex: 0xFFD3C4)),
        Badge(id: "gb-10", title: "Dust Devil", detail: "Clear 10 GB in total", symbol: "tornado", tint: Color(hex: 0xDCD5F7)),
        Badge(id: "gb-50", title: "Fluff Royalty", detail: "Clear 50 GB in total. Unlocks the crown", symbol: "crown", tint: Color(hex: 0xF9E3A0)),
        Badge(id: "cleans-10", title: "Tidy Habit", detail: "Clean up 10 times", symbol: "repeat", tint: Color(hex: 0xCFE8DC)),
        Badge(id: "uninstall", title: "Goodbye App", detail: "Uninstall an app", symbol: "xmark.bin", tint: Color(hex: 0xFFD3C4)),
        Badge(id: "undo", title: "Second Thoughts", detail: "Undo a clean-up", symbol: "arrow.uturn.backward", tint: Color(hex: 0xDCD5F7)),
        Badge(id: "pokes", title: "Tickle Monster", detail: "Poke Fussel 10 times", symbol: "hand.point.up.left", tint: Color(hex: 0xF8D0E4)),
        Badge(id: "night", title: "Night Owl", detail: "Scan between midnight and 5 am", symbol: "moon.stars", tint: Color(hex: 0xCDE4F7)),
        Badge(id: "style", title: "Fashionista", detail: "Try a new style, costume or icon", symbol: "paintpalette", tint: Color(hex: 0xF8D0E4)),
        Badge(id: "speed", title: "Speed Demon", detail: "Run a speed test", symbol: "bolt", tint: Color(hex: 0xF9E3A0)),
        Badge(id: "updates", title: "Fresh Apps", detail: "Check your apps for updates", symbol: "arrow.down.circle", tint: Color(hex: 0xCFE8DC)),
    ]

    private(set) var earned: Set<String>
    /// The badge that was just unlocked, for the celebration in the main window.
    var justEarned: Badge?

    private let earnedKey = "badges"
    private let pokesKey = "pokeCount"
    private let cleansKey = "cleanCount"

    init() {
        earned = Set(UserDefaults.standard.stringArray(forKey: earnedKey) ?? [])
    }

    func has(_ id: String) -> Bool { earned.contains(id) }

    func record(_ event: BadgeEvent) {
        let defaults = UserDefaults.standard
        switch event {
        case .scanned:
            earn("first-scan")
            let hour = Calendar.current.component(.hour, from: Date())
            if hour < 5 { earn("night") }
        case .cleaned:
            earn("first-clean")
            let cleans = defaults.integer(forKey: cleansKey) + 1
            defaults.set(cleans, forKey: cleansKey)
            if cleans >= 10 { earn("cleans-10") }
            checkTotals()
        case .uninstalled:
            earn("uninstall")
            checkTotals()
        case .undid:
            earn("undo")
        case .poked:
            let pokes = defaults.integer(forKey: pokesKey) + 1
            defaults.set(pokes, forKey: pokesKey)
            if pokes >= 10 { earn("pokes") }
        case .restyled:
            earn("style")
        case .speedTest:
            earn("speed")
        case .checkedUpdates:
            earn("updates")
        }
    }

    private func checkTotals() {
        let total = CleanHistory.shared.totalFreed
        if total >= 1_000_000_000 { earn("gb-1") }
        if total >= 10_000_000_000 { earn("gb-10") }
        if total >= 50_000_000_000 { earn("gb-50") }
    }

    private func earn(_ id: String) {
        guard !earned.contains(id), let badge = Self.all.first(where: { $0.id == id }) else { return }
        earned.insert(id)
        UserDefaults.standard.set(Array(earned), forKey: earnedKey)
        justEarned = badge
    }
}

// MARK: - App icon picker (in Settings)

struct IconPicker: View {
    @State private var selected = AppIconVariant.current
    @State private var message: String?

    var body: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                ForEach(AppIconVariant.allCases) { variant in
                    Button {
                        if IconChanger.apply(variant) {
                            selected = variant
                            message = "Done! Fussel now wears the \(variant.title) icon in Finder and Programme."
                            Achievements.shared.record(.restyled)
                            Sounds.play("Pop")
                        } else {
                            message = "I couldn't change my icon. Reinstall Fussel with the latest installer and try again."
                        }
                    } label: {
                        IconChoice(variant: variant, selected: selected == variant)
                    }
                    .buttonStyle(CardPressStyle())
                    .accessibilityLabel(variant.title + " icon")
                }
            }
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text("Fussel lives in the menu bar, so the icon shows in Finder, Programme and Spotlight.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
}

/// One icon to pick: the chosen one sits on a soft tile with a checkmark, instead of a ring that
/// fights the icon's own shape.
private struct IconChoice: View {
    @Environment(\.palette) private var palette
    let variant: AppIconVariant
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            if let image = variant.image {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .scaleEffect(hovering ? 1.06 : 1)
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(.white, Palette.safe)
                                .offset(x: 2, y: 2)
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                        }
                    }
            }
            Text(variant.title)
                .font(.system(size: 11, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? palette.text : palette.secondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? palette.selection : .clear))
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.spring(duration: 0.3, bounce: 0.5)) { hovering = inside } }
        .animation(.spring(duration: 0.35, bounce: 0.5), value: selected)
    }
}
