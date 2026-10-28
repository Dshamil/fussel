import AppKit

// Draws the installer's side picture in the Fussel identity, light and dark: the app icon, the stacked
// wordmark, the tagline and the storage bar in the five tool colors, at the bottom of the step list.
// The picture is 260 × 418 pt (@2x) and sits bottom left, so everything stays left of the text pane.
// Usage: swift design/installer-background.swift   (writes installer/resources/background*.png)
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

for (name, dark) in [("background", false), ("background-dark", true)] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 520, pixelsHigh: 836, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let left: CGFloat = 44

    // The icon brings its own glass; the transparent margin around the tile is about 10 %.
    logo.draw(in: NSRect(x: left - 22, y: 236, width: 220, height: 220))

    let ink = dark ? color(0xF2F2F2) : color(0x2B2D33)
    let muted = dark ? color(0x98989F) : color(0x6E6E73)
    NSAttributedString(string: "Fussel", attributes: [
        .font: rounded(76, .heavy), .foregroundColor: ink, .kern: -2.6,
    ]).draw(at: NSPoint(x: left - 3, y: 140))
    NSAttributedString(string: "Less fluff, more Mac.", attributes: [
        .font: rounded(25, .bold), .foregroundColor: muted,
    ]).draw(at: NSPoint(x: left, y: 104))

    // The storage bar: one slice per tool, then free space.
    var x = left
    let width: CGFloat = 280, y: CGFloat = 62
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: NSRect(x: left, y: y, width: width, height: 12), xRadius: 6, yRadius: 6).addClip()
    (dark ? color(0x333337) : color(0xE3E3E8)).setFill()
    NSRect(x: left, y: y, width: width, height: 12).fill()
    for (hex, share) in tools {
        color(hex).setFill()
        NSRect(x: x, y: y, width: width * share - 3, height: 12).fill()
        x += width * share
    }
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "installer/resources/\(name).png"))
}
print("Rendered installer/resources/background.png and background-dark.png")
