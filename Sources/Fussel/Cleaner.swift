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

    /// A last line of defence: only things inside the home folder (never its folders, the important
    /// Library folders or anything holding keys) and non-Apple app bundles in /Applications may ever be
    /// touched. Every scanner already stays within this; this check catches any future mistake.
    static func isSafeToRemove(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        // A folder on the way that is really a redirect (symlink) would let a harmless-looking path reach
        // somewhere else, like an app pointing its cache folder at your Documents. Such paths never go.
        // (The item itself may be a link: moving a link to the Trash leaves its target alone.)
        let parent = standardized.deletingLastPathComponent()
        guard parent.resolvingSymlinksInPath().path == parent.path else { return false }
        // The Mac's disk ignores upper and lower case, so the checks do too: "documents" is Documents.
        let path = standardized.path.lowercased()
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path.lowercased()
        let library = home + "/library"
        let forbidden: Set<String> = [
            "/", home, library, home + "/desktop", home + "/documents", home + "/downloads",
            home + "/pictures", home + "/music", home + "/movies", home + "/public", home + "/applications",
            home + "/.trash", library + "/caches", library + "/logs", library + "/application support",
            library + "/preferences", library + "/containers", library + "/group containers",
            library + "/launchagents", library + "/developer", library + "/developer/xcode",
            library + "/mobile documents", library + "/cloudstorage", library + "/mail", library + "/messages",
            "/applications",
        ]
        if forbidden.contains(path) { return false }
        // Never anything inside the places that hold passwords and keys.
        for secret in [library + "/keychains", home + "/.ssh", home + "/.gnupg"]
        where path == secret || path.hasPrefix(secret + "/") {
            return false
        }
        // Never anything in a library of Photos, Music, iMovie or Final Cut: it is a database, and taking
        // one file out of it breaks it.
        let libraries = [".photoslibrary", ".photolibrary", ".musiclibrary", ".tvlibrary", ".imovielibrary", ".fcpbundle"]
        if standardized.pathComponents.contains(where: { part in libraries.contains { part.lowercased().hasSuffix($0) } }) {
            return false
        }
        if path.hasPrefix(home + "/") {
            // Folders right in the home folder are the user's own (like ~/Projects): files there may go,
            // the folders themselves never.
            let inHome = standardized.deletingLastPathComponent().path.lowercased() == home
            return !(inHome && isFolder(standardized))
        }
        // Apps in /Applications, also one folder down (like /Applications/Utilities), but never Apple's own.
        let depth = standardized.pathComponents.count
        if path.hasPrefix("/applications/"), path.hasSuffix(".app"), depth == 3 || depth == 4 {
            return !(Bundle(url: standardized)?.bundleIdentifier?.hasPrefix("com.apple.") ?? false)
        }
        return false
    }

    private static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
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

    static func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
