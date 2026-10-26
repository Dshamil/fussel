import SwiftUI
import AppKit

/// An installed app with a newer version available.
struct AppUpdate: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case appStore(URL)
        case sparkle(download: URL?)
    }

    var id: URL { url }
    let url: URL
    let name: String
    let installed: String
    let available: String
    let source: Source

    var sourceLabel: String {
        switch source {
        case .appStore: return "App Store"
        case .sparkle: return "Developer"
        }
    }
}

/// Finds updates for installed apps:
/// - Mac App Store apps through Apple's public lookup service
/// - apps that update themselves with Sparkle, through their update feed
@Observable
@MainActor
final class AppUpdatesModel {
    enum Phase: Equatable {
        case idle
        case checking(done: Int, total: Int)
        case done(checked: Int)
    }

    var phase: Phase = .idle
    var updates: [AppUpdate] = []

    func check() async {
        updates = []
        let candidates = await Task.detached(priority: .userInitiated) { AppUpdateChecker.candidates() }.value
        phase = .checking(done: 0, total: candidates.count)
        var found: [AppUpdate] = []
        var done = 0
        // Ask a few servers at a time.
        for chunk in stride(from: 0, to: candidates.count, by: 8).map({ Array(candidates[$0..<min($0 + 8, candidates.count)]) }) {
            let results = await withTaskGroup(of: AppUpdate?.self) { group -> [AppUpdate] in
                for candidate in chunk {
                    group.addTask { await AppUpdateChecker.check(candidate) }
                }
                var list: [AppUpdate] = []
                for await result in group { if let result { list.append(result) } }
                return list
            }
            found += results
            done += chunk.count
            phase = .checking(done: done, total: candidates.count)
            updates = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        phase = .done(checked: candidates.count)
    }

    func open(_ update: AppUpdate) {
        switch update.source {
        case .appStore(let url):
            NSWorkspace.shared.open(url)
        case .sparkle:
            // Sparkle apps offer their own update when they start.
            NSWorkspace.shared.openApplication(at: update.url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

enum AppUpdateChecker {
    struct Candidate: Sendable {
        let url: URL
        let name: String
        let bundleID: String
        let version: String
        let build: String
        let feed: URL?
        let fromAppStore: Bool
    }

    static func candidates() -> [Candidate] {
        Scanner.appBundles().compactMap { url, bundle, id in
            let info = bundle.infoDictionary ?? [:]
            let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
            let fromAppStore = FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path)
            // Apple's own apps update through Software Update.
            guard fromAppStore || (feed != nil && !id.hasPrefix("com.apple.")) else { return nil }
            return Candidate(url: url, name: Scanner.appName(url), bundleID: id,
                             version: info["CFBundleShortVersionString"] as? String ?? "",
                             build: info["CFBundleVersion"] as? String ?? "",
                             feed: feed, fromAppStore: fromAppStore)
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    static func check(_ c: Candidate) async -> AppUpdate? {
        if c.fromAppStore { return await checkAppStore(c) }
        if let feed = c.feed { return await checkSparkle(c, feed: feed) }
        return nil
    }

    private static func checkAppStore(_ c: Candidate) async -> AppUpdate? {
        let country = Locale.current.region?.identifier.lowercased() ?? "us"
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(c.bundleID)&country=\(country)&entity=desktopSoftware"),
              let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = (json["results"] as? [[String: Any]])?.first,
              let latest = result["version"] as? String,
              VersionCompare.isNewer(latest, than: c.version) else { return nil }
        let page = (result["trackViewUrl"] as? String)
            .map { $0.replacingOccurrences(of: "https://", with: "macappstore://") }
            .flatMap(URL.init(string:)) ?? URL(string: "macappstore://apps.apple.com")!
        return AppUpdate(url: c.url, name: c.name, installed: c.version, available: latest, source: .appStore(page))
    }

    private static func checkSparkle(_ c: Candidate, feed: URL) async -> AppUpdate? {
        guard let (data, _) = try? await session.data(from: feed) else { return nil }
        let parser = AppcastParser(data: data)
        guard let newest = parser.newest() else { return nil }
        let newer: Bool
        if let short = newest.shortVersion, !c.version.isEmpty {
            newer = VersionCompare.isNewer(short, than: c.version)
        } else if let build = newest.build, !c.build.isEmpty {
            newer = VersionCompare.isNewer(build, than: c.build)
        } else {
            newer = false
        }
        guard newer else { return nil }
        return AppUpdate(url: c.url, name: c.name, installed: c.version.isEmpty ? c.build : c.version,
                         available: newest.shortVersion ?? newest.build ?? "?", source: .sparkle(download: newest.download))
    }
}

/// Reads a Sparkle appcast and returns its newest entry.
final class AppcastParser: NSObject, XMLParserDelegate {
    struct Entry {
        var shortVersion: String?
        var build: String?
        var download: URL?
    }

    private let data: Data
    private var entries: [Entry] = []
    private var current: Entry?
    private var text = ""

    init(data: Data) {
        self.data = data
    }

    func newest() -> Entry? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        guard parser.parse() || !entries.isEmpty else { return nil }
        return entries.max { a, b in
            let av = a.shortVersion ?? a.build ?? "0"
            let bv = b.shortVersion ?? b.build ?? "0"
            return VersionCompare.isNewer(bv, than: av)
        }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "item":
            current = Entry()
        case "enclosure":
            if let short = attributes["sparkle:shortVersionString"] { current?.shortVersion = short }
            if let build = attributes["sparkle:version"] { current?.build = build }
            if let url = attributes["url"] { current?.download = URL(string: url) }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "sparkle:shortVersionString":
            if !value.isEmpty { current?.shortVersion = value }
        case "sparkle:version":
            if !value.isEmpty { current?.build = value }
        case "item":
            if let entry = current { entries.append(entry) }
            current = nil
        default:
            break
        }
        text = ""
    }
}

// MARK: - View

struct AppUpdatesView: View {
    let model: AppUpdatesModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle:
                VStack(spacing: 18) {
                    StateIcon(symbol: "arrow.down.circle", size: 96)
                    Text("Are your apps up to date?")
                        .font(.rounded(22, .bold))
                    Text("I'll check App Store apps and apps that update themselves.")
                        .foregroundStyle(.secondary)
                    Button("Check for Updates") { Task { await model.check() } }
                        .buttonStyle(ActionButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .checking(let done, let total):
                VStack(spacing: 14) {
                    BusyState(text: "Asking around… \(done) of \(total)")
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                        .frame(width: 220)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done(let checked):
                if model.updates.isEmpty {
                    VStack(spacing: 16) {
                        StateIcon(symbol: "checkmark", celebrate: true, size: 96)
                        Text("Everything's fresh!")
                            .font(.rounded(22, .bold))
                        Text("I checked \(checked) apps and they're all up to date.")
                            .foregroundStyle(.secondary)
                        Button("Check Again") { Task { await model.check() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list(checked: checked)
                }
            }
        }
    }

    private func list(checked: Int) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.updates.count) update\(model.updates.count == 1 ? "" : "s") available")
                        .font(.rounded(20, .bold))
                    Text("Checked \(checked) apps")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Check Again") { Task { await model.check() } }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            Divider()
            List(model.updates) { update in
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: update.url.path))
                        .resizable()
                        .frame(width: 34, height: 34)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(update.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(update.installed) → \(update.available) · \(update.sourceLabel)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(update.sourceLabel == "App Store" ? "Open App Store" : "Open App") {
                        model.open(update)
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 3)
            }
            .listStyle(.inset)
            // Let the style's own background show instead of the list's.
            .scrollContentBackground(.hidden)
        }
    }
}
