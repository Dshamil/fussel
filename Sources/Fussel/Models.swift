import Foundation

/// The four cleaning areas of Fussel.
enum Module: String, CaseIterable, Identifiable, Hashable {
    case junk, large, uninstaller, tidy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .junk: return "System Junk"
        case .large: return "Large & Old Files"
        case .uninstaller: return "Uninstaller"
        case .tidy: return "Trash & Downloads"
        }
    }

    var symbol: String {
        switch self {
        case .junk: return "sparkles"
        case .large: return "externaldrive"
        case .uninstaller: return "xmark.bin"
        case .tidy: return "tray.full"
        }
    }

    var blurb: String {
        switch self {
        case .junk:
            return "Caches, logs and leftover build data pile up quietly. Fussel finds them and moves them to the Trash."
        case .large:
            return "Find big files and things you haven't opened in ages, so you can decide what stays."
        case .uninstaller:
            return "Remove apps together with the support files, caches and preferences they leave behind."
        case .tidy:
            return "Empty the Trash and sweep out downloads you no longer need."
        }
    }
}

/// One thing Fussel can remove.
struct CleanupItem: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let name: String
    let group: String
    let size: Int64
    var date: Date? = nil
    /// Items already in the Trash are deleted for good; everything else is moved to the Trash.
    var permanent = false
    var preselected = false

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

struct ScanOptions: Sendable {
    var largeFileMB: Int
    var oldFileDays: Int
    var downloadDays: Int
}

struct InstalledApp: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let name: String
    let bundleID: String
}

struct CleanResult: Sendable {
    var freed: Int64 = 0
    var failures: [String] = []
    /// Where each item ended up in the Trash, so it can be put back.
    var trashed: [TrashedItem] = []

    mutating func merge(_ other: CleanResult) {
        freed += other.freed
        failures += other.failures
        trashed += other.trashed
    }
}

struct TrashedItem: Codable, Hashable, Sendable {
    let name: String
    let original: URL
    let trashed: URL
    let size: Int64
}
