import SwiftUI

enum SettingsKey {
    static let largeFileMB = "largeFileMB"
    static let oldFileDays = "oldFileDays"
    static let downloadDays = "downloadDays"
    static let showMenuBarIcon = "showMenuBarIcon"
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
    @AppStorage(SettingsKey.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some View {
        Form {
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
                Toggle("Show Fussel in the menu bar", isOn: $showMenuBarIcon)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
