import Foundation
import AppKit

/// All file system scanning. Everything here is synchronous and meant to run off the main thread.
enum Scanner {
    static var fm: FileManager { FileManager.default }
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var library: URL { home.appendingPathComponent("Library") }

    static let ownBundleID = "app.fussel.Fussel"

    // MARK: Entry point

    static func scan(_ module: Module, options: ScanOptions) -> [CleanupItem] {
        switch module {
        case .junk: return scanJunk()
        case .large: return scanLargeAndOld(options: options)
        case .tidy: return scanTidy(options: options)
        case .uninstaller, .updates: return []
        }
    }

    // MARK: Sizes

    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        var total: Int64 = 0
        let fileKeys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: fileKeys, options: [],
                                             errorHandler: { _, _ in true }) else { return 0 }
        while let file = enumerator.nextObject() as? URL {
            ScanProgress.shared.visit(file)
            if let v = try? file.resourceValues(forKeys: Set(fileKeys)), v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
            }
        }
        return total
    }

    static func children(of dir: URL, keys: [URLResourceKey] = []) -> [URL] {
        (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [])) ?? []
    }

    /// Turns "com.google.Chrome" into "Google Chrome" when the app is installed.
    static func friendlyName(for url: URL) -> String {
        let raw = url.lastPathComponent
        if raw.contains("."),
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: raw) {
            return fm.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
        }
        return raw
    }

    // MARK: System junk

    /// Caches belonging to system services that are better left alone.
    static let protectedCaches: Set<String> = [
        "CloudKit", "com.apple.HomeKit", "com.apple.containermanagerd", "FamilyCircle",
        "com.apple.ap.adprivacyd", "com.apple.findmy.fmipcore", "com.apple.bird",
        "com.apple.nsurlsessiond", ownBundleID,
    ]

    static func scanJunk() -> [CleanupItem] {
        var items: [CleanupItem] = []

        let groups: [(String, URL)] = [
            ("App Caches", library.appendingPathComponent("Caches")),
            ("Logs", library.appendingPathComponent("Logs")),
        ]
        for (group, dir) in groups {
            for child in children(of: dir) {
                let name = child.lastPathComponent
                if name.hasPrefix(".") || protectedCaches.contains(name) { continue }
                let bytes = size(of: child)
                guard bytes > 0 else { continue }
                items.append(found(CleanupItem(url: child, name: friendlyName(for: child), group: group,
                                         size: bytes, preselected: true)))
            }
        }

        let developer: [(String, String)] = [
            ("Xcode Derived Data", "Developer/Xcode/DerivedData"),
            ("Xcode Archives", "Developer/Xcode/Archives"),
            ("Old Device Support", "Developer/Xcode/iOS DeviceSupport"),
        ]
        for (name, path) in developer {
            let url = library.appendingPathComponent(path)
            guard fm.fileExists(atPath: url.path) else { continue }
            let bytes = size(of: url)
            guard bytes > 0 else { continue }
            items.append(found(CleanupItem(url: url, name: name, group: "Developer", size: bytes, preselected: name == "Xcode Derived Data")))
        }

        // Apps from the App Store (and other sandboxed apps) keep their caches inside their own container.
        // Looking in there needs Full Disk Access; without it macOS would ask once per app, so Fussel doesn't.
        // Only what's inside each Caches folder goes, never the folder itself, and never Apple's containers.
        if Permissions.hasFullDiskAccess {
            for container in children(of: library.appendingPathComponent("Containers")) {
                let id = container.lastPathComponent
                guard !id.hasPrefix("com.apple."), id != ownBundleID, !protectedCaches.contains(id) else { continue }
                let app = friendlyName(for: container)
                // The app owns its container and could point Caches (or a folder above it) elsewhere.
                let caches = container.appendingPathComponent("Data/Library/Caches")
                guard caches.resolvingSymlinksInPath().path == caches.path else { continue }
                for child in children(of: caches) where !child.lastPathComponent.hasPrefix(".") {
                    let bytes = size(of: child)
                    // Small bits aren't worth a row of their own.
                    guard bytes >= 1_000_000 else { continue }
                    items.append(found(CleanupItem(url: child, name: "\(app): \(child.lastPathComponent)",
                                                   group: "App Caches", size: bytes, preselected: true)))
                }
            }
        }

        items += leftoversOfRemovedApps()
        return sortedByGroup(items)
    }

    // MARK: Leftovers of removed apps

    /// Support files of apps that are no longer on the Mac. Careful on purpose: the name has to be a bundle ID
    /// (like com.spotify.client), nothing installed may come from the same maker (an app or an audio plug-in;
    /// "pioneer" and "pioneerdj" count as one), it isn't Apple's or a building block other apps share (like
    /// Firebase), it hasn't changed in 30 days, and a background agent only counts when its program is gone.
    /// Even then nothing is preselected: each one waits for a look.
    static func leftoversOfRemovedApps() -> [CleanupItem] {
        let makers = installedMakers()
        let month = Date().addingTimeInterval(-30 * 86_400)
        var places: [(folder: String, suffix: String)] = [
            ("Application Support", ""), ("Preferences", ".plist"), ("Saved Application State", ".savedState"),
            ("HTTPStorages", ""), ("WebKit", ""), ("LaunchAgents", ".plist"),
        ]
        // Containers are only looked into with Full Disk Access (see the caches above).
        if Permissions.hasFullDiskAccess { places.append(("Containers", "")) }

        var items: [CleanupItem] = []
        for (folder, suffix) in places {
            for child in children(of: library.appendingPathComponent(folder)) {
                var id = child.lastPathComponent
                if !suffix.isEmpty {
                    guard id.hasSuffix(suffix) else { continue }
                    id.removeLast(suffix.count)
                }
                guard looksLikeBundleID(id), let who = maker(id), !id.lowercased().hasPrefix("com.apple."),
                      !sharedBuildingBlocks.contains(who), !makers.contains(where: { sameMaker($0, who) }),
                      NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) == nil,
                      newestChange(in: child) < month else { continue }
                if folder == "LaunchAgents", programStillThere(agent: child) { continue }
                let bytes = size(of: child)
                guard bytes > 0 else { continue }
                items.append(found(CleanupItem(url: child, name: id, group: "Leftovers of Removed Apps",
                                               size: bytes, preselected: false)))
            }
        }
        return items
    }

    /// At least three parts with letters, digits or dashes, like com.spotify.client.
    static func looksLikeBundleID(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 3 && parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }

    /// Parts of a bundle ID that name a domain, not a maker.
    private static let domainParts: Set<String> = [
        "com", "org", "net", "io", "de", "app", "fyi", "co", "me", "dev", "ai", "us", "uk", "eu", "group", "info", "tv",
    ]
    /// Code that many apps build in; its settings belong to whichever app uses it, not to a removed app.
    static let sharedBuildingBlocks: Set<String> = [
        "apple", "firebase", "segment", "bugsnag", "crashlytics", "sentry", "appcenter", "amplitude", "mixpanel",
        "sparkle-project", "google", "googlecode",
    ]

    /// Who made it: the first part that isn't a domain, lowercased. "spotify" for com.spotify.client,
    /// "adobe" for adobe.com.Adobe-Spaces-Helper, "nordvpn" for group.com.nordvpn.macos.
    static func maker(_ id: String) -> String? {
        id.lowercased().split(separator: ".").map(String.init).prefix(3).first { !domainParts.contains($0) }
    }

    /// The same maker, also when one name is the other plus a bit ("pioneer" and "pioneerdj").
    static func sameMaker(_ a: String, _ b: String) -> Bool {
        a == b || (min(a.count, b.count) >= 4 && (a.hasPrefix(b) || b.hasPrefix(a)))
    }

    /// Makers of everything installed: apps, Fussel itself, and audio plug-ins (which aren't apps, but keep
    /// settings like one).
    static func installedMakers() -> Set<String> {
        var ids = appBundles().map(\.id) + [ownBundleID]
        for root in [URL(fileURLWithPath: "/Library/Audio/Plug-Ins"), library.appendingPathComponent("Audio/Plug-Ins")] {
            for kind in children(of: root) {
                for plugin in children(of: kind) { if let id = Bundle(url: plugin)?.bundleIdentifier { ids.append(id) } }
            }
        }
        return Set(ids.compactMap(maker))
    }

    /// When anything in here last changed (a folder's own date doesn't move when a file inside is edited).
    static func newestChange(in url: URL) -> Date {
        let key: URLResourceKey = .contentModificationDateKey
        var newest = (try? url.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantFuture
        guard let files = fm.enumerator(at: url, includingPropertiesForKeys: [key], options: [],
                                        errorHandler: { _, _ in true }) else { return newest }
        for case let file as URL in files {
            if let date = try? file.resourceValues(forKeys: [key]).contentModificationDate, date > newest { newest = date }
        }
        return newest
    }

    /// A background agent whose program still exists belongs to something installed (a command-line tool,
    /// a Homebrew service), even without an app.
    static func programStillThere(agent plist: URL) -> Bool {
        guard let info = NSDictionary(contentsOf: plist) else { return true }
        let program = info["Program"] as? String ?? (info["ProgramArguments"] as? [String])?.first
        guard let program, !program.isEmpty else { return true }
        // A bare name like "node" is looked up in the shell's PATH at run time; Fussel can't be sure it's
        // gone, so the agent stays.
        guard program.hasPrefix("/") || program.hasPrefix("~") else { return true }
        return fm.fileExists(atPath: (program as NSString).expandingTildeInPath)
    }

    // MARK: Large & old files

    static func scanLargeAndOld(options: ScanOptions) -> [CleanupItem] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isPackageKey, .totalFileAllocatedSizeKey, .fileSizeKey,
            .contentAccessDateKey, .contentModificationDateKey,
        ]
        let skipTopLevel: Set<String> = ["Library", "Applications", "Pictures", "Music"]
        let minLarge = Int64(options.largeFileMB) * 1_000_000
        let minOld: Int64 = 10_000_000
        let cutoff = Calendar.current.date(byAdding: .day, value: -options.oldFileDays, to: Date()) ?? Date()

        guard let enumerator = fm.enumerator(at: home, includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                             errorHandler: { _, _ in true }) else { return [] }
        var items: [CleanupItem] = []
        while let url = enumerator.nextObject() as? URL {
            ScanProgress.shared.visit(url)
            if enumerator.level == 1 && skipTopLevel.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isPackage == true { continue }
            guard v.isRegularFile == true else { continue }

            let bytes = Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
            let date = v.contentAccessDate ?? v.contentModificationDate
            if bytes >= minLarge {
                items.append(found(CleanupItem(url: url, name: url.lastPathComponent, group: "Large Files",
                                         size: bytes, date: date)))
            } else if bytes >= minOld, let date, date < cutoff {
                items.append(found(CleanupItem(url: url, name: url.lastPathComponent, group: "Not Opened in a While",
                                         size: bytes, date: date)))
            }
            if items.count >= 2000 { break }
        }
        return sortedByGroup(items)
    }

    // MARK: Trash & downloads

    static func scanTidy(options: ScanOptions) -> [CleanupItem] {
        var items: [CleanupItem] = []

        for child in children(of: home.appendingPathComponent(".Trash")) where child.lastPathComponent != ".DS_Store" {
            let bytes = size(of: child)
            items.append(found(CleanupItem(url: child, name: child.lastPathComponent, group: "Trash",
                                     size: bytes, permanent: true)))
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -options.downloadDays, to: Date()) ?? Date()
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey]
        for child in children(of: home.appendingPathComponent("Downloads"), keys: keys) {
            let name = child.lastPathComponent
            if name.hasPrefix(".") { continue }
            let v = try? child.resourceValues(forKeys: Set(keys))
            guard let added = v?.addedToDirectoryDate ?? v?.contentModificationDate, added < cutoff else { continue }
            items.append(found(CleanupItem(url: child, name: name, group: "Old Downloads",
                                     size: size(of: child), date: added)))
        }
        return sortedByGroup(items)
    }

    // MARK: Uninstaller

    /// Every app in /Applications and ~/Applications (one folder level deep), once per bundle ID, without Fussel.
    static func appBundles() -> [(url: URL, bundle: Bundle, id: String)] {
        let dirs = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var list: [(url: URL, bundle: Bundle, id: String)] = []
        var seen = Set<String>()
        func consider(_ url: URL) {
            guard url.pathExtension == "app", let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  id != ownBundleID, seen.insert(id).inserted else { return }
            list.append((url, bundle, id))
        }
        for dir in dirs {
            for child in children(of: dir) {
                if child.pathExtension == "app" {
                    consider(child)
                } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    // e.g. "/Applications/Adobe Something/"
                    for grandchild in children(of: child) { consider(grandchild) }
                }
            }
        }
        return list
    }

    static func appName(_ url: URL) -> String {
        fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func installedApps() -> [InstalledApp] {
        appBundles()
            .filter { !$0.id.hasPrefix("com.apple.") }
            .map { InstalledApp(url: $0.url, name: appName($0.url), bundleID: $0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// An app chooses its own name and ID. Only a plain name may become part of a path: no "/", no
    /// ":" (shown as "/" in Finder), not empty and not "." or "..", so it can't point anywhere else.
    static func isPlainName(_ text: String) -> Bool {
        !text.isEmpty && text != "." && text != ".." && !text.contains("/") && !text.contains(":")
    }

    /// The app bundle itself plus every support file Fussel can attribute to it.
    static func leftovers(for app: InstalledApp) -> [CleanupItem] {
        let id = isPlainName(app.bundleID) ? app.bundleID : ""
        let name = isPlainName(app.name) ? app.name : ""
        var candidates: [URL] = []
        func add(_ path: String) {
            // Paths built from a name that wasn't plain are left out; so are the prefix matches below.
            guard !path.hasSuffix("/"), !path.contains("/."), !path.hasPrefix(".") else { return }
            candidates.append(library.appendingPathComponent(path))
        }

        add("Application Support/\(id)")
        add("Application Support/\(name)")
        add("Caches/\(id)")
        add("Caches/\(name)")
        add("Preferences/\(id).plist")
        add("Containers/\(id)")
        add("Saved Application State/\(id).savedState")
        add("Logs/\(id)")
        add("Logs/\(name)")
        add("HTTPStorages/\(id)")
        add("HTTPStorages/\(id).binarycookies")
        add("WebKit/\(id)")
        add("Cookies/\(id).binarycookies")

        let prefixMatches: [(String, (String) -> Bool)] = [
            ("Preferences/ByHost", { $0.hasPrefix(id + ".") }),
            ("LaunchAgents", { $0.hasPrefix(id) && $0.hasSuffix(".plist") }),
            ("Group Containers", { $0.hasSuffix("." + id) || $0 == id }),
            ("Application Scripts", { $0 == id }),
        ]
        for (folder, matches) in prefixMatches where !id.isEmpty {
            for child in children(of: library.appendingPathComponent(folder)) where matches(child.lastPathComponent) {
                candidates.append(child)
            }
        }

        var items: [CleanupItem] = [
            CleanupItem(url: app.url, name: app.name, group: "Application", size: size(of: app.url), preselected: true)
        ]
        var seen: Set<String> = [app.url.path]
        for url in candidates {
            let path = url.standardizedFileURL.path
            guard !seen.contains(path), fm.fileExists(atPath: path) else { continue }
            seen.insert(path)
            let relative = url.path.replacingOccurrences(of: library.path + "/", with: "")
            let group = relative.components(separatedBy: "/").first ?? "Library"
            items.append(CleanupItem(url: url, name: url.lastPathComponent, group: group,
                                     size: size(of: url), preselected: true))
        }
        return items
    }

    // MARK: Helpers

    /// Reports a find to the live scan counter and passes it through.
    static func found(_ item: CleanupItem) -> CleanupItem {
        ScanProgress.shared.add(item)
        return item
    }

    /// Keeps groups in first-seen order, biggest items first inside each group.
    static func sortedByGroup(_ items: [CleanupItem]) -> [CleanupItem] {
        var order: [String] = []
        for item in items where !order.contains(item.group) { order.append(item.group) }
        return order.flatMap { group in
            items.filter { $0.group == group }.sorted { $0.size > $1.size }
        }
    }
}

/// Live numbers for the scan animation. Written from scanner threads, read by the UI a few
/// times per second.
final class ScanProgress: @unchecked Sendable {
    static let shared = ScanProgress()
    /// Set for scans nobody watches (the weekly check), so they never add to the counter of a scan on screen.
    @TaskLocal static var quiet = false

    private let lock = NSLock()
    private var bytes: Int64 = 0
    private var path = ""
    private var visits = 0

    func reset() {
        lock.lock(); defer { lock.unlock() }
        bytes = 0; path = ""; visits = 0
    }

    func add(_ item: CleanupItem) {
        guard !Self.quiet else { return }
        lock.lock(); defer { lock.unlock() }
        bytes += item.size
        path = item.displayPath
    }

    /// Called for every file the scanners look at; only every 40th updates the shown path.
    func visit(_ url: URL) {
        guard !Self.quiet else { return }
        lock.lock(); defer { lock.unlock() }
        visits += 1
        if visits % 40 == 0 {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let p = url.path
            path = p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
        }
    }

    var snapshot: (bytes: Int64, path: String) {
        lock.lock(); defer { lock.unlock() }
        return (bytes, path)
    }
}
