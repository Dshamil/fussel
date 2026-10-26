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
}
