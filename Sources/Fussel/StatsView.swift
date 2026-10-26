import SwiftUI
import AppKit

/// "Your Mac at a glance" as one quiet line: disk, memory, battery, CPU and network. Gray while all is
/// well, red where it gets tight; each value opens its details.
struct StatsLine: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let s = app.monitor.sample
        let ready = app.monitor.hasSample
        let diskUsed = s.diskTotal > 0 ? 1 - Double(s.diskFree) / Double(s.diskTotal) : 0
        let memFree = s.memTotal > s.memUsed ? Int64(s.memTotal - s.memUsed) : 0
        let memUsed = s.memTotal > 0 ? Double(s.memUsed) / Double(s.memTotal) : 0
        let battery = s.battery
        let batteryLow = (battery?.percent ?? 100) <= 20 && !(battery?.isPluggedIn ?? false)
        HStack(spacing: 12) {
            StatChip(kind: .disk, value: ready ? s.diskFree.byteString : "…", tight: diskUsed > 0.9) {
                DiskPopover(sample: s) { Task { await app.smartScan() } }
            }
            StatChip(kind: .memory, value: ready ? memFree.byteString : "…", tight: memUsed > 0.9) {
                AppsPopover(monitor: app.monitor, title: "Hungriest apps", load: { await app.monitor.memoryHogs() })
            }
            if let battery {
                StatChip(kind: .battery, symbol: BatteryPopover.symbol(battery), value: "\(battery.percent) %", tight: batteryLow) {
                    BatteryPopover(battery: battery)
                }
            }
            StatChip(kind: .cpu, value: s.cpu.map { "\(Int(($0 * 100).rounded())) %" } ?? "…", tight: (s.cpu ?? 0) > 0.9) {
                AppsPopover(monitor: app.monitor, title: "Busiest apps", load: { await app.monitor.cpuHogs() })
            }
            StatChip(kind: .network, value: Int64(s.downBytesPerSecond).byteString + "/s", tight: false) {
                SpeedTestPopover(monitor: app.monitor)
            }
        }
        .onAppear { app.monitor.start() }
    }
}

enum StatKind {
    case disk, memory, battery, cpu, network

    var title: String {
        switch self {
        case .disk: return "Free disk space"
        case .memory: return "Free memory"
        case .battery: return "Battery"
        case .cpu: return "CPU load"
        case .network: return "Download speed"
        }
    }

    var symbol: String {
        switch self {
        case .disk: return "internaldrive"
        case .memory: return "memorychip"
        case .battery: return "battery.75percent"
        case .cpu: return "cpu"
        case .network: return "arrow.down.circle"
        }
    }
}

private let warningRed = Color(hex: 0xE5484D)

/// One value in the line: a small symbol and a number. Lifts a little on hover, opens a popover.
private struct StatChip<Details: View>: View {
    @Environment(\.palette) private var palette
    let kind: StatKind
    var symbol: String? = nil
    let value: String
    let tight: Bool
    @ViewBuilder var details: Details
    @State private var showing = false
    @State private var hovering = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol ?? kind.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(value)
                    .font(.rounded(12, .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
            }
            .foregroundStyle(tight ? warningRed : palette.secondary)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .offset(y: hovering ? -2 : 0)
        }
        .buttonStyle(CardPressStyle())
        .onHover { inside in withAnimation(.spring(duration: 0.3, bounce: 0.5)) { hovering = inside } }
        .help(kind.title)
        .accessibilityLabel("\(kind.title): \(value)")
        .popover(isPresented: $showing, arrowEdge: .bottom) { details }
    }
}

/// Free space with a button to go hunting.
private struct DiskPopover: View {
    let sample: SystemSample
    let scan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(sample.diskFree.byteString) free")
                .font(.rounded(20, .heavy))
            Text("of \(sample.diskTotal.byteString) on \(sample.diskName)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Scan for fluff", action: scan)
                .controlSize(.small)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 240, alignment: .leading)
    }
}

/// Charge, time left and macOS's verdict on the battery's health.
private struct BatteryPopover: View {
    let battery: BatteryInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(battery.percent) %")
                .font(.rounded(20, .heavy))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if let health = battery.health {
                Text("Health: \(health)")
                    .font(.system(size: 12, weight: .semibold))
            }
            Button("Battery Settings") { Permissions.openBatterySettings() }
                .controlSize(.small)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 220, alignment: .leading)
    }

    static func symbol(_ b: BatteryInfo) -> String {
        if b.isCharging { return "battery.100percent.bolt" }
        switch b.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var detail: String {
        if battery.isCharging {
            if let m = battery.minutesLeft { return "Full in \(format(m))" }
            return "Charging"
        }
        if battery.isPluggedIn { return "On power" }
        if let m = battery.minutesLeft { return "\(format(m)) left" }
        return "Estimating…"
    }

    private func format(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}

// MARK: - Popovers

/// The apps using the most memory or CPU, each with a Quit button.
struct AppsPopover: View {
    let monitor: SystemMonitor
    let title: String
    let load: () async -> [AppUsage]
    @State private var apps: [AppUsage] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.rounded(15, .bold))
            Text("Quitting an app frees what it uses. Fussel asks the app nicely, so unsaved work is safe.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if loading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else if apps.isEmpty {
                Text("No apps to show.").foregroundStyle(.secondary)
            } else {
                ForEach(apps) { app in
                    HStack(spacing: 10) {
                        if let path = app.path {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable()
                                .frame(width: 22, height: 22)
                                .accessibilityHidden(true)
                        }
                        Text(app.name).lineLimit(1)
                        Spacer()
                        Text(app.cpu.map { "\(Int($0.rounded())) % CPU" } ?? Int64(app.bytes).byteString)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button("Quit") {
                            monitor.quit(app)
                            withAnimation { apps.removeAll { $0.pid == app.pid } }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .task {
            apps = await load()
            loading = false
        }
    }
}

struct SpeedTestPopover: View {
    let monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 12) {
            switch monitor.speedTest {
            case .idle, .running:
                StateIcon(symbol: "speedometer", size: 56)
                Text("Measuring your connection…")
                    .font(.rounded(14, .bold))
                Text("This takes about 20 seconds.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .done(let down, let up):
                StateIcon(symbol: "checkmark", celebrate: true, size: 56)
                HStack(spacing: 22) {
                    VStack(spacing: 2) {
                        Text("\(Int(down.rounded()))").font(.rounded(30, .heavy))
                        Text("Mbit/s down").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        Text("\(Int(up.rounded()))").font(.rounded(30, .heavy))
                        Text("Mbit/s up").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Button("Test Again") { Task { await monitor.runSpeedTest() } }
                    .controlSize(.small)
            case .failed:
                StateIcon(symbol: "wifi.exclamationmark", size: 56)
                Text("The speed test didn't work.")
                    .font(.rounded(14, .bold))
                Text("Check that you're online and try again.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Try Again") { Task { await monitor.runSpeedTest() } }
                    .controlSize(.small)
            }
        }
        .padding(18)
        .frame(width: 260)
    }
}
