import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Animated previews for the README, drawn the same way as the screenshots.
/// Invoked with `Fussel --render-gifs <folder>`.
extension PreviewRenderer {
    static func renderGIFs(to folder: String) {
        _ = NSApplication.shared
        isRendering = true
        UserDefaults.standard.set(true, forKey: FirstLaunch.seen)
        let dir = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let saved = UserDefaults.standard.string(forKey: SettingsKey.appearance)
        defer { UserDefaults.standard.set(saved, forKey: SettingsKey.appearance) }

        // A tour: scan, see what was found, look closer, clean.
        UserDefaults.standard.set(AppearanceChoice.system.rawValue, forKey: SettingsKey.appearance)
        let tour = [("scanning", Page.overview), ("ready", .overview), ("ready", .tool(.junk)), ("done", .overview)]
            .compactMap { window($0.0, scheme: .light, page: $0.1) }
        writeGIF(crossfade(tour, hold: 1.8), to: dir.appendingPathComponent("tour.gif"))

        // The looks: Light, Dark and Glass in both.
        var looks: [CGImage] = []
        for (choice, scheme) in [(AppearanceChoice.light, ColorScheme.light), (.dark, .dark), (.glass, .light), (.glass, .dark)] {
            UserDefaults.standard.set(choice.rawValue, forKey: SettingsKey.appearance)
            if let image = window("ready", scheme: scheme, page: .overview) { looks.append(image) }
        }
        writeGIF(crossfade(looks, hold: 1.6), to: dir.appendingPathComponent("styles.gif"))

        // Fussel himself: swinging his curl like while he scans, with a blink.
        let fps = 30.0
        let frames: [(CGImage, Double)] = (0..<Int(2.2 * fps)).compactMap { i in
            let t = Double(i) / fps
            let tile = RoundedRectangle(cornerRadius: 54, style: .continuous).fill(Theme.graphite)
                .overlay(FusselBody(blink: (0.9..<1.0).contains(t), curlTilt: 16 * sin(t * 2 * .pi / 1.1))
                    .frame(width: 184, height: 184))
                .frame(width: 200, height: 200)
                .padding(20)
            let renderer = ImageRenderer(content: tile)
            renderer.scale = 1
            return renderer.cgImage.map { ($0, 1 / fps) }
        }
        writeGIF(frames, to: dir.appendingPathComponent("fussel.gif"))
    }

    /// The window in one state, at its real size.
    private static func window(_ scenario: String, scheme: ColorScheme, page: Page) -> CGImage? {
        let view = StyledRoot { ContentView(page: page) }
            .environment(sampleModel(scenario))
            .environment(\.colorScheme, scheme)
            .frame(width: 960, height: 640)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.cgImage
    }

    /// Holds each image, then fades softly into the next one, and back to the first at the end.
    private static func crossfade(_ images: [CGImage], hold: Double, steps: Int = 6) -> [(CGImage, Double)] {
        var frames: [(CGImage, Double)] = []
        for (i, image) in images.enumerated() {
            frames.append((image, hold))
            let next = images[(i + 1) % images.count]
            for step in 1..<steps {
                if let mix = blend(image, next, Double(step) / Double(steps)) { frames.append((mix, 0.04)) }
            }
        }
        return frames
    }

    private static func blend(_ a: CGImage, _ b: CGImage, _ amount: Double) -> CGImage? {
        let rect = CGRect(x: 0, y: 0, width: a.width, height: a.height)
        guard let ctx = CGContext(data: nil, width: a.width, height: a.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(a, in: rect)
        ctx.setAlpha(amount)
        ctx.draw(b, in: rect)
        return ctx.makeImage()
    }

    private static func writeGIF(_ frames: [(CGImage, Double)], to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
        else { return }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (image, delay) in frames {
            CGImageDestinationAddImage(dest, image, [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay,
            ]] as CFDictionary)
        }
        print(CGImageDestinationFinalize(dest) ? "Rendered \(url.lastPathComponent)" : "Could not write \(url.lastPathComponent)")
    }
}
