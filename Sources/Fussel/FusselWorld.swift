import SwiftUI

/// Fussel's little world in the hero: floorboards, a beam of light, a few lost things and the fluff
/// piles a scan finds. Kept soft and muted so Fussel stays the star. Only redraws when the piles change.
struct FusselWorld: View, Animatable {
    /// 0…1, how much fluff lies on the floor (grows while scanning, gone after cleaning).
    var pile: Double
    var isDark: Bool

    var animatableData: Double {
        get { pile }
        set { pile = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let floorTop = h - 54

            // Light falling in from above.
            var beam = Path()
            beam.move(to: CGPoint(x: w * 0.6, y: 0))
            beam.addLine(to: CGPoint(x: w * 0.72, y: 0))
            beam.addLine(to: CGPoint(x: w * 0.9, y: floorTop))
            beam.addLine(to: CGPoint(x: w * 0.66, y: floorTop))
            beam.closeSubpath()
            ctx.fill(beam, with: .color(.white.opacity(isDark ? 0.05 : 0.13)))

            // Floorboards.
            ctx.fill(Path(CGRect(x: 0, y: floorTop, width: w, height: h - floorTop)),
                     with: .color(.black.opacity(isDark ? 0.22 : 0.09)))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.66, y: floorTop - 4, width: w * 0.26, height: 16)),
                     with: .color(.white.opacity(isDark ? 0.04 : 0.12)))
            var boards = Path()
            boards.addRect(CGRect(x: 0, y: floorTop, width: w, height: 1))
            boards.addRect(CGRect(x: 0, y: floorTop + 27, width: w, height: 1))
            for x in stride(from: 90.0, to: w, by: 170) {
                boards.addRect(CGRect(x: x, y: floorTop, width: 1, height: 27))
                boards.addRect(CGRect(x: x + 85, y: floorTop + 27, width: 1, height: h - floorTop))
            }
            ctx.fill(boards, with: .color(.black.opacity(isDark ? 0.18 : 0.08)))

            drawLostThings(&ctx, w: w, floorTop: floorTop)
            drawPiles(&ctx, w: w, floorTop: floorTop)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A coin, a Lego brick and a striped sock, drawn a bit faded so they stay in the background.
    private func drawLostThings(_ ctx: inout GraphicsContext, w: CGFloat, floorTop: CGFloat) {
        // Things lie a bit forward on the floor, so they never touch the buttons above.
        let floorTop = floorTop + 16
        var things = ctx
        things.opacity = isDark ? 0.55 : 0.8

        let brick = Color(hex: 0x5B8FE8)
        let bx = w * 0.66
        things.fill(Path(roundedRect: CGRect(x: bx, y: floorTop - 10, width: 22, height: 12), cornerRadius: 2), with: .color(brick))
        for dx in [3.0, 13.0] {
            things.fill(Path(roundedRect: CGRect(x: bx + dx, y: floorTop - 14, width: 6, height: 5), cornerRadius: 1.5), with: .color(brick))
        }

        let cx = w * 0.76
        things.fill(Path(ellipseIn: CGRect(x: cx, y: floorTop + 2, width: 22, height: 8)), with: .color(Color(hex: 0xD9A93A)))
        things.fill(Path(ellipseIn: CGRect(x: cx, y: floorTop, width: 22, height: 8)), with: .color(Color(hex: 0xF5C95A)))

        // A floppy sock lying on its side: the leg flat along the floor, the foot flopped towards us.
        var sockCtx = things
        sockCtx.translateBy(x: w * 0.83, y: floorTop - 12)
        sockCtx.rotate(by: .degrees(-6))
        var line = Path()
        line.move(to: CGPoint(x: 6, y: 6))
        line.addQuadCurve(to: CGPoint(x: 27, y: 7), control: CGPoint(x: 17, y: 4))
        line.addQuadCurve(to: CGPoint(x: 37, y: 19), control: CGPoint(x: 36, y: 8))
        let sock = line.strokedPath(StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
        sockCtx.fill(Path(ellipseIn: CGRect(x: 2, y: 17, width: 42, height: 10)), with: .color(.black.opacity(0.1)))
        sockCtx.fill(sock, with: .color(Color(hex: 0xFFF4EE)))
        // Ribbed cuff at the open end.
        sockCtx.fill(Path(roundedRect: CGRect(x: -1, y: -1.5, width: 7, height: 15), cornerRadius: 3), with: .color(Color(hex: 0xFFFFFF)))
        var colored = sockCtx
        colored.clip(to: sock)
        var stripes = Path()
        stripes.addRect(CGRect(x: 9, y: -4, width: 3.5, height: 22))
        stripes.addRect(CGRect(x: 15.5, y: -4, width: 3.5, height: 22))
        stripes.addEllipse(in: CGRect(x: 28, y: 15, width: 18, height: 14))
        stripes.addEllipse(in: CGRect(x: 22, y: -2, width: 13, height: 14))
        colored.fill(stripes, with: .color(Color(hex: 0x7BC6A4)))
    }

    /// Fluff piles on the floor, bigger the more Fussel found.
    private func drawPiles(_ ctx: inout GraphicsContext, w: CGFloat, floorTop: CGFloat) {
        guard pile > 0.01 else { return }
        let color = Color(hex: isDark ? 0xCFCBD8 : 0xFFF1EC).opacity(isDark ? 0.5 : 0.85)
        let piles: [(x: CGFloat, size: CGFloat)] = [(0.4, 1), (0.53, 0.7), (0.27, 0.5)]
        for (x, size) in piles {
            let s = CGFloat(pile) * size
            guard s > 0.2 else { continue }
            let base = CGPoint(x: w * x, y: floorTop + 22)
            var fluff = Path()
            for (dx, dy, r) in [(-14.0, -2.0, 8.0), (0, -7, 12), (13, -3, 9), (24, 0, 6), (-24, 1, 5)] as [(CGFloat, CGFloat, CGFloat)] {
                fluff.addEllipse(in: CGRect(x: base.x + dx * s - r * s, y: base.y + dy * s - r * s,
                                            width: r * s * 2, height: r * s * 2))
            }
            ctx.fill(fluff, with: .color(color))
        }
    }
}
