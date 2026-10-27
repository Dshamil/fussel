import SwiftUI
import UserNotifications

/// Asks for what Fussel needs to work properly, right after the first welcome tour and any time from
/// Settings: Full Disk Access (needed), notifications for the weekly reminder, and starting with the Mac.
/// Each row shows whether it's already allowed and updates when you come back from System Settings.
struct PermissionsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var notifications = UNAuthorizationStatus.notDetermined
    @State private var bannersOff = false
    @State private var startsWithMac = LoginItem.isEnabled

    var body: some View {
        ZStack {
            Color.black.opacity(palette.isDark ? 0.45 : 0.25)
                .ignoresSafeArea()
                .onTapGesture {}

            VStack(alignment: .leading, spacing: 0) {
                Text("A few permissions")
                    .font(.rounded(22, .bold))
                    .foregroundStyle(palette.text)
                Text("So I can do my job properly. You can change these anytime in System Settings.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                VStack(spacing: 0) {
                    row(symbol: "externaldrive", title: "Full Disk Access", needed: true,
                        text: "Lets me look into the Trash and every hidden cache. Nothing ever leaves your Mac.",
                        allowed: app.hasFullDiskAccess) {
                        Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Rectangle().fill(palette.cardStroke).frame(height: 1).padding(.leading, 58)
                    row(symbol: "bell", title: "Notifications", needed: false,
                        text: bannersOff ? "Allowed, but set to None in System Settings, so the reminder can't be seen."
                                         : "For the weekly reminder when fluff piles up.",
                        allowed: (notifications == .authorized || notifications == .provisional) && !bannersOff) {
                        Button(notifications == .denied || bannersOff ? "Open Settings" : "Allow") { allowNotifications() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Rectangle().fill(palette.cardStroke).frame(height: 1).padding(.leading, 58)
                    row(symbol: "power", title: "Start with your Mac", needed: false,
                        text: "So I'm in the menu bar whenever you need me.",
                        allowed: nil) {
                        CheckBox(isOn: Binding(get: { startsWithMac }, set: { on in
                            startsWithMac = on
                            LoginItem.setEnabled(on)
                        }), label: nil, accessibility: "Start with your Mac")
                    }
                }
                .cardSurface(palette, radius: 12)
                .padding(.top, 16)

                if !app.hasFullDiskAccess {
                    Text("In System Settings, switch on Fussel in the list. If he's not there, click + and pick Fussel from Applications. You may need to reopen Fussel afterwards.")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }

                HStack {
                    Spacer()
                    if app.hasFullDiskAccess {
                        Button("Done") { close() }
                            .buttonStyle(ActionButtonStyle())
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Later") { close() }
                            .buttonStyle(SecondaryButtonStyle())
                            .keyboardShortcut(.defaultAction)
                    }
                    Button("") { close() }
                        .keyboardShortcut(.cancelAction)
                        .frame(width: 0, height: 0)
                        .opacity(0)
                }
                .padding(.top, 16)
            }
            .padding(24)
            .frame(width: 500)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.sheet))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.cardStroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
        }
        .task { await refresh() }
        // Coming back from System Settings: look again.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
        // Full Disk Access can change while Fussel stays in front, so check now and then while this is open.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            app.refreshAccess()
        }
    }

    private func row<Action: View>(symbol: String, title: String, needed: Bool, text: String, allowed: Bool?,
                                   @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.text)
                .frame(width: 30, height: 30)
                .background(Circle().fill(palette.text.opacity(0.07)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.text)
                    if needed {
                        Text("Needed")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(palette.text.opacity(0.07)))
                    }
                }
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if allowed == true {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.safe)
            } else {
                action()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func refresh() async {
        // Screenshots run outside an app bundle, where asking about notifications isn't allowed.
        guard !PreviewRenderer.isRendering else { return }
        app.refreshAccess()
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        bannersOff = await Notifier.bannersOff
        startsWithMac = LoginItem.isEnabled
    }

    private func allowNotifications() {
        if notifications == .denied || bannersOff {
            Notifier.openSettings()
        } else {
            Task {
                _ = await Notifier.requestPermission()
                await refresh()
            }
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) { app.showPermissions = false }
    }
}
