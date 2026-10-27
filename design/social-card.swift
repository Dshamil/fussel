import AppKit

// Draws the picture that shows up when someone shares the website link: the app icon, the wordmark,
// the tagline and the storage bar in the five tool colors, on the site's light grey. 1200 × 630.
// Usage: swift design/social-card.swift   (writes docs/social.png)
let logo = NSImage(contentsOfFile: "docs/logo.png")!
let tools: [(UInt32, CGFloat)] = [(0x3FAE7C, 0.22), (0xE5484D, 0.10), (0x8B78EC, 0.30), (0xE5A33A, 0.14), (0x3D8BE0, 0.08)]

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 630, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
color(0xF3F3F5).setFill()
NSRect(x: 0, y: 0, width: 1200, height: 630).fill()

let left: CGFloat = 96
logo.draw(in: NSRect(x: left - 30, y: 330, width: 260, height: 260))
NSAttributedString(string: "Fussel", attributes: [
    .font: rounded(132, .heavy), .foregroundColor: color(0x2B2D33), .kern: -4.5,
]).draw(at: NSPoint(x: left - 6, y: 172))
NSAttributedString(string: "Free up your Mac, calmly.", attributes: [
    .font: rounded(44, .bold), .foregroundColor: color(0x6E6E73),
]).draw(at: NSPoint(x: left, y: 116))

// The storage bar: one slice per tool, then free space.
let bar = NSRect(x: left, y: 64, width: 1200 - 2 * left, height: 22)
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: bar, xRadius: 11, yRadius: 11).addClip()
color(0xE3E3E8).setFill(); bar.fill()
var x = bar.minX
for (hex, share) in tools {
    color(hex).setFill()
    NSRect(x: x, y: bar.minY, width: bar.width * share, height: bar.height).fill()
    x += bar.width * share
}
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/social.png"))
