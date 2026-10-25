import SwiftUI

/// Little specks of fluff around Fussel.
/// - drift: they float upwards slowly
/// - vacuum: they spiral into Fussel while it scans
/// - a burst of colourful confetti after cleaning
struct ParticleField: View {
    enum Mode: Equatable { case drift, vacuum, off }

    var mode: Mode
    var tint: Color
    /// Where Fussel sits, relative to the field.
    var center: UnitPoint
    var burstDate: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationsPaused) private var paused
    @Environment(\.controlActiveState) private var activeState

    private static let count = 16
    private static let confettiCount = 44
    private static let confettiColors: [Color] = [
        .white, Color(hex: 0xCFE8DC), Color(hex: 0xDCD5F7), Color(hex: 0xF9E3A0),
        Color(hex: 0xFFD3C4), Theme.ink, Theme.coralDeep,
    ]

    /// Confetti and the scan vortex get the full frame rate; gentle drifting gets a light one.
    private var frameInterval: Double {
        let bursting = burstDate.map { Date().timeIntervalSince($0) < 2.2 } ?? false
        if mode == .vacuum || bursting {
            return AnimationBudget.interval(busy: true, active: activeState)
        }
        return AnimationBudget.driftInterval(active: activeState)
    }

    private static let fileSymbols = [
        "doc.fill", "photo.fill", "music.note", "gearshape.fill", "film.fill", "archivebox.fill", "sparkle",
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval,
                                paused: reduceMotion || paused || AnimationBudget.still || (mode == .off && burstDate == nil))) { timeline in
            Canvas { ctx, size in
                guard !reduceMotion else { return }
                let t = timeline.date.timeIntervalSinceReferenceDate
                let c = CGPoint(x: center.x * size.width, y: center.y * size.height)

                if mode == .vacuum {
                    drawGlowAndRings(t: t, center: c, ctx: &ctx)
                }
                if mode != .off {
                    let count = mode == .vacuum ? 40 : Self.count
                    for i in 0..<count {
                        drawSpeck(i, t: t, in: size, center: c, ctx: &ctx)
                    }
                }
                if let burstDate {
                    let dt = timeline.date.timeIntervalSince(burstDate)
                    if dt >= 0 && dt < 2.2 {
                        drawConfetti(dt: dt, center: c, ctx: &ctx)
                    }
                }
            } symbols: {
                ForEach(Array(Self.fileSymbols.enumerated()), id: \.offset) { index, name in
                    Image(systemName: name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tint)
                        .tag(index)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A pulsing glow behind Fussel and rings that ripple outwards while it scans.
    private func drawGlowAndRings(t: Double, center c: CGPoint, ctx: inout GraphicsContext) {
        let pulse = 0.5 + 0.5 * sin(t * 4)
        let glow = 90 + 14 * pulse
        ctx.fill(
            Path(ellipseIn: CGRect(x: c.x - glow, y: c.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(Gradient(colors: [tint.opacity(0.22 + 0.12 * pulse), tint.opacity(0)]),
                                  center: c, startRadius: 0, endRadius: glow)
        )
        for k in 0..<3 {
            let life = (t / 1.5 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            let r = 60 + 190 * life
            let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.stroke(ring, with: .color(tint.opacity(0.35 * (1 - life))), lineWidth: 2)
        }
    }

    /// Cheap deterministic noise so every speck keeps its own personality.
    private static func rnd(_ i: Int, _ k: Int) -> Double {
        let v = sin(Double(i * 127 + k * 311 + 17) * 12.9898) * 43758.5453
        return v - floor(v)
    }

    private func drawSpeck(_ i: Int, t: Double, in size: CGSize, center c: CGPoint, ctx: inout GraphicsContext) {
        let r = Self.rnd
        let radius = 2.2 + 3.2 * r(i, 1)
        var point: CGPoint
        var alpha: Double

        switch mode {
        case .vacuum:
            let life = (t * (0.6 + 0.45 * r(i, 2)) + r(i, 3)).truncatingRemainder(dividingBy: 1)
            let maxR = max(size.width, size.height) * (0.35 + 0.25 * r(i, 4))
            let dist = maxR * (1 - life)
            let angle = r(i, 5) * 2 * .pi + life * 5.5
            point = CGPoint(x: c.x + cos(angle) * dist, y: c.y + sin(angle) * dist * 0.75)
            alpha = min(1, (1 - life) * 2.5) * min(1, life * 6) * 0.85
        default:
            let speed = 0.012 + 0.02 * r(i, 6)
            let y = (r(i, 7) - t * speed).truncatingRemainder(dividingBy: 1)
            let yy = y < 0 ? y + 1 : y
            let x = r(i, 8) + 0.025 * sin(t * (0.5 + r(i, 9)) + r(i, 10) * 6)
            point = CGPoint(x: x * size.width, y: yy * size.height)
            alpha = 0.18 + 0.32 * r(i, 11)
            // Fade near the top and bottom edges.
            alpha *= min(1, yy * 6) * min(1, (1 - yy) * 6)
        }

        // While vacuuming, every third particle is a little file icon tumbling into Fussel.
        if mode == .vacuum, i % 3 == 0,
           let symbol = ctx.resolveSymbol(id: (i / 3) % Self.fileSymbols.count) {
            var piece = ctx
            piece.opacity = alpha
            piece.translateBy(x: point.x, y: point.y)
            piece.rotate(by: .radians(t * (1.5 + 2 * r(i, 12))))
            let scale = 0.7 + 0.5 * r(i, 13)
            piece.scaleBy(x: scale, y: scale)
            piece.draw(symbol, at: .zero)
            return
        }

        var speck = Path()
        speck.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius * 0.8, width: radius * 1.6, height: radius * 1.6))
        speck.addEllipse(in: CGRect(x: point.x - radius * 0.2, y: point.y - radius, width: radius * 1.4, height: radius * 1.4))
        speck.addEllipse(in: CGRect(x: point.x - radius * 0.5, y: point.y - radius * 0.2, width: radius * 1.5, height: radius * 1.3))
        ctx.fill(speck, with: .color(tint.opacity(alpha)))
    }

    private func drawConfetti(dt: Double, center c: CGPoint, ctx: inout GraphicsContext) {
        let r = Self.rnd
        let fade = max(0, 1 - dt / 2.2)
        for i in 0..<Self.confettiCount {
            let angle = -.pi / 2 + (r(i, 20) - 0.5) * 2.6
            let speed = 260 + 260 * r(i, 21)
            let x = c.x + cos(angle) * speed * dt
            let y = c.y + sin(angle) * speed * dt + 0.5 * 620 * dt * dt
            let color = Self.confettiColors[i % Self.confettiColors.count]
            let w = 5 + 5 * r(i, 22)
            let h = r(i, 23) > 0.5 ? w : w * 0.45
            var piece = ctx
            piece.translateBy(x: x, y: y)
            piece.rotate(by: .radians(dt * (4 + 8 * r(i, 24)) * (r(i, 25) > 0.5 ? 1 : -1)))
            let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            let shape = r(i, 26) > 0.6 ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
            piece.fill(shape, with: .color(color.opacity(fade)))
        }
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
