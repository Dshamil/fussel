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
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                                      .creationDateKey, .fileResourceIdentifierKey]
        struct File { let url: URL; let size: Int64; let bytes: Int64; let created: Date }

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
                         created: v.creationDate ?? .distantFuture))
            }
        }

        // 2. Same size, then same start, then the same whole content.
        var sets: [[File]] = []
        for files in bySize.values where files.count > 1 {
            for sameStart in Dictionary(grouping: files, by: { fingerprint($0.url, limit: 64 * 1024) }).values
            where sameStart.count > 1 {
                for same in Dictionary(grouping: sameStart, by: { fingerprint($0.url, limit: nil) }).values
                where same.count > 1 {
                    sets.append(same)
                }
            }
        }

        // 3. Keep the oldest of each set; list the rest under one group per set.
        let downloadsPath = downloads.standardizedFileURL.path.lowercased() + "/"
        var items: [CleanupItem] = []
        var names = Set<String>()
        for set in sets.sorted(by: { $0[0].size * Int64($0.count) > $1[0].size * Int64($1.count) }) {
            let ordered = set.sorted { ($0.created, $0.url.path) < ($1.created, $1.url.path) }
            var group = duplicatesPrefix + ordered[0].url.lastPathComponent
            var n = 2
            while names.contains(group) { group = duplicatesPrefix + ordered[0].url.lastPathComponent + " (\(n))"; n += 1 }
            names.insert(group)
            for copy in ordered.dropFirst() {
                let inDownloads = copy.url.standardizedFileURL.path.lowercased().hasPrefix(downloadsPath)
                items.append(found(CleanupItem(url: copy.url, name: copy.url.lastPathComponent, group: group,
                                               size: copy.bytes, date: copy.created, preselected: inDownloads)))
            }
            if items.count >= 2000 { break }
        }
        return items
    }

    /// A SHA-256 of the file's first `limit` bytes, or of all of it. Unreadable files get a unique value,
    /// so they never match anything.
    static func fingerprint(_ url: URL, limit: Int?) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return UUID().uuidString }
        defer { try? handle.close() }
        var hasher = SHA256()
        var left = limit ?? Int.max
        while left > 0 {
            let chunk = autoreleasepool { try? handle.read(upToCount: min(left, 1 << 20)) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            left -= chunk.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
