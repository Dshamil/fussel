import AppKit

// Draws an app's icon as the Mac shows it (with Liquid Glass) into a 1024 px PNG with a clear background.
// Usage: swift design/snap-icon.swift <App.app> <out.png>
let app = URL(fileURLWithPath: CommandLine.arguments[1]).path, out = CommandLine.arguments[2]
let icon = NSWorkspace.shared.icon(forFile: app)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
icon.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
