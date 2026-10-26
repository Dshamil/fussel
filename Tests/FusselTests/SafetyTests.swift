import XCTest
import CryptoKit
@testable import Fussel

/// The rules that decide what may be deleted and whether an update is newer.
final class SafetyTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    func testProtectedFoldersAreNeverRemoved() {
        for path in ["Documents", "Desktop", "Downloads", "Pictures", "Library", "Library/Caches",
                     "Library/Application Support", "Library/Containers", ".Trash", ""] {
            XCTAssertFalse(Cleaner.isSafeToRemove(home.appendingPathComponent(path)), path)
        }
        XCTAssertFalse(Cleaner.isSafeToRemove(URL(fileURLWithPath: "/")))
        XCTAssertFalse(Cleaner.isSafeToRemove(URL(fileURLWithPath: "/Applications")))
        XCTAssertFalse(Cleaner.isSafeToRemove(URL(fileURLWithPath: "/System/Library")))
        XCTAssertFalse(Cleaner.isSafeToRemove(URL(fileURLWithPath: "/Applications/Notes.txt")))
        // "/Documents/.." must not sneak past the check.
        XCTAssertFalse(Cleaner.isSafeToRemove(home.appendingPathComponent("Documents/..")))
    }

    func testThingsInsideAreAllowed() {
        XCTAssertTrue(Cleaner.isSafeToRemove(home.appendingPathComponent("Library/Caches/com.example.app")))
        XCTAssertTrue(Cleaner.isSafeToRemove(home.appendingPathComponent("Downloads/old.dmg")))
        XCTAssertTrue(Cleaner.isSafeToRemove(URL(fileURLWithPath: "/Applications/Example.app")))
    }

    func testUpdateSignature() {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let installer = Data("pretend installer".utf8)
        let signature = try! key.signature(for: installer).base64EncodedString()
        XCTAssertTrue(UpdateSignature.isValid(installer, signature: signature, publicKey: publicKey))
        // A changed file, a wrong signature or another key must all be refused.
        XCTAssertFalse(UpdateSignature.isValid(Data("tampered".utf8), signature: signature, publicKey: publicKey))
        XCTAssertFalse(UpdateSignature.isValid(installer, signature: "bm9wZQ==", publicKey: publicKey))
        XCTAssertFalse(UpdateSignature.isValid(installer, signature: signature))
        XCTAssertFalse(UpdateSignature.isValid(installer, signature: ""))
    }

    func testVersionCompare() {
        XCTAssertTrue(VersionCompare.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertTrue(VersionCompare.isNewer("v1.2.1", than: "1.2"))
        XCTAssertTrue(VersionCompare.isNewer("2.0-beta", than: "1.9.9"))
        XCTAssertFalse(VersionCompare.isNewer("1.2.0", than: "1.2"))
        XCTAssertFalse(VersionCompare.isNewer("0.8.0", than: "0.8.1"))
    }

    func testAppcastPicksNewestEntry() {
        let feed = """
        <?xml version="1.0"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
          <item><enclosure url="https://example.com/a.zip" sparkle:version="90" sparkle:shortVersionString="1.9"/></item>
          <item><enclosure url="https://example.com/b.zip" sparkle:version="100" sparkle:shortVersionString="1.10"/></item>
        </channel></rss>
        """
        let newest = AppcastParser(data: Data(feed.utf8)).newest()
        XCTAssertEqual(newest?.shortVersion, "1.10")
        XCTAssertEqual(newest?.download, URL(string: "https://example.com/b.zip"))
    }
}
