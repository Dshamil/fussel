import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import AVFoundation

/// Animated previews, drawn the same way as the screenshots: GIFs for the README (GitHub doesn't play
/// videos there) and sharp MP4 videos at double resolution for the website, with a still image each
/// for before they start. Invoked with `Fussel --render-gifs <folder>`.
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
        let tourSteps = [("scanning", Page.overview), ("ready", .overview), ("ready", .tool(.junk)), ("done", .overview)]
        let tour = tourSteps.compactMap { window($0.0, scheme: .light, page: $0.1) }
        writeGIF(crossfade(tour, hold: 1.8), to: dir.appendingPathComponent("tour.gif"))
        let sharpTour = tourSteps.compactMap { window($0.0, scheme: .light, page: $0.1, scale: 2) }
        writeVideo(crossfade(sharpTour, hold: 1.8, steps: 12, step: 1.0 / 30), to: dir.appendingPathComponent("tour.mp4"))

        // The looks: Light, Dark, Glass in both, and Oreo.
        var looks: [CGImage] = []
        var sharpLooks: [CGImage] = []
        for (choice, scheme) in [(AppearanceChoice.light, ColorScheme.light), (.dark, .dark), (.glass, .light), (.glass, .dark), (.oreo, .dark)] {
            UserDefaults.standard.set(choice.rawValue, forKey: SettingsKey.appearance)
            if let image = window("ready", scheme: scheme, page: .overview) { looks.append(image) }
            if let image = window("ready", scheme: scheme, page: .overview, scale: 2) { sharpLooks.append(image) }
        }
        writeGIF(crossfade(looks, hold: 1.6), to: dir.appendingPathComponent("styles.gif"))
        writeVideo(crossfade(sharpLooks, hold: 1.6, steps: 12, step: 1.0 / 30), to: dir.appendingPathComponent("styles.mp4"))

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

    /// The window in one state.
    private static func window(_ scenario: String, scheme: ColorScheme, page: Page, scale: CGFloat = 1) -> CGImage? {
        let view = StyledRoot { ContentView(page: page) }
            .environment(sampleModel(scenario))
            .environment(\.colorScheme, scheme)
            // A little taller than the default window, so the overview fits down to its last card.
            .frame(width: 960, height: 740)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    /// Holds each image, then fades softly into the next one, and back to the first at the end.
    private static func crossfade(_ images: [CGImage], hold: Double, steps: Int = 6, step: Double = 0.04) -> [(CGImage, Double)] {
        var frames: [(CGImage, Double)] = []
        for (i, image) in images.enumerated() {
            frames.append((image, hold))
            let next = images[(i + 1) % images.count]
            for i in 1..<steps {
                if let mix = blend(image, next, Double(i) / Double(steps)) { frames.append((mix, step)) }
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

    /// An H.264 video: each image shown for its time, looping is up to the page that plays it.
    /// Also writes the first image as a JPEG next to it, shown until the video starts.
    private static func writeVideo(_ frames: [(CGImage, Double)], to url: URL) {
        guard let first = frames.first?.0 else { return }
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: first.width, AVVideoHeightKey: first.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000,
                                              AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: first.width, kCVPixelBufferHeightKey as String: first.height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var time = 0.0
        for (image, duration) in frames {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
            if let buffer = pixelBuffer(image) {
                adaptor.append(buffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600))
            }
            time += duration
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: time, preferredTimescale: 600))
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        print(writer.status == .completed ? "Rendered \(url.lastPathComponent)" : "Could not write \(url.lastPathComponent)")

        let poster = url.deletingPathExtension().appendingPathExtension("jpg")
        if let dest = CGImageDestinationCreateWithURL(poster as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, first, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
            CGImageDestinationFinalize(dest)
        }
    }

    private static func pixelBuffer(_ image: CGImage) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32ARGB, nil, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }
}
