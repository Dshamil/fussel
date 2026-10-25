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

    private static let count = 22
    private static let confettiCount = 44
    private static let confettiColors: [Color] = [
        .white, Color(hex: 0xCFE8DC), Color(hex: 0xDCD5F7), Color(hex: 0xF9E3A0),
        Color(hex: 0xFFD3C4), Theme.ink, Theme.coralDeep,
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            Canvas { ctx, size in
                guard !reduceMotion else { return }
                let t = timeline.date.timeIntervalSinceReferenceDate
                let c = CGPoint(x: center.x * size.width, y: center.y * size.height)

                if mode != .off {
                    for i in 0..<Self.count {
                        drawSpeck(i, t: t, in: size, center: c, ctx: &ctx)
                    }
                }
                if let burstDate {
                    let dt = timeline.date.timeIntervalSince(burstDate)
                    if dt >= 0 && dt < 2.2 {
                        drawConfetti(dt: dt, center: c, ctx: &ctx)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
            let life = (t * (0.45 + 0.35 * r(i, 2)) + r(i, 3)).truncatingRemainder(dividingBy: 1)
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
