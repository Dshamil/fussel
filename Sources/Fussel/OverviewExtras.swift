import SwiftUI
import AppKit

/// One of the big places on the Mac and how much it holds.
struct FolderSize: Identifiable, Sendable {
    let url: URL
    let name: String
    let bytes: Int64
    var id: URL { url }
}

/// Measures where the space goes: every folder in the home folder, the Library and Applications.
/// Only reads sizes; nothing is changed.
enum FolderSizes {
    static func measure() async -> [FolderSize] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var places = ((try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        // The Library is hidden, so it's added by hand, like Applications outside the home folder.
        places.append(home.appendingPathComponent("Library"))
        places.append(URL(fileURLWithPath: "/Applications"))

        // Each folder in its own task, so a huge one doesn't hold up the rest.
        let sizes = await withTaskGroup(of: FolderSize.self) { group in
            for url in places {
                group.addTask(priority: .utility) {
                    // There's an Applications folder in the home folder too (apps just for you); keep the two apart.
                    let name = url.path == home.appendingPathComponent("Applications").path
                        ? "Applications (Home)" : url.lastPathComponent
                    return FolderSize(url: url, name: name, bytes: size(of: url))
                }
            }
            var all: [FolderSize] = []
            for await size in group { all.append(size) }
            return all
        }
        return sizes.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
    }

    private static func size(of folder: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [],
                                                         errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        let wanted = Set(keys)
        var done = false
        while !done {
            // Let go of each file's details right away; the Library alone can hold 100,000s of files.
            autoreleasepool {
                guard let file = files.nextObject() as? URL else { done = true; return }
                if let v = try? file.resourceValues(forKeys: wanted), v.isRegularFile == true {
                    total += Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
                }
            }
        }
        return total
    }
}

/// One measurement of the big folders: path to bytes.
struct FolderSnapshot: Codable, Sendable, Equatable {
    var date: Date
    var sizes: [String: Int64]
}

/// What grew since an earlier measurement, biggest first.
struct FolderGrowth: Sendable, Equatable {
    var since: Date
    /// Bytes each folder grew by, by path. Only real growth is listed.
    var grown: [String: Int64]

    var biggest: (path: String, bytes: Int64)? {
        grown.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }
}

/// Remembers how big the folders were, one measurement a day for 60 days, to answer "what grew?".
/// Stored in ~/Library/Application Support/Fussel/folders.json. It holds folder names and sizes, nothing else.
enum FolderHistory {
    /// Less than this is everyday noise, like a browser's cache coming and going.
    static let noticeable: Int64 = 100_000_000

    private static var file: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fussel", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("folders.json")
    }

    static func record(_ folders: [FolderSize]) -> FolderGrowth? {
        let saved = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([FolderSnapshot].self, from: $0) } ?? []
        let now = Date()
        let sizes = Dictionary(folders.map { ($0.url.path, $0.bytes) }, uniquingKeysWith: { first, _ in first })
        let history = adding(FolderSnapshot(date: now, sizes: sizes), to: saved)
        if let data = try? JSONEncoder().encode(history) { try? data.write(to: file, options: .atomic) }
        return growth(of: sizes, now: now, history: history)
    }

    /// Today's newest measurement replaces today's earlier one.
    static func adding(_ snapshot: FolderSnapshot, to history: [FolderSnapshot]) -> [FolderSnapshot] {
        let others = history.filter { !Calendar.current.isDate($0.date, inSameDayAs: snapshot.date) }
        return Array((others + [snapshot]).sorted { $0.date < $1.date }.suffix(60))
    }

    /// Compares with a week ago, or with the oldest measurement that's at least a day old.
    static func growth(of sizes: [String: Int64], now: Date, history: [FolderSnapshot]) -> FolderGrowth? {
        let old = history.filter { now.timeIntervalSince($0.date) >= 86_400 }
        guard let base = old.last(where: { now.timeIntervalSince($0.date) >= 7 * 86_400 }) ?? old.first else { return nil }
        // A folder that wasn't measured back then isn't growth, just new to the list.
        var grown: [String: Int64] = [:]
        for (path, bytes) in sizes {
            if let before = base.sizes[path], bytes - before >= noticeable { grown[path] = bytes - before }
        }
        return FolderGrowth(since: base.date, grown: grown)
    }
}

/// "Where your space goes": the biggest folders, each a click away in Finder, and what grew lately.
struct BiggestFolders: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        OverviewCard(title: "Where your space goes", note: growthNote, shortNote: shortGrowthNote) {
            if !app.hasFullDiskAccess {
                note("Allow Full Disk Access so I can measure your folders.") {
                    Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
                        .buttonStyle(.link)
                }
            } else if app.folders.isEmpty {
                HStack(spacing: 8) {
                    Spinner(tint: palette.secondary)
                    Text("Measuring your folders…")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                // As many folders as the card has room for, at least four.
                GeometryReader { room in
                    let top = Array(app.folders.prefix(max(4, Int(room.size.height / 26))))
                    let largest = Double(max(1, top.first?.bytes ?? 1))
                    VStack(spacing: 2) {
                        ForEach(top) { folder in
                            FolderRow(folder: folder, share: Double(folder.bytes) / largest,
                                      grew: app.folderGrowth?.grown[folder.url.path],
                                      showsGrowth: top.contains { app.folderGrowth?.grown[$0.url.path] != nil })
                        }
                    }
                }
            }
        }
    }

    /// Answers "what grew?" even when that folder isn't one of the rows shown.
    private var growthNote: String? {
        guard !app.folders.isEmpty else { return nil }
        guard let growth = app.folderGrowth else { return "Shows what grew after a day or two" }
        let since = growth.since.formatted(.relative(presentation: .named).locale(Locale(identifier: "en_US")))
        guard let top = growth.biggest else { return "Nothing grew much since \(since)" }
        let name = app.folders.first { $0.url.path == top.path }?.name ?? URL(fileURLWithPath: top.path).lastPathComponent
        return "\(name) grew most: +\(top.bytes.byteString) since \(since)"
    }

    /// The same, for a narrow card: just the folder and how much.
    private var shortGrowthNote: String? {
        guard let growth = app.folderGrowth, let top = growth.biggest else { return nil }
        let name = app.folders.first { $0.url.path == top.path }?.name ?? URL(fileURLWithPath: top.path).lastPathComponent
        return "\(name) +\(top.bytes.byteString)"
    }

    private func note<Action: View>(_ text: String, @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 6) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
            action()
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }
}

private struct FolderRow: View {
    let folder: FolderSize
    let share: Double
    var grew: Int64?
    /// Keeps the room for the growth on every row, so the bars stay comparable.
    var showsGrowth = false
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: folder.url.path == "/Applications" ? "square.grid.2x2" : "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondary)
                .frame(width: 16)
            Text(folder.name)
                .font(.system(size: 13))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
            GeometryReader { geo in
                Capsule()
                    .fill(palette.secondary.opacity(0.45))
                    .frame(width: max(4, geo.size.width * share))
            }
            .frame(height: 6)
            if showsGrowth {
                Text(grew.map { "+\($0.byteString)" } ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: 60, alignment: .trailing)
            }
            Text(folder.bytes.byteString)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.text)
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(hovering ? palette.selection.opacity(0.6) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { NSWorkspace.shared.open(folder.url) }
        .help("Show \(folder.name) in Finder")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(folder.name), \(folder.bytes.byteString)" + (grew.map { ", grew by \($0.byteString)" } ?? ""))
        .accessibilityHint("Opens it in Finder")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { NSWorkspace.shared.open(folder.url) }
    }
}

/// The last few clean-ups, each with Undo right there.
struct RecentCleanups: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var working: UUID?

    var body: some View {
        OverviewCard(title: "Recent clean-ups") {
            // Screenshots show made-up clean-ups, never the history of the Mac they're drawn on.
            let all = PreviewRenderer.isRendering ? PreviewRenderer.sampleRecords : CleanHistory.shared.records
            if all.isEmpty {
                Text("Nothing cleaned yet. When you do, Undo will be right here.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                // As many as the card has room for, at least three.
                GeometryReader { room in
                    VStack(spacing: 0) {
                        ForEach(Array(all.prefix(max(3, Int(room.size.height / 31))).enumerated()), id: \.element.id) { index, record in
                            if index > 0 {
                                Rectangle().fill(palette.cardStroke).frame(height: 1)
                            }
                            row(record)
                        }
                    }
                }
            }
        }
    }

    private func row(_ record: CleanRecord) -> some View {
        HStack(spacing: 8) {
            Text(record.freed.byteString)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.text)
                .strikethrough(record.undone)
                .monospacedDigit()
            Text(record.date.formatted(.relative(presentation: .named).locale(Locale(identifier: "en_US"))))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if record.undone {
                Text("Restored")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            } else if record.canUndo {
                Button(working == record.id ? "Restoring…" : "Undo") {
                    working = record.id
                    Task {
                        _ = await app.undo(record)
                        working = nil
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.text)
                .padding(.horizontal, 12)
                .frame(height: 22)
                .background(Capsule().fill(palette.text.opacity(0.08)))
                .disabled(working != nil)
                .help("Put \(record.source) back from the Trash")
                .accessibilityLabel("Undo clean-up of \(record.freed.byteString), \(record.source)")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
    }
}

/// "Mac Health": how the battery and the disk are holding up, and when the Mac last restarted.
struct HealthCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        OverviewCard(title: "Mac Health") {
            VStack(spacing: 0) {
                if let health = app.health {
                    if let capacity = health.batteryCapacity {
                        row("battery.75percent", "Battery", "\(capacity) %")
                    }
                    if let cycles = health.batteryCycles {
                        row("arrow.triangle.2.circlepath", "Charge cycles", "\(cycles)")
                    }
                    if let verdict = health.diskVerdict {
                        row("internaldrive", "Disk", verdict, warn: !health.diskIsHealthy)
                    }
                    if let restart = health.lastRestart {
                        row("power", "Restarted", restart.formatted(.relative(presentation: .named).locale(Locale(identifier: "en_US"))))
                    }
                } else {
                    Spinner(tint: palette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
            }
        }
    }

    private func row(_ symbol: String, _ name: String, _ value: String, warn: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondary)
                .frame(width: 16)
            Text(name)
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(warn ? Palette.caution : palette.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .accessibilityElement(children: .combine)
    }
}

/// A titled card for the lower part of the overview.
private struct OverviewCard<Content: View>: View {
    let title: String
    var note: String? = nil
    var shortNote: String? = nil
    @ViewBuilder var content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .fixedSize()
                Spacer(minLength: 4)
                if let note {
                    ViewThatFits(in: .horizontal) {
                        noteText(note).fixedSize()
                        noteText(shortNote ?? note)
                    }
                }
            }
            .padding(.horizontal, 8)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface(palette, radius: 12)
    }

    private func noteText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(palette.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
