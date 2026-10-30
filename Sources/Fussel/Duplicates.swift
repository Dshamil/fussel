import Foundation
import CryptoKit

extension Scanner {
    /// Groups of copies are named "Copies of <file name>".
    static let duplicatesPrefix = "Copies of "

    /// Where duplicates are looked for: the user's own folders, nothing in Library.
    static var duplicateFolders: [URL] {
        ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"].map { home.appendingPathComponent($0) }
    }

    /// Files of 1 MB or more with exactly the same content. In each set the oldest copy stays and is
    /// not listed; the others are. Copies in Downloads are safe to remove, all others need a look first.
    /// Packages are never opened, so nothing inside a Photos or Music library is ever touched.
    static func scanDuplicates(in folders: [URL] = duplicateFolders,
                               downloads: URL = home.appendingPathComponent("Downloads"),
                               minSize: Int64 = 1_000_000) -> [CleanupItem] {
        findDuplicates(in: folders, downloads: downloads, minSize: minSize).items
    }

    /// The copies to list, and per group the copy that stays (the oldest), to show it and let you pick another.
    static func findDuplicates(in folders: [URL] = duplicateFolders,
                               downloads: URL = home.appendingPathComponent("Downloads"),
                               minSize: Int64 = 1_000_000) -> (items: [CleanupItem], kept: [String: CleanupItem]) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                                      .creationDateKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        struct File { let url: URL; let size: Int64; let bytes: Int64; let created: Date; let modified: Date }

        // 1. Every big enough file, by size. Hard links to one file count once: removing one frees nothing.
        var bySize: [Int64: [File]] = [:]
        var seen = Set<NSObject>()
        for folder in folders {
            guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                 options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                 errorHandler: { _, _ in true }) else { continue }
            while let url = enumerator.nextObject() as? URL {
                ScanProgress.shared.visit(url)
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isPackage != true,
                      v.isRegularFile == true, let size = v.fileSize, Int64(size) >= minSize else { continue }
                if let id = v.fileResourceIdentifier as? NSObject {
                    guard seen.insert(id).inserted else { continue }
                }
                bySize[Int64(size), default: []].append(
                    File(url: url, size: Int64(size), bytes: Int64(v.totalFileAllocatedSize ?? size),
                         created: v.creationDate ?? .distantFuture, modified: v.contentModificationDate ?? .distantPast))
            }
        }

        // 2. Same size, then same start and end, then the same whole content. Each step only reads the
        //    files still in the running, several at once.
        var candidates = bySize.values.filter { $0.count > 1 }
        for part in [Part.ends, Part.all] {
            let files = candidates.flatMap { $0 }
            let prints = fingerprints(files.map { ($0.url, $0.size, $0.modified) }, part)
            var byPrint: [String: [File]] = [:]
            for (file, print) in zip(files, prints) { byPrint["\(file.size)-\(print)", default: []].append(file) }
            candidates = byPrint.values.filter { $0.count > 1 }
        }
        let sets = candidates

        // 3. Keep the oldest of each set; list the rest under one group per set.
        let downloadsPath = downloads.standardizedFileURL.path.lowercased() + "/"
        var items: [CleanupItem] = []
        var kept: [String: CleanupItem] = [:]
        var names = Set<String>()
        for set in sets.sorted(by: { $0[0].size * Int64($0.count) > $1[0].size * Int64($1.count) }) {
            let ordered = set.sorted { ($0.created, $0.url.path) < ($1.created, $1.url.path) }
            var group = duplicatesPrefix + ordered[0].url.lastPathComponent
            var n = 2
            while names.contains(group) { group = duplicatesPrefix + ordered[0].url.lastPathComponent + " (\(n))"; n += 1 }
            names.insert(group)
            let original = ordered[0]
            kept[group] = CleanupItem(url: original.url, name: original.url.lastPathComponent, group: group,
                                      size: original.bytes, date: original.created)
            for copy in ordered.dropFirst() {
                let inDownloads = copy.url.standardizedFileURL.path.lowercased().hasPrefix(downloadsPath)
                items.append(found(CleanupItem(url: copy.url, name: copy.url.lastPathComponent, group: group,
                                               size: copy.bytes, date: copy.created, preselected: inDownloads)))
            }
            if items.count >= 2000 { break }
        }
        return (items, kept)
    }

    enum Part { case ends, all }

    /// Fingerprints from earlier scans, for files that haven't changed since (same size, same date).
    /// Fussel keeps running in the menu bar, so every scan after the first reads only what's new.
    private nonisolated(unsafe) static var remembered: [String: String] = [:]
    private static let lock = NSLock()

    /// The fingerprints of many files, worked out in parallel (an SSD reads several files at once just fine).
    static func fingerprints(_ files: [(url: URL, size: Int64, modified: Date)], _ part: Part) -> [String] {
        var results = [String](repeating: "", count: files.count)
        DispatchQueue.concurrentPerform(iterations: files.count) { i in
            let file = files[i]
            let key = "\(part)|\(file.size)|\(file.modified.timeIntervalSinceReferenceDate)|\(file.url.path)"
            if let known = lock.withLock({ remembered[key] }) {
                lock.withLock { results[i] = known }
                return
            }
            // An unreadable file gets a value of its own, so it never matches anything, and isn't remembered.
            let print = fingerprint(file.url, part)
            lock.withLock {
                results[i] = print ?? UUID().uuidString
                if let print { remembered[key] = print }
            }
        }
        return results
    }

    /// A SHA-256 of the file's first and last 64 KB, or of all of it; nil if it can't be read.
    static func fingerprint(_ url: URL, _ part: Part) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        func read(_ count: Int) -> Int {
            var left = count, done = 0
            while left > 0 {
                let chunk = autoreleasepool { try? handle.read(upToCount: min(left, 4 << 20)) }
                guard let chunk, !chunk.isEmpty else { break }
                hasher.update(data: chunk)
                left -= chunk.count
                done += chunk.count
            }
            return done
        }
        switch part {
        case .ends:
            let edge = 64 * 1024
            _ = read(edge)
            if let end = try? handle.seekToEnd(), end > UInt64(2 * edge) {
                try? handle.seek(toOffset: end - UInt64(edge))
                _ = read(edge)
            }
        case .all:
            _ = read(Int.max)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
