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
    /// Disk almost full: puffed up and round-cheeked.
    case stuffed
    /// CPU running hot: sweating and a bit flushed.
    case hot
    /// Battery almost empty: dozing off.
    case sleepy
}

/// The fluff body and its face, drawn in a square frame.
/// Equatable, so SwiftUI only redraws it when the face changes, not on every bobbing frame.
struct FusselBody: View, Equatable {
    var mood: MascotMood
    var color: Color = .white
    var blink = false
    /// Where the eyes look, in design units (about ±1.4).
    var look: CGSize = .zero
    var surprised = false
    var cheeks = false
    var costume: Costume = .none
    /// 0…1, how close the pointer is; the pupils widen a little.
    var curious: CGFloat = 0

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

            drawFace()
            CostumeArt.draw(costume, in: ctx, scale: s)

            func drawFace() {
            let ink = Theme.ink
            if cheeks || mood == .happy || mood == .stuffed || mood == .hot {
                let r: CGFloat = mood == .stuffed ? 3.4 : 2.4
                let tint = mood == .hot ? Color(hex: 0xF27A6B) : Color(hex: 0xF6A795)
                for cx in [40.5, 59.5] as [CGFloat] {
                    ctx.fill(Path(ellipseIn: circle(cx, 56.5, r)), with: .color(tint.opacity(0.8)))
                }
            }

            if mood == .hot {
                // Two little sweat drops.
                for (dx, dy, k) in [(67.0, 37.0, 1.0), (31.5, 41.0, 0.8)] as [(CGFloat, CGFloat, CGFloat)] {
                    var drop = Path()
                    drop.move(to: CGPoint(x: dx * s, y: (dy - 4 * k) * s))
                    drop.addQuadCurve(to: CGPoint(x: dx * s, y: (dy + 2.2 * k) * s),
                                      control: CGPoint(x: (dx + 3.4 * k) * s, y: (dy + 1.5 * k) * s))
                    drop.addQuadCurve(to: CGPoint(x: dx * s, y: (dy - 4 * k) * s),
                                      control: CGPoint(x: (dx - 3.4 * k) * s, y: (dy + 1.5 * k) * s))
                    ctx.fill(drop, with: .color(Color(hex: 0x7CC4F2)))
                }
            }

            if mood == .sleepy && !surprised {
                // Closed, peaceful eyes.
                for (ex, ey) in FusselGeometry.eyes {
                    var lid = Path()
                    lid.move(to: CGPoint(x: (ex - 2.6) * s, y: (ey + 0.5) * s))
                    lid.addQuadCurve(to: CGPoint(x: (ex + 2.6) * s, y: (ey + 0.5) * s),
                                     control: CGPoint(x: ex * s, y: (ey + 3.2) * s))
                    ctx.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round))
                }
                return
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

            let r = surprised ? 3.3 : (mood == .stuffed ? 2.9 : FusselGeometry.eyeRadius) + 0.45 * curious
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
}

/// Fussel floating above its shadow. Bobs with a little squash and stretch, blinks now and then,
/// follows the pointer with its eyes and does a flip when clicked.
struct FusselMascot: View {
    var mood: MascotMood = .idle
    var size: CGFloat = 140
    var showShadow = true
    var color: Color = .white
    /// Eyes (and a little lean of the whole body) follow the pointer, anywhere on screen.
    var followsPointer = false
    var interactive = false
    var onPoke: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationsPaused) private var paused
    @Environment(\.costume) private var costume
    @Environment(\.controlActiveState) private var activeState
    @State private var blink = false
    @State private var pokeDate = Date.distantPast
    @State private var pokeCount = 0
    @State private var gaze = Gaze()

    var body: some View {
        TimelineView(.animation(minimumInterval: AnimationBudget.interval(busy: mood == .busy, active: activeState),
                                paused: reduceMotion || paused || AnimationBudget.still)) { timeline in
            let m = motion(at: timeline.date)
            let g = followsPointer ? gaze.update(at: timeline.date.timeIntervalSinceReferenceDate, size: size) : Gaze.Look()
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
                    look: g.eyes,
                    surprised: m.surprised,
                    cheeks: m.surprised || g.curious > 0.85,
                    costume: costume,
                    curious: g.curious
                )
                .equatable()
                .frame(width: size, height: size)
                .scaleEffect(x: m.scaleX, y: m.scaleY, anchor: .bottom)
                .rotationEffect(.degrees(m.tilt + m.spin + g.lean))
                .offset(x: size * (0.04 + g.lean * 0.004), y: -size * 0.06 - m.height * size)

                if mood == .sleepy && !reduceMotion {
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    ForEach(0..<3, id: \.self) { k in
                        let p = (t * 0.35 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                        Text("z")
                            .font(.system(size: size * (0.09 + 0.05 * p), weight: .heavy, design: .rounded))
                            .foregroundStyle(color.opacity(1 - p))
                            .offset(x: size * (0.22 + 0.12 * p), y: -size * (0.2 + 0.25 * p))
                    }
                }
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .background { if followsPointer && Gaze.enabled { PointerAnchor(gaze: gaze) } }
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
            case .stuffed:
                let wave = sin(t * 1.6)
                m.height = 0.012 + 0.012 * CGFloat(wave)
                m.tilt = -6 + 2 * sin(t * 0.8)
                m.scaleX = 1.12 + 0.02 * CGFloat(max(0, -wave))
                m.scaleY = 1.06 - 0.02 * CGFloat(max(0, -wave))
            case .hot:
                let wave = sin(t * 2.6)
                m.height = 0.02 + 0.02 * CGFloat(wave)
                // A little shiver every couple of seconds.
                let shiver = (t.truncatingRemainder(dividingBy: 2.4)) < 0.35 ? sin(t * 60) * 3 : 0
                m.tilt = -10 + shiver
            case .sleepy:
                let wave = sin(t * 1.1)
                m.height = 0.008 + 0.008 * CGFloat(wave)
                m.tilt = -16 + 3 * sin(t * 0.55)
                m.scaleX = 1 + 0.025 * CGFloat(wave)
                m.scaleY = 1 - 0.025 * CGFloat(wave)
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

/// Where Fussel looks. Reads the pointer straight from the window server on every animation frame
/// (no hover events, so nothing else on screen re-renders) and eases the eyes towards it.
@MainActor
final class Gaze {
    struct Look {
        /// Eye offset in design units.
        var eyes: CGSize = .zero
        /// Degrees the body leans towards the pointer.
        var lean: Double = 0
        /// 0…1, pointer close to Fussel.
        var curious: CGFloat = 0
    }

    weak var anchor: NSView?
    /// Screenshot rendering can't draw AppKit views, so the anchor is left out there.
    static var enabled = true
    private var current = Look()
    private var lastTime: Double?
    private var lastMouse = CGPoint.zero
    private var lastMove = 0.0

    func update(at t: Double, size: CGFloat) -> Look {
        let target = targetLook(at: t, size: size)
        let dt = min(0.1, max(0, t - (lastTime ?? t)))
        if lastTime == nil {
            current = target
        } else {
            // Exponential easing: eyes are quick, the body lean lags behind a bit.
            let eyeK = 1 - exp(-dt * 16)
            let bodyK = 1 - exp(-dt * 5)
            current.eyes.width += (target.eyes.width - current.eyes.width) * eyeK
            current.eyes.height += (target.eyes.height - current.eyes.height) * eyeK
            current.curious += (target.curious - current.curious) * CGFloat(bodyK)
            current.lean += (target.lean - current.lean) * bodyK
        }
        lastTime = t
        return current
    }

    private func targetLook(at t: Double, size: CGFloat) -> Look {
        guard let view = anchor, let window = view.window, window.isVisible else { return Look() }
        let mouse = NSEvent.mouseLocation
        if mouse != lastMouse {
            lastMouse = mouse
            lastMove = t
        }
        // Pointer resting for a while: glance around on its own.
        if t - lastMove > 5 {
            let slot = floor(t / 2.2)
            let a = sin(slot * 12.9898) * 43758.5453
            let angle = (a - floor(a)) * 2 * .pi
            let wander = (slot.truncatingRemainder(dividingBy: 3) == 0) ? 0 : 0.8
            return Look(eyes: CGSize(width: cos(angle) * 1.4 * wander, height: sin(angle) * 0.8 * wander))
        }
        let local = view.convert(window.convertPoint(fromScreen: mouse), from: nil)
        let b = view.bounds
        let dx = local.x - b.midX
        let dy = view.isFlipped ? local.y - b.midY : b.midY - local.y
        let distance = max(1, hypot(dx, dy))
        // Full reach from about one Fussel away; closer in, the eyes converge on the pointer.
        let reach = min(1, distance / (size * 0.9))
        let ux = dx / distance, uy = dy / distance
        return Look(
            eyes: CGSize(width: ux * 1.7 * reach, height: uy * 1.3 * reach),
            lean: Double(max(-1, min(1, dx / (size * 3)))) * 6,
            curious: max(0, 1 - distance / (size * 0.75))
        )
    }
}

/// An invisible view in Fussel's frame, so `Gaze` knows where Fussel is on screen.
private struct PointerAnchor: NSViewRepresentable {
    let gaze: Gaze

    /// Never takes clicks, so poking Fussel still works.
    final class Anchor: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSView {
        let view = Anchor()
        gaze.anchor = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        gaze.anchor = view
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
    static let image: NSImage = make(dot: false)
    /// Same icon with a little dot: Fussel found something while you were away.
    static let imageWithDot: NSImage = make(dot: true)
    /// Closed, happy eyes for a moment after cleaning.
    static let happy: NSImage = make(dot: false, happy: true)
    /// Wiggle frames while scanning.
    static let wiggle: [NSImage] = [-14, -8, 0, 8, 14, 8, 0, -8].map { make(dot: false, rotation: $0) }

    private static func make(dot: Bool, rotation: CGFloat = 0, happy: Bool = false) -> NSImage {
        let side: CGFloat = 18
        let img = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            if rotation != 0 {
                let transform = NSAffineTransform()
                transform.translateX(by: rect.midX, yBy: rect.midY)
                transform.rotate(byDegrees: rotation)
                transform.translateX(by: -rect.midX, yBy: -rect.midY)
                transform.concat()
            }
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
            if happy {
                for (ex, ey) in FusselGeometry.eyes {
                    let arc = NSBezierPath()
                    arc.move(to: NSPoint(x: ox + (ex - 3.2) * s, y: oy + (ey + 1.5) * s))
                    arc.curve(to: NSPoint(x: ox + (ex + 3.2) * s, y: oy + (ey + 1.5) * s),
                              controlPoint1: NSPoint(x: ox + (ex - 2) * s, y: oy + (ey - 3.5) * s),
                              controlPoint2: NSPoint(x: ox + (ex + 2) * s, y: oy + (ey - 3.5) * s))
                    arc.lineWidth = 2.2 * s
                    arc.lineCapStyle = .round
                    arc.stroke()
                }
            } else {
                for (ex, ey) in FusselGeometry.eyes {
                    NSBezierPath(ovalIn: oval(ex, ey, 3.1)).fill()
                }
            }
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            if dot {
                // Cut a ring around the dot so it reads clearly at menu bar size.
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                NSBezierPath(ovalIn: NSRect(x: rect.maxX - 7.5, y: rect.minY - 0.5, width: 8, height: 8)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSBezierPath(ovalIn: NSRect(x: rect.maxX - 6, y: rect.minY + 1, width: 5, height: 5)).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
