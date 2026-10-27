import SwiftUI
import AppKit
import CryptoKit

/// Checks that an update really comes from Fussel's own build: every release installer is signed on
/// GitHub with a private key, and only a file with a matching signature gets installed.
enum UpdateSignature {
    /// The public half of the signing key (Ed25519). The private half lives only in the repo's secrets.
    static let publicKey = "GqWfBfpXrEwleWJFBEr0P2UU5u7ipEkXSSCdUa3zZHU="

    static func isValid(_ data: Data, signature: String, publicKey: String = publicKey) -> Bool {
        guard let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let signatureData = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        return key.isValidSignature(signatureData, for: data)
    }
}

/// Compares "1.2.10" with "1.2.9" the way people expect. Ignores a leading "v" and any "-beta" suffix.
enum VersionCompare {
    static func parts(_ version: String) -> [Int] {
        var text = version.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        let core = text.split(whereSeparator: { $0 == "-" || $0 == " " || $0 == "+" }).first.map(String.init) ?? text
        return core.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// Keeps Fussel itself up to date from its GitHub releases.
/// Downloads the installer package, checks its signature and only then installs it in the background,
/// after one password prompt from macOS. The package quits this Fussel and starts the new one.
@Observable
@MainActor
final class FusselUpdater {
    nonisolated static let owner = "Dshamil"
    nonisolated static let repo = "fussel"
    static let autoKey = "autoCheckUpdates"
    private static let lastCheckKey = "lastUpdateCheck"

    struct Release: Equatable {
        let version: String
        let page: URL
        let installer: URL?
        /// The installer's signature, published next to it as `<installer>.sig`.
        let signature: URL?
    }

    enum State: Equatable {
        case idle, checking, upToDate
        case available(Release)
        case downloading
        case installing
        case failed(String)
    }

    var state: State = .idle
    /// The newest release found, kept while it downloads and installs.
    private(set) var release: Release?
    /// A short note after an update didn't go through, e.g. when the password prompt was cancelled.
    var note: String?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var availableRelease: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    static var autoCheck: Bool {
        UserDefaults.standard.object(forKey: autoKey) as? Bool ?? true
    }

    /// Called at launch and every few hours; checks at most once a day.
    func checkIfDue() async {
        guard Self.autoCheck else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 24 * 3600 else { return }
        await check(quietly: true)
    }

    func check(quietly: Bool = false) async {
        if state == .downloading || state == .installing { return }
        state = .checking
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        let current = currentVersion
        let result = await Task.detached(priority: .utility) { () -> Result<Release?, UpdateError> in
            await Self.fetchLatest(newerThan: current)
        }.value
        switch result {
        case .success(let found?):
            release = found
            state = .available(found)
        case .success(nil):
            state = quietly ? .idle : .upToDate
        case .failure(let error):
            state = quietly ? .idle : .failed(error.message)
        }
    }

    func install() async {
        guard let release = availableRelease else { return }
        guard let installerURL = release.installer, let signatureURL = release.signature else {
            // No signed installer: let people download it themselves from the release page.
            NSWorkspace.shared.open(release.page)
            return
        }
        state = .downloading
        do {
            let (temp, response) = try await URLSession.shared.download(from: installerURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                state = .failed("The download didn't work. Try again in a moment.")
                return
            }
            let (signatureData, signatureResponse) = try await URLSession.shared.data(from: signatureURL)
            let signature = String(decoding: signatureData, as: UTF8.self)
            let package = try Data(contentsOf: temp)
            guard (signatureResponse as? HTTPURLResponse)?.statusCode == 200,
                  UpdateSignature.isValid(package, signature: signature) else {
                try? FileManager.default.removeItem(at: temp)
                state = .failed("This update couldn't be verified, so Fussel won't install it.")
                return
            }
            let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("app.fussel.Fussel/Updates", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent("Fussel-\(release.version)-Installer.pkg")
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: temp, to: target)
            // The fingerprint of exactly the bytes that passed the check. The file waits in a folder
            // other programs of this user could reach, so it's compared again before anything installs it.
            let fingerprint = Self.sha256(package)
            state = .installing
            note = nil
            switch Self.installInBackground(target, sha256: fingerprint) {
            case .started:
                // The package quits this Fussel (preinstall) and starts the new one (postinstall).
                // If that hasn't happened after two minutes, the quiet route didn't work: show the
                // regular installer instead of waiting forever.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(120))
                    guard let self, self.state == .installing else { return }
                    self.state = .available(release)
                    self.note = "The update didn't finish on its own, so the installer opened instead."
                    self.openInstaller(target, sha256: fingerprint)
                }
            case .cancelled:
                state = .available(release)
                note = "The update was cancelled. Click Update Now to try again."
            case .changed:
                state = .failed("The update changed after it was checked, so Fussel won't install it.")
            case .failed:
                // Something odd with the quiet route: fall back to the regular installer window.
                openInstaller(target, sha256: fingerprint)
            }
        } catch {
            state = .failed("The download didn't work: \(error.localizedDescription)")
        }
    }

    enum InstallStart { case started, cancelled, changed, failed }

    /// Opens the regular installer window, but only for the very file that was checked.
    private func openInstaller(_ package: URL, sha256: String) {
        guard let data = try? Data(contentsOf: package), Self.sha256(data) == sha256 else {
            state = .failed("The update changed after it was checked, so Fussel won't install it.")
            return
        }
        NSWorkspace.shared.open(package)
    }

    nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The shell command that runs as administrator. It copies the package into a fresh folder only the
    /// administrator can reach, installs it only if the copy still has the checked fingerprint (else it
    /// stops with code 3), and leaves no files in shared places like /tmp, where another program could
    /// have laid a trap for a file written with administrator rights.
    nonisolated static func installCommand(package: String, sha256: String) -> String {
        let quoted = "'" + package.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "D=$(/usr/bin/mktemp -d) && /bin/cp \(quoted) \"$D/update.pkg\" && "
            + "[ \"$(/usr/bin/shasum -a 256 \"$D/update.pkg\" | /usr/bin/cut -d ' ' -f 1)\" = \(sha256) ] "
            + "|| { /bin/rm -rf \"$D\"; exit 3; }; "
            + "(/usr/sbin/installer -pkg \"$D/update.pkg\" -target /; /bin/rm -rf \"$D\") > /dev/null 2>&1 &"
    }

    /// Runs macOS's `installer` for the package with administrator rights, so the update goes in
    /// without clicking through the installer window. macOS asks for the password itself; Fussel never
    /// sees it. The install runs in the background, because the package quits this very app halfway
    /// through. (No `nohup`: launched this way it refuses with "can't detach from console".)
    private static func installInBackground(_ package: URL, sha256: String) -> InstallStart {
        let command = installCommand(package: package.path, sha256: sha256)
            .replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(command)\" with administrator privileges "
            + "with prompt \"Fussel wants to install its update.\""
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        guard let error else { return .started }
        switch error[NSAppleScript.errorNumber] as? Int {
        case -128: return .cancelled  // "User canceled"
        case 3: return .changed
        default: return .failed
        }
    }

    // MARK: GitHub

    struct UpdateError: Error {
        let message: String
    }

    nonisolated private static func fetchLatest(newerThan current: String) async -> Result<Release?, UpdateError> {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=15") else {
            return .failure(UpdateError(message: "Invalid update address."))
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Fussel/\(current)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 {
                return .failure(UpdateError(message: "Updates can be checked once Fussel's GitHub page is public."))
            }
            guard status == 200,
                  let releases = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return .failure(UpdateError(message: "GitHub didn't answer as expected (\(status))."))
            }
            var best: Release?
            for entry in releases {
                guard (entry["draft"] as? Bool) != true,
                      let tag = entry["tag_name"] as? String,
                      let pageString = entry["html_url"] as? String,
                      let page = URL(string: pageString) else { continue }
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let assets = entry["assets"] as? [[String: Any]] ?? []
                func asset(_ suffix: String) -> URL? {
                    assets.first { ($0["name"] as? String)?.hasSuffix(suffix) == true }
                        .flatMap { $0["browser_download_url"] as? String }
                        .flatMap(URL.init(string:))
                }
                if VersionCompare.isNewer(version, than: best?.version ?? current) {
                    best = Release(version: version, page: page, installer: asset(".pkg"), signature: asset(".pkg.sig"))
                }
            }
            return .success(best)
        } catch {
            return .failure(UpdateError(message: "Couldn't reach GitHub: \(error.localizedDescription)"))
        }
    }
}

/// A slim banner at the top of the main window when a new Fussel is ready.
struct UpdateBanner: View {
    let updater: FusselUpdater
    @Environment(\.palette) private var palette
    @State private var dismissed = false

    var body: some View {
        if !dismissed, let release = shownRelease {
            HStack(spacing: 10) {
                Image(systemName: "gift.fill")
                    .foregroundStyle(palette.text)
                    .symbolEffect(.bounce, value: release.version)
                Text(title(release))
                    .font(.rounded(13, .bold))
                    .foregroundStyle(palette.text)
                Spacer()
                if updater.state == .downloading || updater.state == .installing {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Later") { withAnimation { dismissed = true } }
                        .buttonStyle(.plain)
                        .font(.rounded(12, .semibold))
                        .foregroundStyle(palette.secondary)
                    Button("Update Now") { Task { await updater.install() } }
                        .buttonStyle(ActionButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.card))
            .overlay(Capsule().strokeBorder(palette.cardStroke, lineWidth: 1))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var shownRelease: FusselUpdater.Release? {
        switch updater.state {
        case .available, .downloading, .installing: return updater.release
        default: return nil
        }
    }

    private func title(_ release: FusselUpdater.Release) -> String {
        switch updater.state {
        case .downloading: return "Downloading Fussel \(release.version)…"
        case .installing: return "Installing… Fussel restarts in a moment"
        default: return "Fussel \(release.version) is here!"
        }
    }
}
