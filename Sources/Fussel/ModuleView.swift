import SwiftUI
import AppKit

/// One cleaning tool (System Junk, Large Files, Trash & Downloads): header with its actions,
/// then the list of what it found, each item labelled and explained.
struct ModuleView: View {
    let model: ModuleModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: model.module.title, subtitle: subtitle) {
                Button { Task { await model.scan(options: .current) } } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.phase == .scanning || model.phase == .cleaning)
                Button { confirming = true } label: {
                    Label(model.selected.isEmpty ? "Clean" : "Clean \(model.selectedSize.byteString)", systemImage: "trash")
                }
                .buttonStyle(ActionButtonStyle())
                .disabled(model.selected.isEmpty || model.phase != .results)
            }

            Group {
                switch model.phase {
                case .idle:
                    EmptyState(symbol: model.module.symbol, title: "Not scanned yet", detail: model.module.blurb) {
                        Button("Scan") { Task { await model.scan(options: .current) } }
                            .buttonStyle(ActionButtonStyle())
                            .keyboardShortcut(.defaultAction)
                    }
                case .scanning:
                    BusyState(text: "Looking for fluff…")
                case .cleaning:
                    BusyState(text: "Moving it to the Trash…")
                case .results:
                    if model.items.isEmpty {
                        EmptyState(symbol: "checkmark", celebrate: true, title: model.module.spotless + ".",
                                   detail: "This corner of your Mac is already tidy.") { EmptyView() }
                    } else {
                        ResultsList(model: model)
                    }
                case let .done(freed, failures):
                    DoneState(freed: freed, failures: failures, model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(
            "Clean \(model.selectedItems.count) items (\(model.selectedSize.byteString))?",
            isPresented: $confirming
        ) {
            Button(model.selectionIncludesPermanent ? "Clean and Delete Permanently" : "Move to Trash",
                   role: model.selectionIncludesPermanent ? .destructive : nil) {
                Task { await model.clean() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.selectionIncludesPermanent
                 ? "Items that are already in the Trash will be deleted permanently. Everything else is moved to the Trash."
                 : "The selected items will be moved to the Trash, so you can put them back.")
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .results: return "\(model.items.count) item\(model.items.count == 1 ? "" : "s") · \(model.totalSize.byteString) found"
        case .scanning: return "Scanning…"
        case .cleaning: return "Cleaning…"
        case .done(let freed, _): return freed > 0 ? "Cleaned \(freed.byteString)" : "Nothing was removed"
        case .idle: return "Not scanned yet"
        }
    }
}

/// A calm symbol in the middle, a title, a line of text and an optional action.
struct EmptyState<Action: View>: View {
    @Environment(\.palette) private var palette
    let symbol: String
    var celebrate = false
    /// After a clean-up: the happy Fussel himself instead of a symbol.
    var fussel = false
    let title: String
    let detail: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 12) {
            if fussel { HappyFussel() } else { StateIcon(symbol: symbol, celebrate: celebrate) }
            Text(title)
                .font(.rounded(22, .bold))
                .foregroundStyle(palette.text)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            action
                .padding(.top, 4)
        }
        .padding(40)
    }
}

/// Fussel on his graphite tile, smiling, with one hop when he appears.
private struct HappyFussel: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hopped = PreviewRenderer.isRendering

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.graphite)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(palette.isDark ? 0.14 : 0), lineWidth: 1))
            FusselBody(mood: .happy).equatable().frame(width: 68, height: 68)
        }
        .frame(width: 76, height: 76)
        .scaleEffect(hopped || reduceMotion ? 1 : 0.6)
        .offset(y: hopped || reduceMotion ? 0 : 8)
        .onAppear { withAnimation(.spring(duration: 0.5, bounce: 0.55).delay(0.1)) { hopped = true } }
        .accessibilityHidden(true)
    }
}

/// A symbol in a soft circle for empty and finished states. Celebrating, it turns green and bounces once.
struct StateIcon: View {
    let symbol: String
    var celebrate = false
    var size: CGFloat = 76
    @Environment(\.palette) private var palette
    @State private var bounce = 0

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(celebrate ? Palette.safe : palette.secondary)
            .symbolEffect(.bounce, value: bounce)
            .frame(width: size, height: size)
            .background(Circle().fill((celebrate ? Palette.safe : palette.text).opacity(0.08)))
            .onAppear { if celebrate { bounce += 1 } }
            .accessibilityHidden(true)
    }
}

/// A spinner and a line saying what's going on.
struct BusyState: View {
    @Environment(\.palette) private var palette
    let text: String

    var body: some View {
        VStack(spacing: 16) {
            Spinner(tint: palette.secondary, size: 34)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.secondary)
        }
    }
}

private struct DoneState: View {
    let freed: Int64
    let failures: [String]
    let model: ModuleModel
    @Environment(AppModel.self) private var app
    @State private var showFailures = false

    var body: some View {
        EmptyState(symbol: "checkmark", celebrate: true, fussel: freed > 0, title: freed > 0 ? UserName.allTidy(freed) : "All tidy",
                   detail: freed > 0 ? "Moved to Trash, so you can put it back anytime." : "Nothing was removed.") {
            VStack(spacing: 10) {
                if freed > 0, let record = model.lastRecord {
                    Button("Undo") { Task { _ = await app.undo(record) } }
                        .buttonStyle(SecondaryButtonStyle())
                }
                if !failures.isEmpty {
                    Button("\(failures.count) item\(failures.count == 1 ? "" : "s") couldn't be removed") {
                        showFailures = true
                    }
                    .buttonStyle(.link)
                    .popover(isPresented: $showFailures) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(failures, id: \.self) { Text($0).font(.system(size: 11)) }
                            }
                            .padding(16)
                        }
                        .frame(width: 380, height: 220)
                    }
                }
                Button("Scan Again") { Task { await model.scan(options: .current) } }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

// MARK: - Results

private enum Filter: Hashable { case all, safe, check }
private enum Sort: String, CaseIterable { case largest = "Largest", name = "Name", oldest = "Oldest" }

private struct ResultsList: View {
    let model: ModuleModel
    @Environment(\.palette) private var palette
    @State private var filter = Filter.all
    @State private var sort = Sort.largest
    @State private var appeared = PreviewRenderer.isRendering

    private var shown: [CleanupItem] {
        let filtered = model.items.filter { item in
            switch filter {
            case .all: return true
            case .safe: return item.isSafe
            case .check: return !item.isSafe
            }
        }
        switch sort {
        case .largest: return filtered.sorted { $0.size > $1.size }
        case .name: return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .oldest: return filtered.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        }
    }

    var body: some View {
        let items = shown
        let allOn = !items.isEmpty && items.allSatisfy { model.isSelected($0) }
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                chip(.all, "All", count: model.items.count, symbol: "square.grid.2x2")
                chip(.safe, "Safe to Remove", count: model.items.filter(\.isSafe).count, symbol: "checkmark.circle.fill")
                chip(.check, "Review First", count: model.items.filter { !$0.isSafe }.count, symbol: "exclamationmark.circle")
                Spacer()
                Button {
                    let all = Sort.allCases
                    sort = all[(all.firstIndex(of: sort)! + 1) % all.count]
                } label: {
                    Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                        .contentTransition(.opacity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .help("Change the order")
            }
            .padding(.horizontal, 32)

            HStack {
                CheckBox(isOn: Binding(get: { allOn }, set: { on in items.forEach { model.setSelected($0, on) } }),
                         label: "Select All")
                Spacer()
                Text("\(model.selectedSize.byteString) selected")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(model.selectedSize)))
                    .animation(.snappy, value: model.selectedSize)
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 8)

            PreviewSafeScroll {
                LazyVStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ItemRow(item: item, isOn: Binding(get: { model.isSelected(item) },
                                                          set: { model.setSelected(item, $0) }))
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)
                            .animation(.spring(duration: 0.45, bounce: 0.2).delay(min(0.3, 0.03 * Double(index))), value: appeared)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .animation(.spring(duration: 0.35), value: filter)
                .animation(.spring(duration: 0.35), value: sort)
            }
        }
        .onAppear { appeared = true }
    }

    private func chip(_ value: Filter, _ title: String, count: Int, symbol: String) -> some View {
        let on = filter == value
        let tint: Color = value == .safe ? Palette.safe : (value == .check ? Palette.caution : palette.text)
        return Button {
            filter = value
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .foregroundStyle(on ? tint : palette.secondary)
                Text(title)
                Text("\(count)")
                    .foregroundStyle(palette.secondary)
                    .monospacedDigit()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(on ? palette.text : palette.secondary)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? palette.selection : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.cardStroke, lineWidth: on ? 0 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: on)
    }
}

/// One found item: checkbox, icon, name with a plain-language explanation, size and safety label.
struct ItemRow: View {
    @Environment(\.palette) private var palette
    let item: CleanupItem
    @Binding var isOn: Bool
    var locked = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            CheckBox(isOn: $isOn, label: nil, accessibility: "Select \(item.name)")
                .disabled(locked)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text(item.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.displayPath)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 5) {
                Text(item.size.byteString)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.text)
                SafetyLabel(safe: item.isSafe)
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.secondary)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
            .opacity(hovering ? 1 : 0.4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(isOn ? palette.text.opacity(0.25) : palette.cardStroke, lineWidth: 1))
        .scaleEffect(hovering ? 1.005 : 1)
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// A rounded checkbox drawn in SwiftUI, so it looks the same everywhere (and in screenshots).
struct CheckBox: View {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Binding var isOn: Bool
    let label: String?
    var accessibility: String? = nil

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn ? palette.text : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isOn ? .clear : palette.secondary.opacity(0.6), lineWidth: 1.5))
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(palette.content)
                            .scaleEffect(isOn ? 1 : 0.3)
                            .opacity(isOn ? 1 : 0)
                    )
                    .frame(width: 18, height: 18)
                if let label {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.text)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(.spring(duration: 0.25, bounce: 0.5), value: isOn)
        .accessibilityLabel(accessibility ?? label ?? "")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A scroll view in the app; a plain stack when rendering screenshots, which can't draw scroll views.
struct PreviewSafeScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if PreviewRenderer.isRendering {
            VStack(spacing: 0) { content }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()
        } else {
            ScrollView { content }
        }
    }
}

extension CleanupItem {
    /// Fussel preselects what's safe to remove; everything else deserves a look first.
    var isSafe: Bool { preselected }

    /// What this is and why it's fine (or not) to remove, in plain words.
    var explanation: String {
        switch group {
        case "App Caches":
            return "Temporary files this app keeps so it loads faster. The app rebuilds them when it needs them."
        case "Logs":
            return "Records an app writes while it runs, mostly for fixing problems. Nothing needs them to work."
        case "Developer":
            return isSafe ? "Build data Xcode recreates on the next build." : "Xcode keeps these for debugging older builds and devices. Remove them if you don't need those."
        case "Large Files":
            return "A big file of yours. Have a look before letting it go."
        case "Not Opened in a While":
            return "A file you haven't opened in a long time. Have a look before letting it go."
        case "Trash":
            return "Already in the Trash. Cleaning removes it for good."
        case "Old Downloads":
            return "A download you haven't touched in a while. Have a look before letting it go."
        case "Application":
            return "The app itself."
        default:
            return "Support files left behind by this app."
        }
    }
}
