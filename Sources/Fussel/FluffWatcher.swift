import Foundation
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

        let items = await Task.detached(priority: .background) { Scanner.scanJunk() }.value
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
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func weeklyReminder() async {
        guard await requestPermission() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Weekly tidy-up time!"
        content.body = "It's been a week since your last scan. Want me to take a quick look?"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "weekly-reminder", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func fluffFound(_ bytes: Int64) async {
        guard await requestPermission() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Fussel found some fluff"
        content.body = "About \(bytes.byteString) of caches and logs are piling up. Click to tidy up."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "weekly-fluff", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
