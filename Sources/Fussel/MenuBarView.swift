import SwiftUI
import AppKit

/// The little window that opens from the menu bar: one-click System Junk cleaning.
struct MenuBarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    private var junk: ModuleModel { app.junk }

    var body: some View {
        VStack(spacing: 14) {
            FusselBadge(mood: junk.mood, size: 76)
                .padding(.top, 6)

            VStack(spacing: 3) {
                Text(headline)
                    .font(.rounded(16, .semibold))
                Text(subline)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            primaryButton

            Divider()

            HStack {
                Button("Open Fussel") {
                    openWindow(id: "main")
                    NSApplication.shared.activate()
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 270)
    }

    private var headline: String {
        switch junk.phase {
        case .idle: return "Ready to tidy up"
        case .scanning: return "Looking for fluff…"
        case .results: return junk.items.isEmpty ? "Already fluff-free" : "Found \(junk.selectedSize.byteString)"
        case .cleaning: return "Tidying up…"
        case let .done(freed, _): return freed > 0 ? "Cleared \(freed.byteString)" : "All tidy"
        }
    }

    private var subline: String {
        switch junk.phase {
        case .results where !junk.items.isEmpty: return "of caches and logs, ready to go to the Trash"
        case .done: return "Your Mac feels lighter already"
        default: return "Quick clean of caches and logs"
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch junk.phase {
        case .idle, .done:
            Button("Quick Scan") { Task { await junk.scan(options: .current) } }
                .buttonStyle(CoralButtonStyle())
        case .results:
            if junk.items.isEmpty || junk.selected.isEmpty {
                Button("Scan Again") { Task { await junk.scan(options: .current) } }
                    .buttonStyle(CoralButtonStyle())
            } else {
                Button("Move to Trash") { Task { await junk.clean() } }
                    .buttonStyle(CoralButtonStyle())
            }
        case .scanning, .cleaning:
            ProgressView().controlSize(.small)
        }
    }
}
