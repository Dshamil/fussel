import SwiftUI
import AppKit

/// Renders the main screen in every style and state to PNG files, so the look can be checked
/// without running the app by hand. Invoked with `Fussel --render-previews <folder>`.
@MainActor
enum PreviewRenderer {
    static func renderAll(to folder: String) {
        _ = NSApplication.shared
        Gaze.enabled = false
        UserDefaults.standard.set(true, forKey: TutorialKey.seen)
        let dir = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        renderCloset(to: dir)
        let styles: [AppStyle] = [.light, .dark, .coral]
        let scenarios = ["idle", "scanning", "ready", "done", "tutorial", "stuffed", "hot", "sleepy", "pending", "santa"]
        for style in styles {
            for scenario in scenarios {
                let model = sampleModel(scenario)
                let view = StyledRoot(override: style, costumeOverride: scenario == "santa" ? .santa : Costume.none) {
                    ContentView()
                }
                .environment(model)
                .environment(\.colorScheme, style == .dark ? .dark : .light)
                .frame(width: 760, height: 830)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    print("Could not render \(style.rawValue)-\(scenario)")
                    continue
                }
                let file = dir.appendingPathComponent("\(style.rawValue)-\(scenario).png")
                try? png.write(to: file)
                print("Rendered \(file.lastPathComponent)")
            }
        }
    }

    /// The closet tabs, rendered on their own (sheets don't show up in ImageRenderer).
    static func renderCloset(to dir: URL) {
        for (name, tab) in [("closet-costumes", ClosetView.Tab.costumes), ("closet-icons", .icon), ("closet-badges", .badges)] {
            let view = StyledRoot(override: .light, costumeOverride: Costume.none) {
                ClosetView(tab: tab, scrolls: false)
            }
            .environment(\.colorScheme, .light)
            .frame(width: 720, height: 460)
            .background(Color.white)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
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
