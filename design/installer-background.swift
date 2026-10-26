import AppKit

// Draws the installer's side picture: the app icon (docs/logo.png) at the bottom left, nothing else.
// Usage: swift design/installer-background.swift   (writes installer/resources/background*.png)
let logo = NSImage(contentsOfFile: "docs/logo.png")!
for name in ["background", "background-dark"] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 520, pixelsHigh: 836, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    logo.draw(in: NSRect(x: 30, y: 40, width: 320, height: 320))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "installer/resources/\(name).png"))
}
print("Rendered installer/resources/background.png and background-dark.png")
