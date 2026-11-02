import Foundation

/// Folders the user told Fussel to leave alone: nothing in them shows up in a scan, and nothing in them
/// is ever cleaned. Kept in the settings, on this Mac only.
enum Exclusions {
    static var folders: [String] {
        UserDefaults.standard.stringArray(forKey: SettingsKey.excludedFolders) ?? []
    }

    static func add(_ folder: URL) {
        let path = folder.standardizedFileURL.path
        guard !folders.contains(path) else { return }
        UserDefaults.standard.set(folders + [path], forKey: SettingsKey.excludedFolders)
    }

    static func remove(_ path: String) {
        UserDefaults.standard.set(folders.filter { $0 != path }, forKey: SettingsKey.excludedFolders)
    }

    static func covers(_ url: URL) -> Bool { covers(url, folders: folders) }

    /// Inside one of the folders, or that folder itself. The Mac's disk ignores upper and lower case, and a
    /// file can be reached through a redirect (symlink), so both spellings of each path are compared.
    static func covers(_ url: URL, folders: [String]) -> Bool {
        guard !folders.isEmpty else { return false }
        let paths = [url.standardizedFileURL.path, url.resolvingSymlinksInPath().path].map { $0.lowercased() }
        return folders.contains { folder in
            let folder = URL(fileURLWithPath: folder)
            let roots = [folder.standardizedFileURL.path, folder.resolvingSymlinksInPath().path].map { $0.lowercased() }
            return roots.contains { root in paths.contains { $0 == root || $0.hasPrefix(root + "/") } }
        }
    }
}
