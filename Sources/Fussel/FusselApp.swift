import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications

/// Fussel lives in the menu bar (LSUIElement): no Dock icon, always running in the background.
/// Left-click the menu bar icon to show or hide the window, right-click for a small menu.
@main
struct FusselApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Used by the build pipeline to render screenshots of every style.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-previews"), i + 1 < args.count {
            PreviewRenderer.renderAll(to: args[i + 1])
            exit(0)
        }
        if let i = args.firstIndex(of: "--render-gifs"), i + 1 < args.count {
            PreviewRenderer.renderGIFs(to: args[i + 1])
            exit(0)
        }
    }

    var body: some Scene {
        Settings {
            StyledRoot {
                SettingsView()
            }
        }
    }
}

/// Fussel lives in the menu bar; it can also show up in the Dock (Settings › Show Fussel in the Dock).
/// Then clicking the Dock icon opens the window, and the app gets its own menu bar while in front.
@MainActor
enum DockIcon {
    /// `switched`: the setting was just changed, with Fussel's window in front.
    static func apply(switched: Bool = false) {
        let inDock = UserDefaults.standard.bool(forKey: SettingsKey.showInDock)
        NSApp.setActivationPolicy(inDock ? .regular : .accessory)
        // Leaving the Dock sends the app to the back; keep the window you were just using in front.
        if switched && !inDock { DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) } }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    /// The running delegate, for the few places outside the window that need the model.
    static weak var shared: AppDelegate?

    let model = AppModel()
    private var wiggleTimer: Timer?
    private var wiggleFrame = 0
    private var happyUntil: Date?
    private var updateTimer: Timer?
    private var bedtimeTimer: Timer?
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var keyMonitor: Any?
    private var watcher: FluffWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        DockIcon.apply()
        AppearanceChoice.apply()
        setUpStatusItem()
        setUpKeyboardShortcuts()
        LoginItem.enableOnFirstLaunch()
        UNUserNotificationCenter.current().delegate = self
        let watcher = FluffWatcher(model: model)
        watcher.start()
        self.watcher = watcher
        observeStatusIcon()
        scheduleUpdateChecks()
        // Keep an eye on the Mac's health even while the window is closed, so Fussel's mood is current,
        // but only at a slow background pace until the window opens.
        model.monitor.setFast(false)
        model.monitor.start()
        // First launch after installing: open the window right away with the welcome tour. The window
        // marks the tour as seen as soon as it appears, so it never comes back, even if skipped.
        if !UserDefaults.standard.bool(forKey: FirstLaunch.seen) {
            model.showTutorial = true
            model.permissionsAfterTour = true
            showMainWindow()
        } else if let updated = Self.versionAfterUpdate() {
            // Right after an update: say so once, and help with Full Disk Access if macOS forgot it.
            model.justUpdatedTo = updated
            showMainWindow()
        }
        UserDefaults.standard.set(model.updater.currentVersion, forKey: Self.lastVersionKey)
    }

    private static let lastVersionKey = "lastRunVersion"

    /// The running version, if it's newer than the one that ran last time.
    private static func versionAfterUpdate() -> String? {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        // Before 0.9.9 nobody wrote this down; a known user without it has just come from an older Fussel.
        let last = UserDefaults.standard.string(forKey: lastVersionKey) ?? "0.0.0"
        return VersionCompare.isNewer(current, than: last) ? current : nil
    }

    /// Opening Fussel.app again (from Programme or Spotlight) shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = MenuBarIcon.image
            button.image?.accessibilityDescription = "Fussel"
            button.toolTip = "Fussel"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusMenu()
        } else {
            toggleMainWindow()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Fussel", action: #selector(openFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Scan Mac", action: #selector(scanFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        if let release = model.updater.release, case .available = model.updater.state {
            menu.addItem(withTitle: "Update to Fussel \(release.version)…", action: #selector(installUpdateFromMenu), keyEquivalent: "").target = self
        } else {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkUpdatesFromMenu), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: "Settings…", action: #selector(settingsFromMenu), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Send Feedback…", action: #selector(feedbackFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Fussel", action: #selector(quitFromMenu), keyEquivalent: "q").target = self
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        // Detach again so the next left-click toggles the window instead of opening the menu.
        Task { @MainActor [weak self] in self?.statusItem?.menu = nil }
    }

    @objc private func openFromMenu() { showMainWindow() }
    @objc private func scanFromMenu() {
        showMainWindow()
        Task { await model.smartScan() }
    }
    @objc private func settingsFromMenu() { showSettingsWindow() }
    @objc private func feedbackFromMenu() { Feedback.open() }
    @objc private func checkUpdatesFromMenu() {
        showMainWindow()
        Task { await model.updater.check() }
    }
    @objc private func installUpdateFromMenu() {
        Task { await model.updater.install() }
    }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    /// The menu bar icon is alive: it wiggles while scanning, smiles after cleaning,
    /// and wears a dot while fluff from the weekly check is waiting.
    private func observeStatusIcon() {
        let (stage, _) = withObservationTracking {
            (model.stage, model.pendingFluff)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStatusIcon() }
        }
        switch stage {
        case .scanning, .cleaning:
            startWiggle()
        case .done:
            stopWiggle()
            happyUntil = Date().addingTimeInterval(3)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3.1))
                self?.refreshStatusIcon()
            }
        default:
            stopWiggle()
        }
        refreshStatusIcon()
    }

    private func refreshStatusIcon() {
        guard wiggleTimer == nil else { return }
        if let until = happyUntil, until > Date() {
            statusItem?.button?.image = MenuBarIcon.happy
        } else {
            // Waiting fluff matters more than bedtime; otherwise he dozes at night.
            statusItem?.button?.image = model.pendingFluff > 0 ? MenuBarIcon.imageWithDot
                : (Bedtime.now ? MenuBarIcon.asleep : MenuBarIcon.image)
        }
    }

    private func startWiggle() {
        guard wiggleTimer == nil else { return }
        // 10 frames per second only while scanning; the timer is gone the rest of the time.
        wiggleTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.wiggleFrame = (self.wiggleFrame + 1) % MenuBarIcon.busy.count
                self.statusItem?.button?.image = MenuBarIcon.busy[self.wiggleFrame]
            }
        }
    }

    private func stopWiggle() {
        wiggleTimer?.invalidate()
        wiggleTimer = nil
    }

    /// Fussel looks for its own updates shortly after launch and then every few hours (at most daily).
    private func scheduleUpdateChecks() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            await self?.model.updater.checkIfDue()
        }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.updater.checkIfDue() }
        }
        // Falls asleep at 23:00 and wakes at 6:00: a look every few minutes is plenty.
        bedtimeTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatusIcon() }
        }
    }

    // MARK: Notifications

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.showMainWindow() }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Quietly: a tidy-up reminder is no reason to make a sound.
        completionHandler([.banner, .list])
    }

    // MARK: Windows

    private func toggleMainWindow() {
        if let window = mainWindow, window.isVisible, window.isKeyWindow {
            window.orderOut(nil)
            model.monitor.setFast(false)
        } else {
            showMainWindow()
        }
    }

    func showMainWindow() {
        if mainWindow == nil {
            let root = StyledRoot { ContentView() }
                .environment(model)
            let controller = NSHostingController(rootView: root)
            controller.sizingOptions = []
            let window = NSWindow(contentViewController: controller)
            window.title = "Fussel"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // An empty toolbar makes the title bar as tall as Fussel's top bar, with the window buttons centred in it.
            window.toolbar = NSToolbar(identifier: "main")
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 960, height: 640))
            window.contentMinSize = NSSize(width: 820, height: 560)
            window.setFrameAutosaveName("FusselWindow")
            window.delegate = self
            if !window.setFrameUsingName("FusselWindow") { window.center() }
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
        model.monitor.setFast(true)
    }

    func showSettingsWindow() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: StyledRoot { SettingsView() })
            let window = NSWindow(contentViewController: controller)
            window.title = "Fussel Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Closing the window only hides it; Fussel keeps running in the menu bar.
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === mainWindow { model.monitor.setFast(false) }
    }

    /// Hidden, minimised or covered by other windows: stop drawing frames nobody sees.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        model.windowVisible = window.occlusionState.contains(.visible)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        if (notification.object as? NSWindow) === mainWindow { model.monitor.setFast(false) }
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        if (notification.object as? NSWindow) === mainWindow { model.monitor.setFast(true) }
    }

    // MARK: Keyboard

    /// Without a visible menu bar, handle the usual shortcuts ourselves.
    private func setUpKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  let key = event.charactersIgnoringModifiers?.lowercased() else { return event }
            switch key {
            case "w":
                NSApp.keyWindow?.performClose(nil)
            case "q":
                NSApp.terminate(nil)
            case ",":
                self.showSettingsWindow()
            case "r":
                if self.model.stage != .scanning && self.model.stage != .cleaning {
                    Task { await self.model.smartScan() }
                }
            case "m":
                NSApp.keyWindow?.miniaturize(nil)
            default:
                return event
            }
            return nil
        }
    }
}

/// Start Fussel together with the Mac, like CleanMyMac.
enum LoginItem {
    private static let configuredKey = "loginItemConfigured"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Fussel: login item change failed: \(error.localizedDescription)")
        }
    }

    static func enableOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: configuredKey) else { return }
        UserDefaults.standard.set(true, forKey: configuredKey)
        setEnabled(true)
    }
}
