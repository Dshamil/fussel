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

/// The fluff body with its two eyes, drawn in a square frame.
struct FusselBody: View {
    var mood: MascotMood
    var color: Color = .white

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

            if mood == .happy {
                for (ex, ey) in FusselGeometry.eyes {
                    var arc = Path()
                    arc.move(to: CGPoint(x: (ex - 2.6) * s, y: (ey + 1) * s))
                    arc.addQuadCurve(
                        to: CGPoint(x: (ex + 2.6) * s, y: (ey + 1) * s),
                        control: CGPoint(x: ex * s, y: (ey - 3.5) * s)
                    )
                    ctx.stroke(arc, with: .color(Theme.ink),
                               style: StrokeStyle(lineWidth: 1.7 * s, lineCap: .round))
                }
            } else {
                for (ex, ey) in FusselGeometry.eyes {
                    ctx.fill(Path(ellipseIn: circle(ex, ey, FusselGeometry.eyeRadius)), with: .color(Theme.ink))
                    ctx.fill(Path(ellipseIn: circle(ex - 0.8, ey - 0.9, 0.8)), with: .color(.white))
                }
            }
        }
    }
}

/// Fussel floating above its shadow, gently bobbing. Busy = faster wobble, happy = closed eyes.
struct FusselMascot: View {
    var mood: MascotMood = .idle
    var size: CGFloat = 140
    var showShadow = true

    var body: some View {
        AnimatedMascot(mood: mood, size: size, showShadow: showShadow)
            .id(mood)
            .accessibilityHidden(true)
    }
}

private struct AnimatedMascot: View {
    let mood: MascotMood
    let size: CGFloat
    let showShadow: Bool
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var duration: Double { mood == .busy ? 0.42 : 1.8 }
    private var lift: CGFloat {
        switch mood {
        case .busy: return up ? -0.08 : 0.0
        case .idle: return up ? -0.045 : 0.0
        case .happy: return up ? -0.07 : -0.02
        }
    }
    private var tilt: Double {
        switch mood {
        case .busy: return up ? -16 : -4
        default: return up ? -12 : -9
        }
    }

    var body: some View {
        ZStack {
            if showShadow {
                Ellipse()
                    .fill(Color.black.opacity(up ? 0.10 : 0.17))
                    .frame(width: size * 0.26 * (up ? 0.82 : 1), height: size * 0.056)
                    .offset(x: -size * 0.02, y: size * 0.33)
            }
            FusselBody(mood: mood)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(tilt))
                .offset(x: size * 0.04, y: -size * 0.06 + lift * size)
        }
        .frame(width: size, height: size)
        .onAppear {
            // Respect Reduce Motion: Fussel still changes its face, but stops bobbing.
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                up = true
            }
        }
    }
}

/// Fussel on its coral squircle, like the app icon.
struct FusselBadge: View {
    var mood: MascotMood = .idle
    var size: CGFloat = 170

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Theme.coralGradient)
                .shadow(color: Theme.coralDeep.opacity(0.35), radius: size * 0.08, y: size * 0.05)
            FusselMascot(mood: mood, size: size)
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
