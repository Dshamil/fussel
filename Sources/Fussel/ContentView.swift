import SwiftUI
import AppKit

/// Fussel's single main screen: a coral hero with one big action, and four cards below.
struct ContentView: View {
    @Environment(AppModel.self) private var app
    @State private var openModule: Module?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        VStack(spacing: 18) {
            HeroCard()

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Module.allCases) { module in
                    ModuleCard(module: module) { openModule = module }
                }
            }

            if !app.hasFullDiskAccess {
                FullDiskAccessHint()
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 26)
        .padding(.top, 8)
        .frame(minWidth: 700, idealWidth: 760, maxWidth: .infinity,
               minHeight: 540, maxHeight: .infinity, alignment: .top)
        .background(Theme.canvas)
        .sheet(item: $openModule) { module in
            DetailSheet(module: module)
                .environment(app)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshAccess()
        }
    }
}

// MARK: - Hero

private struct HeroCard: View {
    @Environment(AppModel.self) private var app
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 26) {
            FusselMascot(mood: app.mood, size: 150)
                .padding(.leading, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(headline)
                    .font(.rounded(30, .bold))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text(subline)
                    .font(.rounded(14, .medium))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                action
                    .padding(.top, 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, minHeight: 210)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.coralGradient)
                .shadow(color: Theme.coralDeep.opacity(0.28), radius: 18, y: 10)
        )
        .animation(.spring(duration: 0.4), value: app.stage)
        .onChange(of: app.confirmCleanRequested) { _, requested in
            guard requested else { return }
            app.confirmCleanRequested = false
            if app.selectedTotal > 0 { confirming = true }
        }
        .confirmationDialog("Clean \(app.selectedTotal.byteString)?", isPresented: $confirming) {
            Button(app.selectionIncludesPermanent ? "Clean and Delete Permanently" : "Move to Trash",
                   role: app.selectionIncludesPermanent ? .destructive : nil) {
                Task { await app.cleanAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(app.selectionIncludesPermanent
                 ? "Items already in the Trash are deleted permanently. Everything else goes to the Trash."
                 : "Everything selected goes to the Trash, so you can still change your mind.")
        }
    }

    private var headline: String {
        switch app.stage {
        case .idle: return "Hi, I'm Fussel."
        case .scanning: return "Looking for fluff…"
        case .ready: return app.foundTotal > 0 ? "Found \(app.foundTotal.byteString)" : "Already fluff-free!"
        case .cleaning: return "Tidying up…"
        case .done: return "All tidy!"
        }
    }

    private var subline: String {
        switch app.stage {
        case .idle:
            return "Let's find the fluff hiding on your Mac."
        case .scanning:
            return "Checking caches, logs, big files and downloads."
        case .ready:
            if app.foundTotal == 0 { return "Nothing to clean right now. Nice." }
            return app.selectedTotal > 0
                ? "\(app.selectedTotal.byteString) is ready to go. Open a card to review."
                : "Open a card below to choose what to clean."
        case .cleaning:
            return "Moving things to the Trash."
        case let .done(freed, failures):
            var text = freed > 0 ? "Cleared \(freed.byteString). Your Mac feels lighter." : "Nothing needed removing."
            if !failures.isEmpty { text += " \(failures.count) item(s) couldn't be removed." }
            return text
        }
    }

    @ViewBuilder
    private var action: some View {
        switch app.stage {
        case .idle:
            Button("Start Scan") { Task { await app.smartScan() } }
                .buttonStyle(InkButtonStyle())
                .keyboardShortcut(.defaultAction)
        case .scanning, .cleaning:
            ProgressView()
                .controlSize(.small)
                .tint(Theme.ink)
                .frame(height: 40)
        case .ready:
            if app.selectedTotal > 0 {
                HStack(spacing: 12) {
                    Button("Clean \(app.selectedTotal.byteString)") { confirming = true }
                        .buttonStyle(InkButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    Button("Scan Again") { Task { await app.smartScan() } }
                        .buttonStyle(.plain)
                        .font(.rounded(13, .semibold))
                        .foregroundStyle(Theme.ink)
                }
            } else {
                Button("Scan Again") { Task { await app.smartScan() } }
                    .buttonStyle(InkButtonStyle())
            }
        case .done:
            Button("Scan Again") { Task { await app.smartScan() } }
                .buttonStyle(InkButtonStyle())
        }
    }
}

// MARK: - Cards

private struct ModuleCard: View {
    @Environment(AppModel.self) private var app
    let module: Module
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.coral.opacity(0.14))
                    Image(systemName: module.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(module.title)
                        .font(.rounded(15, .semibold))
                        .foregroundStyle(.primary)
                    status
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: .black.opacity(hovering ? 0.10 : 0.05), radius: hovering ? 12 : 6, y: hovering ? 6 : 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1)
            )
            .scaleEffect(hovering ? 1.01 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hovering = inside }
        }
    }

    @ViewBuilder
    private var status: some View {
        if module == .uninstaller {
            Text("Remove apps and their leftovers")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            let model = app.model(for: module)
            switch model.phase {
            case .idle:
                Text(shortBlurb)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            case .scanning, .cleaning:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(model.phase == .scanning ? "Scanning…" : "Cleaning…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            case .results:
                if model.items.isEmpty {
                    Label("All tidy", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(model.totalSize.byteString)
                            .font(.rounded(18, .bold))
                            .foregroundStyle(.primary)
                        Text(model.selected.isEmpty ? "nothing selected" : "\(model.selectedSize.byteString) selected")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            case let .done(freed, _):
                Label(freed > 0 ? "Cleared \(freed.byteString)" : "All tidy", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var shortBlurb: String {
        switch module {
        case .junk: return "Caches, logs and build data"
        case .large: return "Big files and forgotten ones"
        case .tidy: return "Trash and old downloads"
        case .uninstaller: return "Remove apps and their leftovers"
        }
    }
}

// MARK: - Detail sheet

private struct DetailSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let module: Module

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: module.symbol)
                    .foregroundStyle(Theme.accentText)
                Text(module.title)
                    .font(.rounded(17, .semibold))
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            Group {
                if module == .uninstaller {
                    UninstallerView(model: app.uninstaller)
                } else {
                    ModuleView(model: app.model(for: module))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 520)
        .background(Theme.canvas)
    }
}

// MARK: - Full Disk Access

struct FullDiskAccessHint: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(Theme.accentText)
            Text("Give Fussel Full Disk Access so it can reach the Trash and every hidden speck.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.cardStroke, lineWidth: 1)
        )
    }
}
