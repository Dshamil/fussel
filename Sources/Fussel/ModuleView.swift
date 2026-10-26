import SwiftUI
import AppKit

struct ModuleView: View {
    let model: ModuleModel

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                IntroState(model: model)
            case .scanning:
                BusyState(text: "Looking for fluff…", module: model.module)
            case .results:
                if model.items.isEmpty {
                    DoneState(title: "Already fluff-free", detail: "Nothing to clean up here right now.",
                              failures: [], model: model)
                } else {
                    ResultsList(model: model)
                }
            case .cleaning:
                BusyState(text: "Tidying up…", module: model.module)
            case let .done(freed, failures):
                DoneState(title: "All tidy!",
                          detail: freed > 0 ? "Fussel cleared \(freed.byteString)." : "Nothing was removed.",
                          failures: failures, model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(model.module.title)
    }
}

/// The card's symbol, big, on a soft circle in the card's color.
struct ModuleEmblem: View {
    let module: Module
    var symbol: String? = nil
    var bounce = 0
    var pulsing = false
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            Circle()
                .fill(!palette.colorful ? .white.opacity(0.07) : palette.isDark ? Palette.pastel(module).opacity(0.16) : Palette.pastel(module))
            Image(systemName: symbol ?? module.symbol)
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(palette.icon(module))
                .symbolEffect(.bounce, value: bounce)
                .symbolEffect(.pulse, isActive: pulsing)
        }
        .frame(width: 118, height: 118)
        .accessibilityHidden(true)
    }
}

private struct IntroState: View {
    let model: ModuleModel

    var body: some View {
        VStack(spacing: 22) {
            ModuleEmblem(module: model.module)
            VStack(spacing: 8) {
                Text("Let's take a look")
                    .font(.rounded(26, .heavy))
                Text(model.module.blurb)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Button("Scan") {
                Task { await model.scan(options: .current) }
            }
            .buttonStyle(ActionButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
    }
}

struct BusyState: View {
    let text: String
    var module: Module? = nil

    var body: some View {
        VStack(spacing: 18) {
            if let module {
                ModuleEmblem(module: module, pulsing: true)
            } else {
                FusselBadge(mood: .busy, size: 150)
            }
            Text(text)
                .font(.rounded(16, .medium))
                .foregroundStyle(.secondary)
            ProgressView()
                .controlSize(.small)
        }
    }
}

private struct DoneState: View {
    let title: String
    let detail: String
    let failures: [String]
    let model: ModuleModel
    @State private var showFailures = false

    @State private var bounce = 0

    var body: some View {
        VStack(spacing: 18) {
            ModuleEmblem(module: model.module, symbol: "checkmark", bounce: bounce)
                .onAppear { bounce += 1 }
            Text(title)
                .font(.rounded(26, .heavy))
            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
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
                        .padding(14)
                    }
                    .frame(width: 380, height: 220)
                }
            }
            Button("Scan again") {
                Task { await model.scan(options: .current) }
            }
            .buttonStyle(ActionButtonStyle())
        }
        .padding(40)
    }
}

private struct ResultsList: View {
    let model: ModuleModel
    @State private var confirming = false
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Found \(model.totalSize.byteString)")
                        .font(.rounded(24, .heavy))
                    HStack(spacing: 0) {
                        Text("\(model.items.count) items · ")
                        Text(model.selectedSize.byteString)
                            .contentTransition(.numericText(value: Double(model.selectedSize)))
                        Text(" selected")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .animation(.snappy, value: model.selectedSize)
                }
                Spacer()
                Button("Rescan") {
                    Task { await model.scan(options: .current) }
                }
                .buttonStyle(NudgeButtonStyle(tint: palette.text, badgeText: palette.isDark ? Theme.ink : .white,
                                              symbol: "arrow.clockwise"))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider()

            List {
                ForEach(model.groups, id: \.self) { group in
                    Section {
                        ForEach(model.items(in: group)) { item in
                            ItemRow(
                                item: item,
                                isOn: Binding(
                                    get: { model.isSelected(item) },
                                    set: { model.setSelected(item, $0) }
                                )
                            )
                        }
                    } header: {
                        HStack {
                            Text(group)
                            Spacer()
                            let all = model.isGroupFullySelected(group)
                            Button(all ? "Deselect All" : "Select All") {
                                model.setGroup(group, selected: !all)
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                        }
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                if model.selectionIncludesPermanent {
                    Label("Items already in the Trash are deleted for good.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Everything goes to the Trash first, so you can still change your mind.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clean \(model.selectedSize.byteString)") {
                    confirming = true
                }
                .buttonStyle(ActionButtonStyle())
                .disabled(model.selected.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
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
            if model.selectionIncludesPermanent {
                Text("Items that are already in the Trash will be deleted permanently. Everything else is moved to the Trash.")
            } else {
                Text("The selected items will be moved to the Trash.")
            }
        }
    }
}

struct ItemRow: View {
    let item: CleanupItem
    @Binding var isOn: Bool
    var locked = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Select \(item.name)", isOn: $isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(locked)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .lineLimit(1)
                Text(item.displayPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if let date = item.date {
                Text(date, format: .dateTime.day().month().year())
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Text(item.size.byteString)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Label("Show in Finder", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
        .padding(.vertical, 2)
    }
}
