import SwiftUI
import AppKit

/// Geometry of the Fussel character in a 100×100 design space, the same as the app icon
/// (design/AppIcon.icon at 1024 px, divided by 10.24): a round fluff ball with one bold curl on top.
enum FusselGeometry {
    static let ball = CGPoint(x: 50, y: 54)
    static let radius: CGFloat = 25.4
    /// The curl swings around this point, where it grows out of the ball.
    static let curlBase = CGPoint(x: 51.5, y: 30)
    /// The curl: a loop and a short strand, both starting inside the ball.
    static func curl(_ p: (CGFloat, CGFloat) -> CGPoint) -> (loop: Path, strand: Path) {
        var loop = Path()
        loop.move(to: p(50, 30))
        loop.addQuadCurve(to: p(50, 12.7), control: p(42, 18))
        loop.addQuadCurve(to: p(58.7, 18.7), control: p(58.7, 9.4))
        var strand = Path()
        strand.move(to: p(53.3, 30))
        strand.addQuadCurve(to: p(66.7, 23.3), control: p(60, 22))
        return (loop, strand)
    }
    static let loopWidth: CGFloat = 4.7
    static let strandWidth: CGFloat = 4.0
    /// Small drawings (menu bar, sidebar badge) keep the exact shape but draw the curl a little thinner:
    /// the gap between loop and strand is under 2 % of the drawing and would close up otherwise.
    static let smallWeight: CGFloat = 0.8
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
    /// Eyes looking to the side, in design units (about ±3 looks around without leaving the face).
    var look: CGFloat = 0

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 100
            let g = FusselGeometry.self
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            var curl = ctx
            curl.translateBy(x: g.curlBase.x * s, y: g.curlBase.y * s)
            curl.rotate(by: .degrees(curlTilt))
            curl.translateBy(x: -g.curlBase.x * s, y: -g.curlBase.y * s)
            let weight = s < 0.48 ? g.smallWeight : 1
            let (loop, strand) = g.curl(p)
            curl.stroke(loop, with: .color(color), style: StrokeStyle(lineWidth: g.loopWidth * s * weight, lineCap: .round))
            curl.stroke(strand, with: .color(color), style: StrokeStyle(lineWidth: g.strandWidth * s * weight, lineCap: .round))

            let r = g.radius
            ctx.fill(Path(ellipseIn: CGRect(x: (g.ball.x - r) * s, y: (g.ball.y - r) * s, width: 2 * r * s, height: 2 * r * s)),
                     with: .color(color))

            let w = g.eyeSize.width, h = g.eyeSize.height
            for base in g.eyes {
                let eye = CGPoint(x: base.x + look, y: base.y)
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
            let (loop, strand) = g.curl { CGPoint(x: $0, y: $1) }
            cg.setLineWidth(g.loopWidth * g.smallWeight)
            cg.addPath(loop.cgPath)
            cg.strokePath()
            cg.setLineWidth(g.strandWidth * g.smallWeight)
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
