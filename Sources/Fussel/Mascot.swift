import SwiftUI
import AppKit

/// Geometry of the Fussel character in a 100×100 design space, the same as the app icon
/// (design/AppIcon.icon at 1024 px, divided by 10.24): a round fluff ball with one bold curl on top.
enum FusselGeometry {
    static let ball = CGPoint(x: 50, y: 54)
    static let radius: CGFloat = 25.4
    /// The curl swings around this point, where it grows out of the ball.
    static let curlBase = CGPoint(x: 51.5, y: 30)
    /// The curl: a loop and a short strand, both starting inside the ball. Small drawings (menu bar,
    /// sidebar badge) end the loop a bit earlier and let the strand lean further out, so the two
    /// don't melt into one blob.
    static func curl(small: Bool = false, _ p: (CGFloat, CGFloat) -> CGPoint) -> (loop: Path, strand: Path) {
        var loop = Path()
        loop.move(to: p(50, 30))
        loop.addQuadCurve(to: p(50, 12.7), control: p(42, 18))
        if small { loop.addQuadCurve(to: p(57, 15.5), control: p(58.3, 9.8)) }
        else { loop.addQuadCurve(to: p(58.7, 18.7), control: p(58.7, 9.4)) }
        var strand = Path()
        strand.move(to: p(53.3, 30))
        if small { strand.addQuadCurve(to: p(71, 31), control: p(63, 27)) }
        else { strand.addQuadCurve(to: p(66.7, 23.3), control: p(60, 22)) }
        return (loop, strand)
    }
    static let loopWidth: CGFloat = 4.7
    static let strandWidth: CGFloat = 4.0
    static let eyes: [CGPoint] = [CGPoint(x: 42.7, y: 55.4), CGPoint(x: 57.3, y: 55.4)]
    static let eyeSize = CGSize(width: 6.6, height: 10.8)
}

enum MascotMood: Equatable {
    case idle, busy, happy
    /// Disk almost full.
    case stuffed
    /// CPU running hot.
    case hot
    /// Battery almost empty.
    case sleepy
}

/// Fussel's ball, curl and eyes, drawn in a square frame. `curlTilt` swings the curl (in degrees).
/// Equatable, so SwiftUI only redraws it when something actually changes.
struct FusselBody: View, Equatable {
    var mood: MascotMood = .idle
    var color: Color = .white
    var eyeColor: Color = Theme.graphite
    var blink = false
    var curlTilt: Double = 0

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 100
            let g = FusselGeometry.self
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            var curl = ctx
            curl.translateBy(x: g.curlBase.x * s, y: g.curlBase.y * s)
            curl.rotate(by: .degrees(curlTilt))
            curl.translateBy(x: -g.curlBase.x * s, y: -g.curlBase.y * s)
            let small = s < 0.48
            let (loop, strand) = g.curl(small: small, p)
            // Small sizes get a little extra weight, so the curl doesn't turn into a hairline.
            curl.stroke(loop, with: .color(color), style: StrokeStyle(lineWidth: max(g.loopWidth * s, 1.5), lineCap: .round))
            curl.stroke(strand, with: .color(color), style: StrokeStyle(lineWidth: max(g.strandWidth * s, 1.35), lineCap: .round))

            let r = g.radius
            ctx.fill(Path(ellipseIn: CGRect(x: (g.ball.x - r) * s, y: (g.ball.y - r) * s, width: 2 * r * s, height: 2 * r * s)),
                     with: .color(color))

            let w = g.eyeSize.width, h = g.eyeSize.height
            for eye in g.eyes {
                if mood == .happy || mood == .sleepy || blink {
                    // Closed: smiling for happy, drooping for sleepy, flat for a blink.
                    var lid = Path()
                    let bend: CGFloat = mood == .happy ? -4 : (mood == .sleepy ? 3 : 0)
                    lid.move(to: p(eye.x - w / 2 - 0.6, eye.y))
                    lid.addQuadCurve(to: p(eye.x + w / 2 + 0.6, eye.y), control: p(eye.x, eye.y + bend))
                    ctx.stroke(lid, with: .color(eyeColor), style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round))
                } else {
                    ctx.fill(Path(ellipseIn: CGRect(x: (eye.x - w / 2) * s, y: (eye.y - h / 2) * s,
                                                    width: w * s, height: h * s)),
                             with: .color(eyeColor))
                }
            }
        }
    }
}

/// Monochrome template images of Fussel for the menu bar: plain, with a dot when the weekly check
/// found something, happy after cleaning, and with a swinging curl while he scans.
enum MenuBarIcon {
    static let image: NSImage = make()
    static let imageWithDot: NSImage = make(dot: true)
    static let happy: NSImage = make(happy: true)
    /// Busy frames: the curl swings back and forth.
    static let busy: [NSImage] = [0.0, -16, 0, 16].map { make(curlTilt: $0) }

    private static func make(dot: Bool = false, happy: Bool = false, curlTilt: Double = 0) -> NSImage {
        let side: CGFloat = 18
        let img = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            let g = FusselGeometry.self
            // The design spans about y 6…80; scale that to fill the icon.
            let s = rect.height / 75
            cg.translateBy(x: rect.midX - 50 * s, y: -6 * s)
            cg.scaleBy(x: s, y: s)

            cg.setFillColor(NSColor.black.cgColor)
            cg.setStrokeColor(NSColor.black.cgColor)
            cg.setLineCap(.round)
            cg.saveGState()
            cg.translateBy(x: g.curlBase.x, y: g.curlBase.y)
            cg.rotate(by: curlTilt * .pi / 180)
            cg.translateBy(x: -g.curlBase.x, y: -g.curlBase.y)
            let (loop, strand) = g.curl(small: true) { CGPoint(x: $0, y: $1) }
            cg.setLineWidth(g.loopWidth)
            cg.addPath(loop.cgPath)
            cg.strokePath()
            cg.setLineWidth(g.strandWidth)
            cg.addPath(strand.cgPath)
            cg.strokePath()
            cg.restoreGState()
            let r = g.radius
            cg.fillEllipse(in: CGRect(x: g.ball.x - r, y: g.ball.y - r, width: 2 * r, height: 2 * r))

            cg.setBlendMode(.destinationOut)
            let w = g.eyeSize.width * 1.15, h = g.eyeSize.height * 1.15
            for eye in g.eyes {
                if happy {
                    cg.setLineWidth(3.6)
                    cg.move(to: CGPoint(x: eye.x - w / 2 - 0.5, y: eye.y + 1.5))
                    cg.addQuadCurve(to: CGPoint(x: eye.x + w / 2 + 0.5, y: eye.y + 1.5),
                                    control: CGPoint(x: eye.x, y: eye.y - 5))
                    cg.strokePath()
                } else {
                    cg.fillEllipse(in: CGRect(x: eye.x - w / 2, y: eye.y - h / 2, width: w, height: h))
                }
            }
            if dot {
                // Cut a ring around the dot so it reads clearly at menu bar size.
                cg.fillEllipse(in: CGRect(x: 62, y: 8, width: 22, height: 22))
                cg.setBlendMode(.normal)
                cg.fillEllipse(in: CGRect(x: 66, y: 12, width: 14, height: 14))
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
