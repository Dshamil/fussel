import XCTest
@testable import Fussel

/// What Fussel may remove, what it must never touch, and that Undo really brings things back.
/// Every file these tests create lives in a fresh folder of its own and is gone again afterwards.
final class CleaningTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let fm = FileManager.default

    // MARK: The last line of defence

    func testUpperAndLowerCaseMakeNoDifference() {
        // The Mac's disk treats "documents" and "Documents" as the same folder.
        for path in ["documents", "DESKTOP", "downloads", "library", "library/caches", "LIBRARY/Application Support"] {
            XCTAssertFalse(Cleaner.isSafeToRemove(home.appendingPathComponent(path)), path)
        }
        XCTAssertFalse(Cleaner.isSafeToRemove(URL(fileURLWithPath: "/APPLICATIONS")))
    }

    func testPathTricksDontSlipThrough() {
        XCTAssertFalse(Cleaner.isSafeToRemove(home.appendingPathComponent("Library/Caches/../../Documents")))
        XCTAssertFalse(Cleaner.isSafeToRemove(URL(fileURLWithPath: home.path + "/Documents/", isDirectory: true)))
        XCTAssertFalse(Cleaner.isSafeToRemove(URL(fileURLWithPath: "/Applications/../etc")))
        XCTAssertFalse(Cleaner.isSafeToRemove(URL(fileURLWithPath: "/Applications/Example.app/../../etc")))
        XCTAssertFalse(Cleaner.isSafeToRemove(URL(fileURLWithPath: "/Users")))
        XCTAssertFalse(Cleaner.isSafeToRemove(URL(fileURLWithPath: "/usr/bin/true")))
        XCTAssertFalse(Cleaner.isSafeToRemove(URL(fileURLWithPath: "/System/Applications/Notes.app")))
    }

    func testCloudMailAndSharedFoldersAreKept() {
        for path in ["Public", "Library/Mobile Documents", "Library/CloudStorage", "Library/Mail", "Library/Messages",
                     "Library/Preferences", "Library/LaunchAgents", "Library/Group Containers"] {
            XCTAssertFalse(Cleaner.isSafeToRemove(home.appendingPathComponent(path)), path)
        }
    }

    func testPasswordsAndKeysAreNeverTouched() {
        for path in ["Library/Keychains", "Library/Keychains/login.keychain-db", ".ssh", ".ssh/id_ed25519",
                     ".gnupg/private-keys-v1.d", "library/KEYCHAINS/login.keychain-db"] {
            XCTAssertFalse(Cleaner.isSafeToRemove(home.appendingPathComponent(path)), path)
        }
    }

    func testOwnFoldersInTheHomeFolderAreKeptButFilesMayGo() throws {
        let folder = home.appendingPathComponent("FusselTest-\(UUID().uuidString)")
        let file = home.appendingPathComponent("FusselTest-\(UUID().uuidString).txt")
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("test".utf8).write(to: file)
        defer {
            try? fm.removeItem(at: folder)
            try? fm.removeItem(at: file)
        }
        // A folder like ~/Projects is the user's own, never removed as a whole.
        XCTAssertFalse(Cleaner.isSafeToRemove(folder))
        // Something inside it, or a big file lying right in the home folder, may be suggested.
        XCTAssertTrue(Cleaner.isSafeToRemove(folder.appendingPathComponent("old.zip")))
        XCTAssertTrue(Cleaner.isSafeToRemove(file))
    }

    func testOnlyOtherPeoplesAppsMayBeUninstalled() {
        XCTAssertTrue(Cleaner.isSafeToRemove(URL(fileURLWithPath: "/Applications/Example.app")))
        XCTAssertTrue(Cleaner.isSafeToRemove(URL(fileURLWithPath: "/Applications/Some Suite/Example.app")))
        // Not an app inside an app, not a loose file, not deeper folders.
        XCTAssertFalse(Cleaner.isSafeToRemove(URL(fileURLWithPath: "/Applications/Example.app/Contents/Helper.app")))
        XCTAssertFalse(Cleaner.isSafeToRemove(URL(fileURLWithPath: "/Applications/Example.dmg")))
        // Apple's own apps stay, even when they sit in /Applications.
        for app in ["Safari", "Pages", "Numbers", "Keynote", "iMovie", "GarageBand", "Xcode"] {
            let url = URL(fileURLWithPath: "/Applications/\(app).app")
            guard fm.fileExists(atPath: url.path) else { continue }
            XCTAssertFalse(Cleaner.isSafeToRemove(url), app)
        }
    }

    func testCleanerSkipsWhatTheRuleRefuses() {
        let item = CleanupItem(url: URL(fileURLWithPath: "/usr/bin/true"), name: "true", group: "Test", size: 1)
        let result = Cleaner.clean([item])
        XCTAssertEqual(result.freed, 0)
        XCTAssertTrue(result.trashed.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: "/usr/bin/true"))
    }

    // MARK: Undo

    /// A fresh folder in the caches, where Fussel is allowed to clean, removed again afterwards.
    private func scratchFolder() throws -> URL {
        let folder = home.appendingPathComponent("Library/Caches/FusselTests-\(UUID().uuidString)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    func testCleanedFilesGoToTheTrashAndUndoBringsThemBack() throws {
        let folder = try scratchFolder()
        let file = folder.appendingPathComponent("cache.bin")
        try Data("keep me".utf8).write(to: file)

        let result = Cleaner.clean([CleanupItem(url: file, name: "cache.bin", group: "App Caches", size: 7)])
        XCTAssertTrue(result.failures.isEmpty, "\(result.failures)")
        XCTAssertEqual(result.freed, 7)
        XCTAssertFalse(fm.fileExists(atPath: file.path), "the file should be gone from its place")
        let trashed = try XCTUnwrap(result.trashed.first)
        addTeardownBlock { try? FileManager.default.removeItem(at: trashed.trashed) }
        XCTAssertTrue(fm.fileExists(atPath: trashed.trashed.path), "the file should be in the Trash, not deleted")

        let outcome = CleanHistory.restore(result.trashed)
        XCTAssertEqual(outcome.restored, 1)
        XCTAssertTrue(outcome.failed.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), Data("keep me".utf8))
    }

    func testUndoNeverOverwritesSomethingNew() throws {
        let folder = try scratchFolder()
        let file = folder.appendingPathComponent("notes.txt")
        try Data("old".utf8).write(to: file)
        let result = Cleaner.clean([CleanupItem(url: file, name: "notes.txt", group: "Test", size: 3)])
        let trashed = try XCTUnwrap(result.trashed.first)
        addTeardownBlock { try? FileManager.default.removeItem(at: trashed.trashed) }

        // Something new appears where the old file was.
        try Data("new".utf8).write(to: file)
        let outcome = CleanHistory.restore(result.trashed)
        XCTAssertEqual(outcome.restored, 0)
        XCTAssertEqual(outcome.failed.count, 1)
        XCTAssertEqual(try Data(contentsOf: file), Data("new".utf8), "the new file must stay untouched")
        XCTAssertTrue(fm.fileExists(atPath: trashed.trashed.path), "the old one waits in the Trash")
    }

    func testUndoSaysSoWhenTheTrashWasEmptied() throws {
        let folder = try scratchFolder()
        let gone = TrashedItem(name: "gone", original: folder.appendingPathComponent("gone"),
                               trashed: folder.appendingPathComponent("not-in-trash"), size: 1)
        let outcome = CleanHistory.restore([gone])
        XCTAssertEqual(outcome.restored, 0)
        XCTAssertEqual(outcome.failed.count, 1)
    }

    // MARK: What the scanners suggest

    func testTheWeeklyCheckNeverAddsToTheLiveCounter() {
        let item = CleanupItem(url: home.appendingPathComponent("Library/Caches/x"), name: "x", group: "App Caches", size: 500)
        ScanProgress.shared.reset()
        ScanProgress.$quiet.withValue(true) { _ = Scanner.found(item) }
        XCTAssertEqual(ScanProgress.shared.snapshot.bytes, 0, "a background check must stay out of the scan on screen")
        _ = Scanner.found(item)
        XCTAssertEqual(ScanProgress.shared.snapshot.bytes, 500)
        ScanProgress.shared.reset()
    }

    func testSystemJunkOnlySuggestsWhatTheRuleAllows() {
        // Reads ~/Library/Caches and ~/Library/Logs only; nothing is changed.
        for item in Scanner.scanJunk() {
            XCTAssertTrue(Cleaner.isSafeToRemove(item.url), item.url.path)
            XCTAssertFalse(item.permanent, "junk always goes to the Trash first: \(item.url.path)")
            if item.group == "Developer" && item.name != "Xcode Derived Data" {
                XCTAssertFalse(item.preselected, "\(item.name) should wait for a decision")
            }
        }
    }

    /// Caches inside an app's container: only their contents, never the folder itself, never Apple's.
    func testContainerCachesStayInsideTheirCachesFolder() {
        for item in Scanner.scanJunk() where item.url.path.contains("/Library/Containers/") {
            let parts = item.url.pathComponents
            guard let at = parts.firstIndex(of: "Containers"), at + 1 < parts.count else { continue }
            if item.group == "App Caches" {
                XCTAssertFalse(parts[at + 1].hasPrefix("com.apple."), item.url.path)
                XCTAssertEqual(item.url.deletingLastPathComponent().lastPathComponent, "Caches", item.url.path)
                XCTAssertTrue(item.preselected, item.url.path)
            }
        }
    }

    /// A folder on the way that is really a redirect (symlink) to somewhere else: Fussel would judge the
    /// harmless-looking path but move the real file elsewhere, so such paths are refused outright.
    func testAPathThroughARedirectedFolderIsRefused() throws {
        let folder = try scratchFolder()
        let elsewhere = folder.appendingPathComponent("elsewhere")
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try Data("not a cache".utf8).write(to: elsewhere.appendingPathComponent("file.bin"))
        let redirect = folder.appendingPathComponent("Caches")
        try fm.createSymbolicLink(at: redirect, withDestinationURL: elsewhere)
        let throughRedirect = redirect.appendingPathComponent("file.bin")
        XCTAssertFalse(Cleaner.isSafeToRemove(throughRedirect), "a path through a symlinked folder")
        // The redirect itself may still go: trashing a link leaves its target alone.
        XCTAssertTrue(Cleaner.isSafeToRemove(redirect))
        let result = Cleaner.clean([CleanupItem(url: throughRedirect, name: "file", group: "App Caches", size: 11)])
        XCTAssertTrue(result.trashed.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: elsewhere.appendingPathComponent("file.bin").path))
    }

    /// Emptying the Trash ends Undo for earlier clean-ups: the prompt says so, with how many.
    func testTheEmptyTrashPromptCountsWhatUndoLoses() {
        let trash = home.appendingPathComponent(".Trash")
        let mine = trash.appendingPathComponent("old cache")
        let other = trash.appendingPathComponent("someone else's file")
        let record = CleanRecord(date: Date(), source: "System Junk", freed: 10, itemCount: 1,
                                 trashed: [TrashedItem(name: "old cache", original: home.appendingPathComponent("Library/Caches/x"), trashed: mine, size: 10)])
        let items = [CleanupItem(url: mine, name: "old cache", group: "Trash", size: 10, permanent: true),
                     CleanupItem(url: other, name: "other", group: "Trash", size: 5, permanent: true)]
        let note = CleanHistory.permanentNote(for: items, records: [record])
        XCTAssertTrue(note.contains("1 item from an earlier Fussel clean-up"), note)
        XCTAssertTrue(note.contains("Undo can't bring it back"), note)
        // Already undone or none of Fussel's: just the usual sentence.
        var undone = record; undone.undone = true
        XCTAssertFalse(CleanHistory.permanentNote(for: items, records: [undone]).contains("Undo"))
        XCTAssertFalse(CleanHistory.permanentNote(for: [items[1]], records: [record]).contains("Undo"))
    }

    /// Undo only brings back what is really in the Trash, and only to a place Fussel may clean,
    /// even if someone wrote a fake entry into the history file.
    func testUndoRefusesAForgedEntry() throws {
        let folder = try scratchFolder()
        let notInTrash = folder.appendingPathComponent("private.txt")
        try Data("stay here".utf8).write(to: notInTrash)
        let forged = TrashedItem(name: "forged", original: folder.appendingPathComponent("moved.txt"), trashed: notInTrash, size: 9)
        let (restored, failed) = CleanHistory.restore([forged])
        XCTAssertEqual(restored, 0)
        XCTAssertEqual(failed.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: notInTrash.path), "the file outside the Trash stays where it is")
        XCTAssertFalse(fm.fileExists(atPath: folder.appendingPathComponent("moved.txt").path))
    }

    func testUndoNeverRestoresIntoAProtectedPlace() throws {
        let folder = try scratchFolder()
        let file = folder.appendingPathComponent("cache.bin")
        try Data("x".utf8).write(to: file)
        var trashed: NSURL?
        try fm.trashItem(at: file, resultingItemURL: &trashed)
        let inTrash = try XCTUnwrap(trashed as URL?)
        defer { try? fm.removeItem(at: inTrash) }
        let target = home.appendingPathComponent(".ssh/fussel-test-\(UUID().uuidString)")
        let (restored, _) = CleanHistory.restore([TrashedItem(name: "x", original: target, trashed: inTrash, size: 1)])
        XCTAssertEqual(restored, 0)
        XCTAssertFalse(fm.fileExists(atPath: target.path))
    }

    // MARK: Leftovers of removed apps

    /// Makes a folder in Application Support that looks like a removed app's leftover, last changed
    /// `daysAgo` days ago.
    private func fakeLeftover(_ id: String, daysAgo: Double) throws -> URL {
        let dir = home.appendingPathComponent("Library/Application Support/\(id)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("data.bin")
        try Data(repeating: 7, count: 4096).write(to: file)
        let then = Date().addingTimeInterval(-daysAgo * 86_400)
        try fm.setAttributes([.modificationDate: then], ofItemAtPath: file.path)
        try fm.setAttributes([.modificationDate: then], ofItemAtPath: dir.path)
        return dir
    }

    func testLeftoversOfARemovedAppAreFoundButNeverPreselected() throws {
        let vendor = "com.zqxleftover\(UUID().uuidString.prefix(8).lowercased())"
        let old = try fakeLeftover("\(vendor).oldapp", daysAgo: 60)
        defer { try? fm.removeItem(at: old) }
        let found = Scanner.scanJunk().first { $0.url.standardizedFileURL.path == old.standardizedFileURL.path }
        XCTAssertNotNil(found, "a two-month-old leftover of an app that's gone should be offered")
        XCTAssertEqual(found?.preselected, false, "leftovers always wait for a look")
        XCTAssertEqual(found.map { Cleaner.isSafeToRemove($0.url) }, true)
    }

    func testRecentAppleOrStillInstalledVendorsAreNoLeftovers() throws {
        let vendor = "com.zqxleftover\(UUID().uuidString.prefix(8).lowercased())"
        var made = [try fakeLeftover("\(vendor).recentapp", daysAgo: 2),
                    try fakeLeftover("com.apple.fusseltest\(UUID().uuidString.prefix(6).lowercased())", daysAgo: 90)]
        // A support folder of a vendor that still has an app installed belongs to that vendor's tools.
        if let installed = Scanner.appBundles().first(where: { $0.id.split(separator: ".").count >= 2 }) {
            let parts = installed.id.split(separator: ".")
            made.append(try fakeLeftover("\(parts[0]).\(parts[1]).fusseltesthelper", daysAgo: 90))
        }
        defer { made.forEach { try? fm.removeItem(at: $0) } }
        let paths = Set(Scanner.scanJunk().map { $0.url.standardizedFileURL.path })
        for dir in made {
            XCTAssertFalse(paths.contains(dir.standardizedFileURL.path), "not a leftover: \(dir.lastPathComponent)")
        }
    }

    /// A background agent only counts as left over when its program is surely gone.
    func testAnAgentWhoseProgramMightStillExistIsKept() throws {
        let dir = fm.temporaryDirectory.appendingPathComponent("FusselAgents-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        func agent(_ program: Any) throws -> URL {
            let url = dir.appendingPathComponent("\(UUID().uuidString).plist")
            let key = program is [String] ? "ProgramArguments" : "Program"
            try PropertyListSerialization.data(fromPropertyList: [key: program], format: .xml, options: 0).write(to: url)
            return url
        }
        XCTAssertTrue(Scanner.programStillThere(agent: try agent("/bin/ls")), "an existing program")
        XCTAssertTrue(Scanner.programStillThere(agent: try agent(["node", "server.js"])), "a bare name found via PATH")
        XCTAssertFalse(Scanner.programStillThere(agent: try agent("/Applications/GoneForGood-\(UUID().uuidString).app/x")))
    }

    // MARK: Uninstaller

    /// An app picks its own name and ID. With "../" in them it must not steer the uninstaller to
    /// files that belong to someone else, here a folder next to the app's caches.
    func testAnAppsNameCantPointTheUninstallerElsewhere() throws {
        let target = home.appendingPathComponent("Library/Caches/FusselTest-\(UUID().uuidString)")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: target) }
        let app = InstalledApp(url: URL(fileURLWithPath: "/Applications/Sneaky.app"),
                               name: "../Caches/\(target.lastPathComponent)",
                               bundleID: "../Caches/\(target.lastPathComponent)")
        let paths = Scanner.leftovers(for: app).map { $0.url.standardizedFileURL.path }
        XCTAssertFalse(paths.contains(target.path), "a crafted name reached \(target.path)")
    }

    func testAnEmptyAppIDDoesntMatchEveryLaunchAgent() {
        let app = InstalledApp(url: URL(fileURLWithPath: "/Applications/Empty.app"), name: "Empty", bundleID: "")
        let others = Scanner.leftovers(for: app).filter { $0.url.path.contains("/LaunchAgents/") }
        XCTAssertTrue(others.isEmpty, "an empty ID offered \(others.map(\.name))")
    }

    // MARK: Duplicates

    /// Photos, Music and iMovie keep their files inside a library that is really a database: removing a
    /// single file from in there breaks it. Nothing inside such a library may ever go, whatever finds it.
    func testNothingInsideAPhotosOrMusicLibraryIsTouched() {
        for path in ["Pictures/Photos Library.photoslibrary",
                     "Pictures/Photos Library.photoslibrary/originals/A/IMG_0001.heic",
                     "pictures/PHOTOS LIBRARY.PHOTOSLIBRARY/originals/A/IMG_0001.heic",
                     "Pictures/iPhoto Library.photolibrary/Masters/2010/IMG_0002.jpg",
                     "Music/Music/Music Library.musiclibrary/Library.musicdb",
                     "Movies/iMovie Library.imovielibrary/Holiday/Original Media/clip.mov",
                     "Movies/Projects.fcpbundle/Event/Original Media/clip.mov"] {
            XCTAssertFalse(Cleaner.isSafeToRemove(home.appendingPathComponent(path)), path)
        }
        // Files next to a library are still the user's to decide about.
        XCTAssertTrue(Cleaner.isSafeToRemove(home.appendingPathComponent("Pictures/IMG_0001 copy.heic")))
    }

    /// The oldest copy always stays and isn't even listed; only copies in Downloads are preselected;
    /// small files and files that only share their size are left alone.
    func testDuplicatesKeepTheOldestCopyAndOnlyPreselectDownloads() throws {
        let root = home.appendingPathComponent("FusselTest-\(UUID().uuidString)")
        let docs = root.appendingPathComponent("Documents"), downloads = root.appendingPathComponent("Downloads")
        try fm.createDirectory(at: docs.appendingPathComponent("Old"), withIntermediateDirectories: true)
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let content = Data((0..<1_200_000).map { UInt8($0 % 251) })
        var other = content
        other[other.count - 1] ^= 0xFF
        let small = Data(repeating: 7, count: 200_000)
        func write(_ data: Data, _ url: URL, daysAgo: Double) throws {
            try data.write(to: url)
            try fm.setAttributes([.creationDate: Date().addingTimeInterval(-daysAgo * 86_400)], ofItemAtPath: url.path)
        }
        try write(content, docs.appendingPathComponent("Old/report.pdf"), daysAgo: 300)    // the original
        try write(content, downloads.appendingPathComponent("report.pdf"), daysAgo: 2)
        try write(content, docs.appendingPathComponent("report copy.pdf"), daysAgo: 30)
        try write(other, docs.appendingPathComponent("almost.pdf"), daysAgo: 10)          // same size, other content
        try write(small, docs.appendingPathComponent("small.txt"), daysAgo: 10)
        try write(small, downloads.appendingPathComponent("small.txt"), daysAgo: 1)

        let found = Scanner.findDuplicates(in: [docs, downloads], downloads: downloads)
        XCTAssertEqual(found.kept["Copies of report.pdf"]?.url.path.contains("/Old/"), true, "the oldest copy stays")
        let items = found.items
        XCTAssertEqual(Set(items.map(\.url.lastPathComponent)), ["report.pdf", "report copy.pdf"])
        XCTAssertFalse(items.contains { $0.url.path.contains("/Old/") }, "the oldest copy must stay")
        XCTAssertEqual(Set(items.map(\.group)), ["Copies of report.pdf"])
        for item in items {
            XCTAssertEqual(item.preselected, item.url.deletingLastPathComponent().lastPathComponent == "Downloads",
                           item.url.path)
            XCTAssertTrue(Cleaner.isSafeToRemove(item.url), item.url.path)
        }
    }

    /// Picking another copy to keep: it leaves the list and the selection, and the copy that stayed so far
    /// comes back unselected. The copy that stays can never be cleaned.
    @MainActor
    func testKeepingAnotherCopySwapsItSafely() async {
        let model = ModuleModel(module: .duplicates)
        let group = "Copies of a.mov"
        let old = CleanupItem(url: home.appendingPathComponent("Movies/a.mov"), name: "a.mov", group: group, size: 5)
        let copy = CleanupItem(url: home.appendingPathComponent("Downloads/a.mov"), name: "a.mov", group: group, size: 5,
                               preselected: true)
        model.items = [copy]
        model.kept = [group: old]
        model.selected = [copy.url]
        model.phase = .results

        model.keep(copy)
        XCTAssertEqual(model.kept[group]?.url, copy.url)
        XCTAssertEqual(model.items.map(\.url), [old.url])
        XCTAssertFalse(model.selected.contains(copy.url), "the copy that stays must not be selected")
        XCTAssertFalse(model.items[0].preselected, "the copy coming back waits for a decision")
        XCTAssertTrue(model.selectedItems.isEmpty)
    }

    // MARK: Self-update

    /// The update runs as administrator, so it must not write to shared places like /tmp, and it must
    /// install exactly the file Fussel checked: copied somewhere only the administrator can reach,
    /// then compared with the checked file's fingerprint.
    func testTheUpdateInstallsOnlyTheCheckedFile() {
        let script = FusselUpdater.installCommand(package: "/Users/me/Library/Caches/it's.pkg", sha256: "abc123")
        XCTAssertFalse(script.contains("/tmp/"), script)
        XCTAssertTrue(script.contains("mktemp -d"), script)
        XCTAssertTrue(script.contains("abc123"), script)
        XCTAssertTrue(script.contains("'/Users/me/Library/Caches/it'\\''s.pkg'"), script)
    }
}
