import SwiftUI
import AppKit
import ServiceManagement

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
    }

    var body: some Scene {
        Settings {
            StyledRoot {
                SettingsView()
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setUpStatusItem()
        setUpKeyboardShortcuts()
        LoginItem.enableOnFirstLaunch()
        // First launch: open the window right away so the tutorial greets people.
        if !UserDefaults.standard.bool(forKey: TutorialKey.seen) {
            showMainWindow()
        }
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
        menu.addItem(withTitle: "Show Tutorial", action: #selector(tutorialFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(settingsFromMenu), keyEquivalent: ",").target = self
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
    @objc private func tutorialFromMenu() {
        showMainWindow()
        model.showTutorial = true
    }
    @objc private func settingsFromMenu() { showSettingsWindow() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    // MARK: Windows

    private func toggleMainWindow() {
        if let window = mainWindow, window.isVisible, window.isKeyWindow {
            window.orderOut(nil)
        } else {
            showMainWindow()
        }
    }

    func showMainWindow() {
        if mainWindow == nil {
            let root = StyledRoot { ContentView() }
                .environment(model)
            let controller = NSHostingController(rootView: root)
            controller.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: controller)
            window.title = "Fussel"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 760, height: 720))
            window.setFrameAutosaveName("FusselMainWindow")
            window.delegate = self
            if !window.setFrameUsingName("FusselMainWindow") { window.center() }
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
        model.monitor.start()
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
        if (notification.object as? NSWindow) === mainWindow {
            model.monitor.stop()
        }
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
