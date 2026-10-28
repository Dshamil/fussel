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
        isRendering = true
        UserDefaults.standard.set(true, forKey: FirstLaunch.seen)
        let dir = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        renderMenuBar(to: dir)
        let scenarios = ["idle", "scanning", "ready", "done", "stuffed", "pending", "tutorial", "permissions", "updated"]
        for scheme in [ColorScheme.light, .dark] {
            for scenario in scenarios {
                render(scenario, scheme: scheme, page: .overview, to: dir, name: "\(name(scheme))-\(scenario)")
            }
            for (scenario, module) in [("ready", Module.junk), ("ready", .large), ("idle", .tidy), ("ready", .uninstaller)] {
                render(scenario, scheme: scheme, page: .tool(module), to: dir,
                       name: "\(name(scheme))-\(module.rawValue)-\(scenario)")
            }
        }
        // The Glass style, over a stand-in desktop.
        let saved = UserDefaults.standard.string(forKey: SettingsKey.appearance)
        UserDefaults.standard.set(AppearanceChoice.glass.rawValue, forKey: SettingsKey.appearance)
        for scheme in [ColorScheme.light, .dark] {
            render("ready", scheme: scheme, page: .overview, to: dir, name: "glass-\(name(scheme))-ready")
            render("ready", scheme: scheme, page: .tool(.junk), to: dir, name: "glass-\(name(scheme))-junk-ready")
        }
        UserDefaults.standard.set(AppearanceChoice.oreo.rawValue, forKey: SettingsKey.appearance)
        render("ready", scheme: .dark, page: .overview, to: dir, name: "oreo-ready")
        render("ready", scheme: .dark, page: .tool(.junk), to: dir, name: "oreo-junk-ready")
        render("ready", scheme: .dark, page: .tool(.uninstaller), to: dir, name: "oreo-uninstaller-ready")
        UserDefaults.standard.set(AppearanceChoice.glass.rawValue, forKey: SettingsKey.appearance)
        render("ready", scheme: .light, page: .tool(.uninstaller), to: dir, name: "glass-light-uninstaller-ready")
        UserDefaults.standard.set(saved, forKey: SettingsKey.appearance)
    }

    private static func name(_ scheme: ColorScheme) -> String { scheme == .dark ? "dark" : "light" }

    /// The menu bar icons, eight times their size: plain, with the dot, happy, and the busy frames.
    private static func renderMenuBar(to dir: URL) {
        let icons = [MenuBarIcon.image, MenuBarIcon.imageWithDot, MenuBarIcon.happy, MenuBarIcon.asleep] + MenuBarIcon.busy
        let cell: CGFloat = 18 * 8, pad: CGFloat = 16
        let strip = NSImage(size: NSSize(width: (cell + pad) * CGFloat(icons.count) + pad, height: cell + 2 * pad))
        strip.lockFocus()
        NSColor(white: 0.93, alpha: 1).setFill()
        NSRect(origin: .zero, size: strip.size).fill()
        for (i, icon) in icons.enumerated() {
            icon.draw(in: NSRect(x: pad + CGFloat(i) * (cell + pad), y: pad, width: cell, height: cell))
        }
        strip.unlockFocus()
        if let tiff = strip.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("menubar.png"))
        }
    }

    private static func render(_ scenario: String, scheme: ColorScheme, page: Page, to dir: URL, name: String) {
        let model = sampleModel(scenario)
        let view = StyledRoot {
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

    /// Made-up clean-ups for "Recent clean-ups" in screenshots.
    static let sampleRecords: [CleanRecord] = [(Int64(2_160_000_000), 1800.0, "Smart Clean"), (840_000_000, 2 * 86_400.0, "System Junk"),
                                               (1_350_000_000, 6 * 86_400.0, "Trash & Downloads")].map { freed, ago, source in
        let item = TrashedItem(name: "Example", original: URL(fileURLWithPath: "/tmp/example"),
                               trashed: URL(fileURLWithPath: "/tmp/example"), size: freed)
        return CleanRecord(date: Date().addingTimeInterval(-ago), source: source, freed: freed, itemCount: 12, trashed: [item])
    }

    static func sampleModel(_ scenario: String) -> AppModel {
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
        model.monitor.diskTotal = model.monitor.sample.diskTotal
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
        case "permissions":
            model.showPermissions = true
        case "updated":
            model.justUpdatedTo = "0.9.9"
            model.hasFullDiskAccess = false
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
            model.uninstaller.apps = ["Calculator", "Calendar", "Chess", "Clock", "Maps", "Notes", "Photo Booth", "Stocks"].map {
                InstalledApp(url: URL(fileURLWithPath: "/System/Applications/\($0).app"), name: $0, bundleID: "")
            }
            model.uninstaller.selectedApp = model.uninstaller.apps[3]
            model.folders = [("Library", 96_400_000_000), ("Pictures", 61_200_000_000), ("Applications", 38_900_000_000),
                             ("Movies", 24_700_000_000), ("Downloads", 9_300_000_000)].map {
                FolderSize(url: home.appendingPathComponent($0.0), name: $0.0, bytes: $0.1)
            }
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
