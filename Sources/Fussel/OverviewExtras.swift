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
                    FolderSize(url: url, name: url.lastPathComponent, bytes: size(of: url))
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

/// "Where your space goes": the four biggest folders, each a click away in Finder.
struct BiggestFolders: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        OverviewCard(title: "Where your space goes") {
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
                let top = Array(app.folders.prefix(4))
                let largest = Double(max(1, top.first?.bytes ?? 1))
                VStack(spacing: 2) {
                    ForEach(top) { folder in
                        FolderRow(folder: folder, share: Double(folder.bytes) / largest)
                    }
                }
            }
        }
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
        .accessibilityLabel("\(folder.name), \(folder.bytes.byteString)")
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
            let records = PreviewRenderer.isRendering ? PreviewRenderer.sampleRecords : Array(CleanHistory.shared.records.prefix(3))
            if records.isEmpty {
                Text("Nothing cleaned yet. When you do, Undo will be right here.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        if index > 0 {
                            Rectangle().fill(palette.cardStroke).frame(height: 1)
                        }
                        row(record)
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

/// A titled card for the lower part of the overview.
private struct OverviewCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.text)
                .padding(.horizontal, 8)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .cardSurface(palette, radius: 12)
    }
}
