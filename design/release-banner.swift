import AppKit

// Draws the banner at the top of a big release's notes on GitHub: Fussel's icon on graphite, the
// version, the motto and the storage bar in the five tool colours. 2560 × 1080 (shown at 1280 × 540).
// Usage: swift design/release-banner.swift 1.0   (writes docs/release-<version>.png)
let version = CommandLine.arguments.dropFirst().first ?? "1.0"
let logo = NSImage(contentsOfFile: "docs/logo.png")!
let tools: [(UInt32, CGFloat)] = [(0x3FAE7C, 0.22), (0xE5484D, 0.10), (0x8B78EC, 0.30), (0xE5A33A, 0.14), (0x3D8BE0, 0.08)]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

let W: CGFloat = 2560, H: CGFloat = 1080
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Graphite, a touch lighter towards the top left where the icon sits.
NSGradient(colors: [color(0x34363D), color(0x1C1D21)])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -35)

// The icon brings its own glass and shadow.
let iconSide: CGFloat = 620
logo.draw(in: NSRect(x: 150, y: (H - iconSide) / 2 + 10, width: iconSide, height: iconSide))

let left: CGFloat = 860
NSAttributedString(string: "Fussel \(version)", attributes: [
    .font: rounded(230, .heavy), .foregroundColor: color(0xF5F5F7), .kern: -8,
]).draw(at: NSPoint(x: left - 8, y: 520))
NSAttributedString(string: "Less fluff, more Mac.", attributes: [
    .font: rounded(92, .bold), .foregroundColor: color(0xF5F5F7, 0.62),
]).draw(at: NSPoint(x: left, y: 400))

// The storage bar: one slice per tool, then free space.
let bar = NSRect(x: left, y: 300, width: W - left - 200, height: 40)
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: bar, xRadius: 20, yRadius: 20).addClip()
color(0xFFFFFF, 0.12).setFill(); bar.fill()
var x = bar.minX
for (hex, share) in tools {
    color(hex).setFill()
    NSRect(x: x, y: bar.minY, width: bar.width * share, height: bar.height).fill()
    x += bar.width * share
}
NSGraphicsContext.restoreGraphicsState()

NSAttributedString(string: "Free and open source  ·  for macOS 14 and later", attributes: [
    .font: rounded(52, .semibold), .foregroundColor: color(0xF5F5F7, 0.45),
]).draw(at: NSPoint(x: left, y: 190))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "docs/release-\(version).png"))
print("Rendered docs/release-\(version).png")
