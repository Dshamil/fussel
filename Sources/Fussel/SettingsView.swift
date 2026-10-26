import SwiftUI
import AppKit

enum SettingsKey {
    static let largeFileMB = "largeFileMB"
    static let oldFileDays = "oldFileDays"
    static let downloadDays = "downloadDays"
    static let sounds = "playSounds"
    static let appearance = "appearance"
}

extension ScanOptions {
    static var current: ScanOptions {
        let d = UserDefaults.standard
        return ScanOptions(
            largeFileMB: d.object(forKey: SettingsKey.largeFileMB) as? Int ?? 500,
            oldFileDays: d.object(forKey: SettingsKey.oldFileDays) as? Int ?? 365,
            downloadDays: d.object(forKey: SettingsKey.downloadDays) as? Int ?? 30
        )
    }
}

struct SettingsView: View {
    @AppStorage(SettingsKey.largeFileMB) private var largeFileMB = 500
    @AppStorage(SettingsKey.oldFileDays) private var oldFileDays = 365
    @AppStorage(SettingsKey.downloadDays) private var downloadDays = 30
    @State private var openAtLogin = LoginItem.isEnabled
    @AppStorage(FluffWatcher.enabledKey) private var weeklyCheck = true
    @AppStorage(FusselUpdater.autoKey) private var autoUpdate = true
    @AppStorage(SettingsKey.sounds) private var playSounds = false
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceChoice.system.rawValue

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Style", selection: $appearance) {
                    Text("Match Mac").tag(AppearanceChoice.system.rawValue)
                    Text("Light").tag(AppearanceChoice.light.rawValue)
                    Text("Dark").tag(AppearanceChoice.dark.rawValue)
                    Text("Glass").tag(AppearanceChoice.glass.rawValue)
                    Text("Oreo").tag(AppearanceChoice.oreo.rawValue)
                }
                .pickerStyle(.segmented)
            }
            Section("Permissions") {
                HStack {
                    Text("Full Disk Access, notifications and starting with your Mac.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Permissions") {
                        guard let delegate = AppDelegate.shared else { return }
                        delegate.model.showPermissions = true
                        delegate.showMainWindow()
                    }
                }
            }
            Section("Welcome Tour") {
                HStack {
                    Text("A short look at how Fussel works.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show Tour") {
                        guard let delegate = AppDelegate.shared else { return }
                        delegate.model.showTutorial = true
                        delegate.showMainWindow()
                    }
                }
            }
            Section("Sounds") {
                Toggle("Play little sounds", isOn: $playSounds)
            }
            Section("Updates") {
                Toggle("Check for Fussel updates automatically", isOn: $autoUpdate)
                HStack {
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let updater = AppDelegate.shared?.model.updater {
                        UpdateControls(updater: updater)
                    }
                }
                if let note = AppDelegate.shared?.model.updater.note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Section("Large & Old Files") {
                Picker("Count a file as large from", selection: $largeFileMB) {
                    Text("100 MB").tag(100)
                    Text("250 MB").tag(250)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1000)
                    Text("5 GB").tag(5000)
                }
                Picker("Count a file as old after", selection: $oldFileDays) {
                    Text("3 months").tag(90)
                    Text("6 months").tag(180)
                    Text("1 year").tag(365)
                    Text("2 years").tag(730)
                }
            }
            Section("Downloads") {
                Picker("Suggest downloads older than", selection: $downloadDays) {
                    Text("1 week").tag(7)
                    Text("1 month").tag(30)
                    Text("3 months").tag(90)
                    Text("6 months").tag(180)
                }
            }
            Section("General") {
                Toggle("Open Fussel at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, enabled in
                        LoginItem.setEnabled(enabled)
                    }
                Toggle("Weekly reminder", isOn: $weeklyCheck)
                    .onChange(of: weeklyCheck) { _, enabled in
                        if enabled { Task { _ = await Notifier.requestPermission() } }
                    }
                HStack(alignment: .firstTextBaseline) {
                    Text("If you haven't scanned for a week, Fussel peeks at caches and logs and sends a friendly reminder.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Show Example") { Task { await Notifier.weeklyReminder() } }
                        .controlSize(.small)
                }
                Text("Fussel lives in the menu bar. Click the little fluff to open it, right-click for more.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// What Settings shows next to the version: a status, and Update Now as soon as there is something new.
private struct UpdateControls: View {
    let updater: FusselUpdater

    var body: some View {
        switch updater.state {
        case .checking:
            ProgressView().controlSize(.small)
            Text("Checking…").font(.system(size: 11)).foregroundStyle(.secondary)
        case .available(let release):
            Text("Fussel \(release.version) is available")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("Update Now") { Task { await updater.install() } }
                .keyboardShortcut(.defaultAction)
        case .downloading:
            ProgressView().controlSize(.small)
            Text("Downloading…").font(.system(size: 11)).foregroundStyle(.secondary)
        case .installing:
            ProgressView().controlSize(.small)
            Text("Installing…").font(.system(size: 11)).foregroundStyle(.secondary)
        case .upToDate:
            Text("You're up to date").font(.system(size: 11)).foregroundStyle(.secondary)
            checkButton
        case .failed(let message):
            Text(message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            checkButton
        case .idle:
            checkButton
        }
    }

    private var checkButton: some View {
        Button("Check Now") { Task { await updater.check() } }
    }
}
