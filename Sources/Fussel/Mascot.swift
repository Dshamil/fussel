import SwiftUI
import AppKit

/// Geometry of the Fussel character, in the same 100×100 design space as the app icon.
enum FusselGeometry {
    static let body: [(CGFloat, CGFloat, CGFloat)] = [
        (50, 52, 16), (64, 52, 9), (59.9, 61.9, 9), (50, 66, 9), (40.1, 61.9, 9),
        (36, 52, 9), (40.1, 42.1, 9), (50, 38, 9), (59.9, 42.1, 9),
    ]
    static let eyes: [(CGFloat, CGFloat)] = [(45, 51), (55, 51)]
    static let eyeRadius: CGFloat = 2.6
}

enum MascotMood: Equatable {
    case idle, busy, happy
}

/// The fluff body and its face, drawn in a square frame.
struct FusselBody: View {
    var mood: MascotMood
    var color: Color = .white
    var blink = false
    /// Where the eyes look, in design units (about ±1.4).
    var look: CGSize = .zero
    var surprised = false
    var cheeks = false

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 100
            func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGRect {
                CGRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s)
            }

            var fluff = Path()
            for (x, y, r) in FusselGeometry.body {
                fluff.addEllipse(in: circle(x, y, r))
            }
            ctx.fill(fluff, with: .color(color))

            let ink = Theme.ink
            if cheeks || mood == .happy {
                for cx in [40.5, 59.5] as [CGFloat] {
                    ctx.fill(Path(ellipseIn: circle(cx, 56.5, 2.4)), with: .color(Color(hex: 0xF6A795).opacity(0.75)))
                }
            }

            if mood == .happy && !surprised {
                for (ex, ey) in FusselGeometry.eyes {
                    var arc = Path()
                    arc.move(to: CGPoint(x: (ex - 2.6) * s, y: (ey + 1) * s))
                    arc.addQuadCurve(to: CGPoint(x: (ex + 2.6) * s, y: (ey + 1) * s),
                                     control: CGPoint(x: ex * s, y: (ey - 3.5) * s))
                    ctx.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 1.7 * s, lineCap: .round))
                }
                return
            }

            let r = surprised ? 3.3 : FusselGeometry.eyeRadius
            for (ex, ey) in FusselGeometry.eyes {
                let x = ex + look.width
                let y = ey + look.height
                if blink {
                    var lid = Path()
                    lid.move(to: CGPoint(x: (x - 2.4) * s, y: y * s))
                    lid.addLine(to: CGPoint(x: (x + 2.4) * s, y: y * s))
                    ctx.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round))
                } else {
                    ctx.fill(Path(ellipseIn: circle(x, y, r)), with: .color(ink))
                    ctx.fill(Path(ellipseIn: circle(x - 0.8, y - 0.9, r * 0.32)), with: .color(.white))
                }
            }
            if surprised {
                ctx.fill(Path(ellipseIn: circle(50 + look.width * 0.5, 58, 1.6)), with: .color(ink))
            }
        }
    }
}

/// Fussel floating above its shadow. Bobs with a little squash and stretch, blinks now and then,
/// follows the pointer with its eyes and does a flip when clicked.
struct FusselMascot: View {
    var mood: MascotMood = .idle
    var size: CGFloat = 140
    var showShadow = true
    var color: Color = .white
    /// Unit vector towards the pointer, or nil to look ahead.
    var lookAt: CGVector? = nil
    var interactive = false
    var onPoke: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blink = false
    @State private var pokeDate = Date.distantPast
    @State private var pokeCount = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            let m = motion(at: timeline.date)
            ZStack {
                if showShadow {
                    Ellipse()
                        .fill(Color.black.opacity(0.17 - Double(m.height) * 0.6))
                        .frame(width: size * 0.26 * (1 - m.height * 1.6), height: size * 0.056)
                        .offset(x: -size * 0.02, y: size * 0.33)
                }
                FusselBody(
                    mood: mood,
                    color: color,
                    blink: blink && !m.surprised,
                    look: look,
                    surprised: m.surprised,
                    cheeks: m.surprised
                )
                .frame(width: size, height: size)
                .scaleEffect(x: m.scaleX, y: m.scaleY, anchor: .bottom)
                .rotationEffect(.degrees(m.tilt + m.spin))
                .offset(x: size * 0.04, y: -size * 0.06 - m.height * size)
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .contentShape(Circle().scale(0.6))
        .onTapGesture {
            guard interactive else { return }
            pokeCount += 1
            pokeDate = Date()
            onPoke?()
        }
        .task(id: mood) {
            // Blink every few seconds.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.2...5.0)))
                if Task.isCancelled { break }
                blink = true
                try? await Task.sleep(for: .milliseconds(130))
                blink = false
            }
        }
        .accessibilityHidden(true)
    }

    private var look: CGSize {
        guard let v = lookAt else { return .zero }
        return CGSize(width: v.dx * 1.4, height: v.dy * 1.1)
    }

    private struct Motion {
        var height: CGFloat = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var tilt: Double = -10
        var spin: Double = 0
        var surprised = false
    }

    private func motion(at date: Date) -> Motion {
        var m = Motion()
        let t = date.timeIntervalSinceReferenceDate
        if !reduceMotion {
            switch mood {
            case .idle:
                let wave = sin(t * 2.3)
                m.height = 0.025 + 0.025 * CGFloat(wave)
                m.tilt = -10 + 2.5 * sin(t * 1.15)
                let squash = CGFloat(max(0, -wave))
                m.scaleX = 1 + 0.035 * squash
                m.scaleY = 1 - 0.035 * squash
            case .busy:
                let wave = sin(t * 11)
                m.height = 0.03 + 0.03 * CGFloat(wave)
                m.tilt = -10 + 9 * sin(t * 5.5)
                let squash = CGFloat(max(0, -wave))
                m.scaleX = 1 + 0.06 * squash
                m.scaleY = 1 - 0.06 * squash
            case .happy:
                let hop = abs(sin(t * 3.4))
                m.height = 0.11 * CGFloat(hop)
                m.tilt = -10 + 6 * sin(t * 3.4)
                let landing = CGFloat(pow(1 - hop, 6))
                m.scaleX = 1 + 0.09 * landing
                m.scaleY = 1 - 0.09 * landing
            }
        }

        // Poke: a little jump with a full flip.
        let dt = date.timeIntervalSince(pokeDate)
        if dt >= 0 && dt < 0.75 {
            let p = dt / 0.75
            m.height += 0.16 * CGFloat(sin(.pi * p))
            if !reduceMotion {
                let eased = 1 - pow(1 - p, 3)
                m.spin = (pokeCount % 2 == 0 ? -360 : 360) * eased
            }
            m.surprised = p < 0.8
        }
        return m
    }
}

/// Fussel on its squircle, like the app icon.
struct FusselBadge: View {
    var mood: MascotMood = .idle
    var size: CGFloat = 170
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(palette.badge)
                .shadow(color: Theme.coralDeep.opacity(palette.isDark ? 0 : 0.3), radius: size * 0.08, y: size * 0.05)
            FusselMascot(mood: mood, size: size, color: palette.mascot)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Monochrome template image of Fussel for the menu bar.
enum MenuBarIcon {
    static let image: NSImage = {
        let side: CGFloat = 18
        let img = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            // Fluff spans x 27…73 and y 29…75 in design units; fit it into the rect.
            let s = (rect.width - 2) / 46
            let ox = 1 - 27 * s
            let oy = 1 - 29 * s
            func oval(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> NSRect {
                NSRect(x: ox + (x - r) * s, y: oy + (y - r) * s, width: 2 * r * s, height: 2 * r * s)
            }
            NSColor.black.setFill()
            let fluff = NSBezierPath()
            for (x, y, r) in FusselGeometry.body {
                fluff.appendOval(in: oval(x, y, r))
            }
            fluff.fill()

            NSGraphicsContext.current?.compositingOperation = .destinationOut
            for (ex, ey) in FusselGeometry.eyes {
                NSBezierPath(ovalIn: oval(ex, ey, 3.1)).fill()
            }
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        img.isTemplate = true
        return img
    }()
}
