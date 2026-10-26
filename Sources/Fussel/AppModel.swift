import SwiftUI
import Observation

@Observable
@MainActor
final class AppModel {
    var hasFullDiskAccess = Permissions.hasFullDiskAccess
    let junk = ModuleModel(module: .junk)
    let large = ModuleModel(module: .large)
    let tidy = ModuleModel(module: .tidy)
    let uninstaller = UninstallerModel()
    let monitor = SystemMonitor()
    let appUpdates = AppUpdatesModel()
    let updater = FusselUpdater()
    /// Shows the onboarding tutorial over the main window.
    var showTutorial = false
    /// Shows the permissions screen over the main window.
    var showPermissions = false
    /// Set once after Fussel was updated, to show which version is now running.
    var justUpdatedTo: String?
    /// On the first start the permissions screen follows the tour, even if the tour is skipped.
    var permissionsAfterTour = false
    /// The biggest folders, largest first, for "Where your space goes".
    var folders: [FolderSize] = []
    private var measuringFolders = false
    private var foldersMeasured: Date?

    /// Measures the big folders in the background. Needs Full Disk Access, or macOS would ask
    /// about every protected folder one by one. Counting every file takes a while (half a minute on a
    /// full Mac), so it happens at most once an hour, unless a clean-up just changed things (`force`).
    func measureFolders(force: Bool = false) async {
        guard hasFullDiskAccess, !measuringFolders, !PreviewRenderer.isRendering else { return }
        if !force, let last = foldersMeasured, Date().timeIntervalSince(last) < 3600 { return }
        measuringFolders = true
        folders = await FolderSizes.measure()
        foldersMeasured = Date()
        measuringFolders = false
    }

    func model(for module: Module) -> ModuleModel {
        switch module {
        case .junk, .uninstaller, .updates: return junk
        case .large: return large
        case .tidy: return tidy
        }
    }

    func refreshAccess() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess
    }

    // MARK: One-screen flow

    enum Stage: Equatable {
        case idle, scanning, ready, cleaning
        case done(freed: Int64, failures: [String])
    }

    var stage: Stage = .idle
    /// False while the window is closed, minimised or fully covered: all animations stop.
    var windowVisible = true

    var scannable: [ModuleModel] { [junk, large, tidy] }
    private var withResults: [ModuleModel] { scannable.filter { $0.phase == .results } }

    var foundTotal: Int64 { withResults.reduce(0) { $0 + $1.totalSize } }
    var selectedTotal: Int64 { withResults.reduce(0) { $0 + $1.selectedSize } }
    var selectionIncludesPermanent: Bool { withResults.contains { $0.selectionIncludesPermanent } }

    var mood: MascotMood {
        switch stage {
        case .scanning, .cleaning: return .busy
        case .done: return .happy
        default: return healthMood
        }
    }

    /// How the Mac is doing right now, shown on Fussel's face when nothing else is going on.
    var healthMood: MascotMood {
        let s = monitor.sample
        guard monitor.hasSample else { return .idle }
        if (s.temperature ?? 0) >= 85 || monitor.thermal == .serious || monitor.thermal == .critical {
            return .hot
        }
        if let battery = s.battery, battery.percent <= 15, !battery.isPluggedIn {
            return .sleepy
        }
        if s.diskTotal > 0, Double(s.diskFree) / Double(s.diskTotal) < 0.1 {
            return .stuffed
        }
        return .idle
    }

    /// Scans System Junk, Large & Old Files and Trash & Downloads at the same time.
    func smartScan() async {
        ScanProgress.shared.reset()
        UserDefaults.standard.set(Date(), forKey: FluffWatcher.lastScanKey)
        pendingFluff = 0
        stage = .scanning
        let started = Date()
        let options = ScanOptions.current
        async let a: Void = junk.scan(options: options)
        async let b: Void = large.scan(options: options)
        async let c: Void = tidy.scan(options: options)
        _ = await (a, b, c)
        // Give the scan show a moment even on a very fast Mac.
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < 3.2 {
            try? await Task.sleep(for: .seconds(3.2 - elapsed))
        }
        stage = .ready
        Task { await measureFolders() }
    }

    /// How many of the three scans have finished, for the progress chips.
    func isFinished(_ module: Module) -> Bool {
        let phase = model(for: module).phase
        return phase != .scanning && phase != .idle
    }

    /// Cleans whatever is selected across all modules.
    func cleanAll() async {
        stage = .cleaning
        var total = CleanResult()
        var count = 0
        for module in withResults where !module.selected.isEmpty {
            count += module.selected.count
            total.merge(await module.clean(record: false))
        }
        lastRecord = CleanHistory.shared.record(total, source: "Smart Clean", itemCount: count)
        monitor.refreshDisk()
        stage = .done(freed: total.freed, failures: total.failures)
        Task { await measureFolders(force: true) }
    }

    /// The clean-up that the hero's Undo button would take back.
    var lastRecord: CleanRecord?
    /// Fluff found by the weekly background check, shown as a dot on the menu bar icon.
    var pendingFluff: Int64 = 0

    /// Puts a clean-up back. Undoing the latest clean-up makes what's on screen outdated, so that starts
    /// fresh; putting back an older one leaves the current scan results as they are.
    func undo(_ record: CleanRecord) async -> (restored: Int, failed: [String]) {
        let latest = lastRecord?.id == record.id || scannable.contains { $0.lastRecord?.id == record.id }
        let outcome = await CleanHistory.shared.undo(record)
        guard outcome.restored > 0 else {
            undoMessage = "Hmm, I couldn't put anything back. Was the Trash emptied?"
            return outcome
        }
        monitor.refreshDisk()
        if latest {
            lastRecord = nil
            for module in scannable { module.reset() }
            stage = .idle
        }
        undoMessage = outcome.failed.isEmpty ? "Phew, everything's back!" : "Put back \(outcome.restored) item(s)."
        return outcome
    }

    /// One-off message for Fussel's speech bubble after an undo.
    var undoMessage: String?
}

/// Scan → review → clean flow shared by System Junk, Large & Old Files and Trash & Downloads.
@Observable
@MainActor
final class ModuleModel {
    enum Phase: Equatable {
        case idle, scanning, results, cleaning
        case done(freed: Int64, failures: [String])
    }

    let module: Module
    var phase: Phase = .idle
    var items: [CleanupItem] = []
    var selected: Set<URL> = []
    /// This tool's last clean-up, for the Undo button on its done screen.
    var lastRecord: CleanRecord?

    init(module: Module) {
        self.module = module
    }

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedItems: [CleanupItem] { items.filter { selected.contains($0.url) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var selectionIncludesPermanent: Bool { selectedItems.contains { $0.permanent } }

    var groups: [String] {
        var order: [String] = []
        for item in items where !order.contains(item.group) { order.append(item.group) }
        return order
    }

    func items(in group: String) -> [CleanupItem] { items.filter { $0.group == group } }

    func isSelected(_ item: CleanupItem) -> Bool { selected.contains(item.url) }

    func setSelected(_ item: CleanupItem, _ on: Bool) {
        if on { selected.insert(item.url) } else { selected.remove(item.url) }
    }

    func setGroup(_ group: String, selected on: Bool) {
        for item in items(in: group) { setSelected(item, on) }
    }

    func isGroupFullySelected(_ group: String) -> Bool {
        items(in: group).allSatisfy { selected.contains($0.url) }
    }

    func scan(options: ScanOptions) async {
        phase = .scanning
        let module = self.module
        let found = await Task.detached(priority: .userInitiated) {
            Scanner.scan(module, options: options)
        }.value
        items = found
        selected = Set(found.filter(\.preselected).map(\.url))
        phase = .results
    }

    @discardableResult
    func clean(record: Bool = true) async -> CleanResult {
        let toClean = selectedItems
        guard !toClean.isEmpty else { return CleanResult() }
        phase = .cleaning
        let result = await Task.detached(priority: .userInitiated) {
            Cleaner.clean(toClean)
        }.value
        items = []
        selected = []
        phase = .done(freed: result.freed, failures: result.failures)
        if record {
            lastRecord = CleanHistory.shared.record(result, source: module.title, itemCount: toClean.count)
        }
        return result
    }

    func reset() {
        items = []
        selected = []
        phase = .idle
    }
}

@Observable
@MainActor
final class UninstallerModel {
    var apps: [InstalledApp] = []
    var loadingApps = false
    var selectedApp: InstalledApp?
    var leftovers: [CleanupItem] = []
    var selected: Set<URL> = []
    var loadingLeftovers = false
    var working = false
    var lastResult: (name: String, freed: Int64, failures: [String])?

    var selectedSize: Int64 {
        leftovers.filter { selected.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    func loadApps() async {
        loadingApps = true
        apps = await Task.detached(priority: .userInitiated) { Scanner.installedApps() }.value
        loadingApps = false
    }

    func select(_ app: InstalledApp?) async {
        selectedApp = app
        leftovers = []
        selected = []
        lastResult = nil
        guard let app else { return }
        loadingLeftovers = true
        let found = await Task.detached(priority: .userInitiated) { Scanner.leftovers(for: app) }.value
        guard selectedApp == app else { return }
        leftovers = found
        selected = Set(found.filter(\.preselected).map(\.url))
        loadingLeftovers = false
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    func quit(_ app: InstalledApp) {
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) {
            running.terminate()
        }
    }

    func setSelected(_ item: CleanupItem, _ on: Bool) {
        if on { selected.insert(item.url) } else { selected.remove(item.url) }
    }

    func uninstall() async {
        guard let app = selectedApp else { return }
        let toClean = leftovers.filter { selected.contains($0.url) }
        working = true
        let result = await Task.detached(priority: .userInitiated) { Cleaner.clean(toClean) }.value
        working = false
        lastResult = (app.name, result.freed, result.failures)
        CleanHistory.shared.record(result, source: "Uninstalled \(app.name)", itemCount: toClean.count)
        if !FileManager.default.fileExists(atPath: app.url.path) {
            apps.removeAll { $0 == app }
        }
        selectedApp = nil
        leftovers = []
        selected = []
    }
}
