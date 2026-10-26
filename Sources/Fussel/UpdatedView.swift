import SwiftUI

/// The little card Fussel shows once after it was updated: which version is now running, a link to
/// what's new, and, if macOS forgot it, the way back to Full Disk Access.
struct UpdatedView: View {
    let version: String
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            Color.black.opacity(palette.isDark ? 0.45 : 0.25)
                .ignoresSafeArea()
                .onTapGesture {}

            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.graphite)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(palette.isDark ? 0.14 : 0), lineWidth: 1))
                    FusselBody(mood: .happy).equatable().frame(width: 58, height: 58)
                }
                .frame(width: 64, height: 64)

                Text("Updated to Fussel \(version)")
                    .font(.rounded(22, .bold))
                    .foregroundStyle(palette.text)
                Text("All set and ready to tidy up.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)

                if !app.hasFullDiskAccess {
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(palette.text)
                        Text("macOS asks for Full Disk Access again after an update.")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(12)
                    .cardSurface(palette, radius: 12)
                    .padding(.top, 4)
                }

                HStack {
                    Button("What's New") {
                        if let url = URL(string: "https://github.com/\(FusselUpdater.owner)/\(FusselUpdater.repo)/releases/tag/v\(version)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button("Done") { close() }
                        .buttonStyle(ActionButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 8)
            }
            .padding(24)
            .frame(width: 440)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.sheet))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.cardStroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
        }
        // Coming back from System Settings with access granted: the hint goes away.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshAccess()
        }
        .onExitCommand { close() }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) { app.justUpdatedTo = nil }
    }
}
