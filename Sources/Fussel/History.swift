import SwiftUI
import AppKit

/// One clean-up, remembered so it can be shown and undone.
struct CleanRecord: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    var source: String
    var freed: Int64
    var itemCount: Int
    var trashed: [TrashedItem]
    var undone = false

    var canUndo: Bool { !undone && !trashed.isEmpty }
}

/// The clean-up history, stored in ~/Library/Application Support/Fussel/history.json.
@Observable
@MainActor
final class CleanHistory {
    static let shared = CleanHistory()

    private(set) var records: [CleanRecord] = []

    /// Everything Fussel has cleared and that wasn't put back.
    var totalFreed: Int64 {
        records.filter { !$0.undone }.reduce(0) { $0 + $1.freed }
    }

    private let file: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fussel", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("history.json")
    }()

    init() {
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([CleanRecord].self, from: data) {
            records = saved
        }
    }

    @discardableResult
    func record(_ result: CleanResult, source: String, itemCount: Int) -> CleanRecord? {
        guard result.freed > 0 || !result.trashed.isEmpty else { return nil }
        let entry = CleanRecord(date: Date(), source: source, freed: result.freed,
                                itemCount: itemCount, trashed: result.trashed)
        records.insert(entry, at: 0)
        if records.count > 50 { records.removeLast(records.count - 50) }
        save()
        return entry
    }

    /// Puts everything from a clean-up back where it came from.
    /// Returns how many items were restored and which ones couldn't be.
    func undo(_ record: CleanRecord) async -> (restored: Int, failed: [String]) {
        guard let index = records.firstIndex(where: { $0.id == record.id }), records[index].canUndo else {
            return (0, [])
        }
        let items = records[index].trashed
        let outcome = await Task.detached(priority: .userInitiated) { () -> (Int, [String]) in
            let fm = FileManager.default
            var restored = 0
            var failed: [String] = []
            for item in items {
                guard fm.fileExists(atPath: item.trashed.path) else {
                    failed.append("\(item.name): no longer in the Trash")
                    continue
                }
                guard !fm.fileExists(atPath: item.original.path) else {
                    failed.append("\(item.name): something new is already in its place")
                    continue
                }
                do {
                    try fm.createDirectory(at: item.original.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
                    try fm.moveItem(at: item.trashed, to: item.original)
                    restored += 1
                } catch {
                    failed.append("\(item.name): \(error.localizedDescription)")
                }
            }
            return (restored, failed)
        }.value
        if let i = records.firstIndex(where: { $0.id == record.id }) {
            records[i].undone = true
            save()
        }
        return outcome
    }

    var latestUndoable: CleanRecord? {
        records.first.flatMap { $0.canUndo ? $0 : nil }
    }

    private func save() {
        let records = self.records
        let file = self.file
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(records) {
                try? data.write(to: file, options: .atomic)
            }
        }
    }
}

/// "✨ 24 GB cleared" pill in the footer; opens the history.
struct HistoryPill: View {
    @Environment(\.palette) private var palette
    @Environment(AppModel.self) private var app
    @State private var showing = false
    private var history: CleanHistory { CleanHistory.shared }

    var body: some View {
        Button {
            showing = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(palette.text)
                if history.totalFreed > 0 {
                    Text("\(history.totalFreed.byteString) cleared")
                } else {
                    Text("History")
                }
            }
            .font(.rounded(12, .bold))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(palette.card))
            .overlay(Capsule().strokeBorder(palette.cardStroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Clean-up history")
        .popover(isPresented: $showing, arrowEdge: .top) {
            HistoryList()
                .environment(app)
        }
    }
}

private struct HistoryList: View {
    @Environment(AppModel.self) private var app
    @State private var message: String?
    @State private var working: UUID?
    private var history: CleanHistory { CleanHistory.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Clean-up history")
                    .font(.rounded(15, .bold))
                Spacer()
                Text("\(history.totalFreed.byteString) in total")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if history.records.isEmpty {
                Text("Nothing cleaned yet. Start a scan and I'll keep track here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(history.records.prefix(20)) { record in
                            row(record)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Undo puts items back from the Trash, as long as you haven't emptied it.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 360)
    }

    private func row(_ record: CleanRecord) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(record.freed.byteString) · \(record.source)")
                    .font(.system(size: 13, weight: .semibold))
                    .strikethrough(record.undone)
                Text("\(record.date.formatted(.relative(presentation: .named))) · \(record.itemCount) items")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if record.undone {
                Label("Restored", systemImage: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else if record.canUndo {
                Button(working == record.id ? "Restoring…" : "Undo") {
                    Task { await undo(record) }
                }
                .controlSize(.small)
                .disabled(working != nil)
            }
        }
        .padding(.vertical, 8)
    }

    private func undo(_ record: CleanRecord) async {
        working = record.id
        let outcome = await app.undo(record)
        working = nil
        message = outcome.failed.isEmpty
            ? "Put back \(outcome.restored) item(s). Phew!"
            : "Put back \(outcome.restored) item(s). \(outcome.failed.count) couldn't be restored."
    }
}
