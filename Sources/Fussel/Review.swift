import SwiftUI
import AppKit
import QuickLookThumbnailing

/// One file at a time, as a big card: Keep (←) or Move to Trash (→), and ⌘Z goes back a step.
/// A pick only changes the selection; nothing is removed until Clean, which still asks first.
struct ReviewView: View {
    @Environment(\.palette) private var palette
    let model: ModuleModel
    let items: [CleanupItem]
    let close: () -> Void
    @State private var index = 0
    /// Each step's file and whether it was selected before, for ⌘Z.
    @State private var past: [(index: Int, wasOn: Bool)] = []
    /// Which way the last card left: -1 kept, 1 trashed.
    @State private var direction: CGFloat = 1

    var body: some View {
        let picked = items.filter { model.isSelected($0) }
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Review \(model.module.sidebarTitle)")
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(palette.text)
                    Text("\(min(index + 1, items.count)) of \(items.count) · \(picked.reduce(0) { $0 + $1.size }.byteString) picked for the Trash")
                        .font(.system(size: 12)).foregroundStyle(palette.secondary).monospacedDigit()
                }
                Spacer()
                Button("Done", action: close)
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            GeometryReader { geo in
                Capsule().fill(palette.text.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(palette.accent(model.module))
                            .frame(width: max(8, geo.size.width * Double(index) / Double(max(items.count, 1))))
                    }
            }
            .frame(height: 4)
            .padding(.top, 14)

            Spacer(minLength: 20)
            if index < items.count {
                ZStack {
                    // The next two wait underneath, a little smaller.
                    ForEach((1...2).reversed(), id: \.self) { depth in
                        if index + depth < items.count {
                            ReviewCard(item: items[index + depth], model: model, faded: true)
                                .scaleEffect(1 - 0.05 * Double(depth))
                                .offset(y: 14 * Double(depth))
                        }
                    }
                    ReviewCard(item: items[index], model: model, faded: false)
                        .id(index)
                        .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity),
                                                removal: .modifier(active: Thrown(x: direction * 520, angle: direction * 12),
                                                                   identity: Thrown(x: 0, angle: 0))
                                                    .combined(with: .opacity)))
                }
                Spacer(minLength: 20)
                HStack(spacing: 14) {
                    Button { decide(trash: false) } label: { Label("Keep", systemImage: "arrow.left") }
                        .buttonStyle(SecondaryButtonStyle())
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Button { decide(trash: true) } label: { Label("Move to Trash", systemImage: "arrow.right") }
                        .buttonStyle(ActionButtonStyle())
                        .keyboardShortcut(.rightArrow, modifiers: [])
                }
            } else {
                VStack(spacing: 10) {
                    StateIcon(symbol: "checkmark", celebrate: true)
                    Text("All looked at").font(.system(size: 20, weight: .bold)).foregroundStyle(palette.text)
                    Text(picked.isEmpty ? "Nothing picked for the Trash."
                         : "\(picked.count == 1 ? "1 file" : "\(picked.count) files") picked · \(picked.reduce(0) { $0 + $1.size }.byteString). Clean moves them to the Trash.")
                        .font(.system(size: 12)).foregroundStyle(palette.secondary)
                    Button("Back to the List", action: close)
                        .buttonStyle(ActionButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .padding(.top, 8)
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                Spacer(minLength: 20)
            }
            Button { goBack() } label: { Text("← keep  ·  → trash  ·  ⌘Z back") }
                .buttonStyle(.plain)
                .font(.system(size: 11)).foregroundStyle(palette.secondary)
                .keyboardShortcut("z", modifiers: .command)
                .disabled(past.isEmpty)
                .padding(.top, 12)
        }
        .padding(.horizontal, 32)
        .padding(.top, 14)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.content)
    }

    private func decide(trash: Bool) {
        guard index < items.count else { return }
        let item = items[index]
        past.append((index, model.isSelected(item)))
        model.setSelected(item, trash)
        direction = trash ? 1 : -1
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) { index += 1 }
    }

    private func goBack() {
        guard let last = past.popLast() else { return }
        model.setSelected(items[last.index], last.wasOn)
        direction = 0
        withAnimation(.spring(duration: 0.4, bounce: 0.2)) { index = last.index }
    }
}

/// A card thrown off to one side, tipping as it goes.
private struct Thrown: ViewModifier {
    let x: CGFloat
    let angle: Double
    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(angle)).offset(x: x)
    }
}

private struct ReviewCard: View {
    @Environment(\.palette) private var palette
    let item: CleanupItem
    let model: ModuleModel
    let faded: Bool
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 14) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().aspectRatio(contentMode: .fit)
                }
            }
            .frame(maxWidth: 220, maxHeight: 110)
            if !faded {
                VStack(spacing: 4) {
                    Text(item.name).font(.system(size: 16, weight: .bold)).foregroundStyle(palette.text)
                        .lineLimit(1).truncationMode(.middle)
                    Text(facts).font(.system(size: 12)).foregroundStyle(palette.secondary).monospacedDigit()
                    Text(note).font(.system(size: 11)).foregroundStyle(palette.secondary)
                        .multilineTextAlignment(.center).lineLimit(2).padding(.top, 4)
                    if !item.isSafe { SafetyLabel(safe: false).padding(.top, 6) }
                }
                .padding(.horizontal, 24)
            }
        }
        .frame(width: 440, height: 290)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.cardStroke, lineWidth: 1))
        .shadow(color: .black.opacity(faded ? 0.04 : 0.12), radius: faded ? 4 : 16, y: faded ? 2 : 8)
        .opacity(faded ? 0.7 : 1)
        .help(item.displayPath)
        .task(id: item.url) {
            guard !faded, !PreviewRenderer.isRendering else { return }
            let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 220, height: 110),
                                                       scale: 2, representationTypes: .thumbnail)
            thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
    }

    /// Size, folder and how old it is.
    private var facts: String {
        var parts = [item.size.byteString, item.url.deletingLastPathComponent().lastPathComponent]
        if let date = item.date {
            // The app speaks English, whatever the Mac's language.
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "en_US")
            let ago = formatter.localizedString(for: date, relativeTo: Date())
            parts.append(model.module == .large ? "last opened \(ago)" : "from \(ago)")
        }
        return parts.joined(separator: " · ")
    }

    private var note: String {
        if let stays = model.kept[item.group] { return "Same as \(stays.displayPath), which stays." }
        return item.explanation
    }
}
