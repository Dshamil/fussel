import AppKit
import os
import UserNotifications

/// The weekly reminder: if nobody has scanned for a week, Fussel quietly checks caches and logs in
/// the background and sends a friendly reminder. When there's a lot of fluff, it says how much and
/// puts a dot on the menu bar icon.
@MainActor
final class FluffWatcher {
    static let lastScanKey = "lastScanDate"
    static let lastNudgeKey = "lastFluffNudge"
    static let enabledKey = "weeklyFluffCheck"

    /// Only nudge when it's worth it.
    private let threshold: Int64 = 300_000_000
    private let week: TimeInterval = 7 * 24 * 3600

    private weak var model: AppModel?
    private var timer: Timer?

    init(model: AppModel) {
        self.model = model
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    func start() {
        // Never nudge right after the very first launch: count the install as a fresh start.
        if UserDefaults.standard.object(forKey: Self.lastScanKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.lastScanKey)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(90))
            await self?.check()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    func check() async {
        guard Self.isEnabled, let model else { return }
        guard model.stage != .scanning, model.stage != .cleaning else { return }
        let defaults = UserDefaults.standard
        let lastScan = defaults.object(forKey: Self.lastScanKey) as? Date ?? .distantPast
        let lastNudge = defaults.object(forKey: Self.lastNudgeKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastScan) > week,
              Date().timeIntervalSince(lastNudge) > week else { return }

        let items = await Task.detached(priority: .background) {
            ScanProgress.$quiet.withValue(true) { Scanner.scanJunk() }
        }.value
        let bytes = items.filter(\.preselected).reduce(Int64(0)) { $0 + $1.size }
        defaults.set(Date(), forKey: Self.lastNudgeKey)
        if bytes >= threshold {
            model.pendingFluff = bytes
            await Notifier.fluffFound(bytes)
        } else {
            await Notifier.weeklyReminder()
        }
    }
}

enum Notifier {
    /// Why a reminder didn't show, readable with `log show --predicate 'subsystem == "app.fussel.Fussel"'`.
    private static let log = Logger(subsystem: "app.fussel.Fussel", category: "notifications")

    /// The Show Example button. It never just does nothing: if macOS won't show Fussel's reminders,
    /// it opens the place in System Settings where they're switched on.
    static func showExample() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        log.notice("example: status \(settings.authorizationStatus.rawValue), style \(settings.alertStyle.rawValue)")
        switch settings.authorizationStatus {
        case .notDetermined:
            guard await requestPermission() else { return openSettings() }
            await weeklyReminder()
        case .authorized, .provisional, .ephemeral:
            if settings.alertStyle == .none { return openSettings() }
            await weeklyReminder()
        default:
            openSettings()
        }
    }
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert])
        } catch {
            log.error("asking for permission failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Allowed, but set to "None" in System Settings: the reminder arrives without anything to see.
    static var bannersOff: Bool {
        get async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return settings.authorizationStatus == .authorized && settings.alertStyle == .none
        }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=app.fussel.Fussel") {
            NSWorkspace.shared.open(url)
        }
    }

    static func weeklyReminder() async {
        guard await requestPermission() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time for a quick tidy-up"
        content.body = "It's been a week since your last scan. Want me to take a quick look?"
        await post(content, id: "weekly-reminder")
    }

    /// An older reminder with the same ID still in Notification Center would only be swapped quietly,
    /// without a new banner; so it goes first.
    private static func post(_ content: UNMutableNotificationContent, id: String) async {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [id])
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        } catch {
            log.error("reminder not sent: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func fluffFound(_ bytes: Int64) async {
        guard await requestPermission() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Fussel found some fluff"
        content.body = "About \(bytes.byteString) of caches and logs are piling up. Click to tidy up."
        await post(content, id: "weekly-fluff")
    }
}
