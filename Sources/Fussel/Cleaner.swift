import Foundation
import AppKit

/// Removes items. Moves to the Trash by default; only items that are already in the Trash are deleted for good.
enum Cleaner {
    static func clean(_ items: [CleanupItem]) -> CleanResult {
        var result = CleanResult()
        let fm = FileManager.default
        for item in items {
            guard isSafeToRemove(item.url) else {
                result.failures.append("\(item.name): skipped for safety")
                continue
            }
            do {
                if item.permanent {
                    try fm.removeItem(at: item.url)
                } else {
                    var trashedURL: NSURL?
                    try fm.trashItem(at: item.url, resultingItemURL: &trashedURL)
                    if let trashedURL = trashedURL as URL? {
                        result.trashed.append(TrashedItem(name: item.name, original: item.url,
                                                          trashed: trashedURL, size: item.size))
                    }
                }
                result.freed += item.size
            } catch {
                result.failures.append("\(item.name): \(error.localizedDescription)")
            }
        }
        return result
    }

    /// A last line of defence: only paths inside the home folder (never the important top-level
    /// folders themselves) and app bundles in /Applications may ever be touched.
    static func isSafeToRemove(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let library = home + "/Library"
        let forbidden: Set<String> = [
            "/", home, library, home + "/Desktop", home + "/Documents", home + "/Downloads",
            home + "/Pictures", home + "/Music", home + "/Movies", home + "/Applications", home + "/.Trash",
            library + "/Caches", library + "/Logs", library + "/Application Support", library + "/Preferences",
            library + "/Containers", library + "/Group Containers", library + "/LaunchAgents",
            library + "/Developer", library + "/Developer/Xcode", "/Applications",
        ]
        if forbidden.contains(path) { return false }
        if path.hasPrefix(home + "/") { return true }
        if path.hasPrefix("/Applications/") && path.hasSuffix(".app") { return true }
        return false
    }
}

enum Permissions {
    /// Reading the TCC database only works with Full Disk Access, which makes it a reliable probe.
    static var hasFullDiskAccess: Bool {
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        if let handle = try? FileHandle(forReadingFrom: probe) {
            try? handle.close()
            return true
        }
        return false
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
