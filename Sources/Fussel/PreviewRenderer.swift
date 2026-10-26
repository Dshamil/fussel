import SwiftUI
import AppKit

/// Renders the main screen in every style and state to PNG files, so the look can be checked
/// without running the app by hand. Invoked with `Fussel --render-previews <folder>`.
@MainActor
enum PreviewRenderer {
    /// True while screenshots are drawn: some AppKit-backed views are swapped for plain ones.
    static var isRendering = false

    static func renderAll(to folder: String) {
        _ = NSApplication.shared
        Gaze.enabled = false
        isRendering = true
        UserDefaults.standard.set(true, forKey: FirstLaunch.seen)
        let dir = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let scenarios = ["idle", "scanning", "ready", "done", "stuffed", "pending"]
        for scheme in [ColorScheme.light, .dark] {
            for scenario in scenarios {
                render(scenario, scheme: scheme, page: .overview, to: dir, name: "\(name(scheme))-\(scenario)")
            }
            for (scenario, module) in [("ready", Module.junk), ("ready", .large), ("idle", .tidy)] {
                render(scenario, scheme: scheme, page: .tool(module), to: dir,
                       name: "\(name(scheme))-\(module.rawValue)-\(scenario)")
            }
        }
    }

    private static func name(_ scheme: ColorScheme) -> String { scheme == .dark ? "dark" : "light" }

    private static func render(_ scenario: String, scheme: ColorScheme, page: Page, to dir: URL, name: String) {
        let model = sampleModel(scenario)
        let view = StyledRoot(costumeOverride: Costume.none) {
            ContentView(page: page)
        }
        .environment(model)
        .environment(\.colorScheme, scheme)
        .frame(width: 960, height: 640)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            print("Could not render \(name)")
            return
        }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
        print("Rendered \(name).png")
    }

    private static func sampleModel(_ scenario: String) -> AppModel {
        let model = AppModel()
        model.hasFullDiskAccess = scenario != "idle"
        let home = FileManager.default.homeDirectoryForCurrentUser
        model.monitor.sample = SystemSample(
            diskName: "Macintosh HD", diskFree: 135_870_000_000, diskTotal: 494_000_000_000,
            memUsed: 14_200_000_000, memTotal: 16_000_000_000,
            battery: BatteryInfo(percent: 64, isCharging: false, isPluggedIn: false, minutesLeft: 214, health: "Good"),
            cpu: 0.12, temperature: 36, downBytesPerSecond: 3_200, upBytesPerSecond: 0
        )
        model.monitor.downHistory = (0..<30).map { Double(($0 * 37) % 11) * 900 }
        model.monitor.hasSample = true
        switch scenario {
        case "stuffed":
            model.monitor.sample.diskFree = 21_000_000_000
        case "hot":
            model.monitor.sample.temperature = 93
            model.monitor.sample.cpu = 0.97
        case "sleepy":
            model.monitor.sample.battery = BatteryInfo(percent: 8, isCharging: false, isPluggedIn: false, minutesLeft: 12)
        case "pending":
            model.pendingFluff = 2_400_000_000
        case "santa":
            model.stage = .done(freed: 1_200_000_000, failures: [])
        case "scanning":
            model.junk.phase = .results
            model.large.phase = .scanning
            model.tidy.phase = .scanning
            model.stage = .scanning
        case "tutorial":
            model.showTutorial = true
        case "ready":
            model.junk.items = [
                CleanupItem(url: home.appendingPathComponent("Library/Caches/com.example.browser"), name: "Browser",
                            group: "App Caches", size: 1_840_000_000, preselected: true),
                CleanupItem(url: home.appendingPathComponent("Library/Logs/Example"), name: "Example",
                            group: "Logs", size: 320_000_000, preselected: true),
            ]
            model.junk.selected = Set(model.junk.items.map(\.url))
            model.junk.phase = .results
            model.large.items = [
                CleanupItem(url: home.appendingPathComponent("Movies/Holiday.mov"), name: "Holiday.mov",
                            group: "Large Files", size: 4_200_000_000),
            ]
            model.large.phase = .results
            model.tidy.phase = .results
            model.stage = .ready
        case "done":
            model.junk.phase = .done(freed: 2_160_000_000, failures: [])
            model.large.phase = .results
            model.large.items = [
                CleanupItem(url: home.appendingPathComponent("Movies/Holiday.mov"), name: "Holiday.mov",
                            group: "Large Files", size: 4_200_000_000),
            ]
            model.tidy.phase = .done(freed: 0, failures: [])
            model.stage = .done(freed: 2_160_000_000, failures: [])
        default:
            break
        }
        return model
    }
}
