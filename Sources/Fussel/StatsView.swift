import SwiftUI
import AppKit

/// "Your Mac at a glance": disk, memory, battery, CPU and network as live tiles.
struct StatsRow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DiskTile()
            MemoryTile()
            BatteryTile()
            CPUTile()
            NetworkTile()
        }
        .onAppear { app.monitor.start() }
    }
}

enum StatKind {
    case disk, memory, battery, cpu, network

    var title: String {
        switch self {
        case .disk: return "Disk"
        case .memory: return "Memory"
        case .battery: return "Battery"
        case .cpu: return "CPU"
        case .network: return "Network"
        }
    }

    var symbol: String {
        switch self {
        case .disk: return "internaldrive"
        case .memory: return "memorychip"
        case .battery: return "battery.75percent"
        case .cpu: return "cpu"
        case .network: return "wifi"
        }
    }

    var pastel: Color {
        switch self {
        case .disk: return Color(hex: 0xFFD3C4)    // peach
        case .memory: return Color(hex: 0xDCD5F7)  // lavender
        case .battery: return Color(hex: 0xCFE8DC) // mint
        case .cpu: return Color(hex: 0xF9E3A0)     // butter
        case .network: return Color(hex: 0xCDE4F7) // sky
        }
    }
}

/// Shared tile frame: pastel icon, title, big value, detail, then an optional gauge and button.
private struct StatTile<Gauge: View, Footer: View>: View {
    @Environment(\.palette) private var palette
    let kind: StatKind
    var symbol: String? = nil
    let value: String
    var valueColor: Color? = nil
    let detail: String
    @ViewBuilder var gauge: Gauge
    @ViewBuilder var footer: Footer
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(palette.isDark ? kind.pastel.opacity(0.18) : kind.pastel)
                Image(systemName: symbol ?? kind.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.isDark ? kind.pastel : Theme.ink)
                    .symbolEffect(.bounce, value: hovering)
            }
            .frame(width: 30, height: 30)
            .rotationEffect(.degrees(hovering ? -10 : 0))

            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title)
                    .font(.rounded(12, .semibold))
                    .foregroundStyle(palette.secondary)
                Text(value)
                    .font(.rounded(19, .heavy))
                    .foregroundStyle(valueColor ?? palette.text)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .animation(.snappy, value: value)

            gauge
            Spacer(minLength: 0)
            footer
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 162, alignment: .topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
            ZStack {
                shape.fill(palette.card)
                // A whisper of the tile's pastel, fading out towards the bottom.
                shape.fill(LinearGradient(colors: [kind.pastel.opacity(palette.isDark ? 0.10 : 0.5), .clear],
                                          startPoint: .top, endPoint: .bottom))
            }
            .shadow(color: .black.opacity(hovering ? (palette.isDark ? 0.3 : 0.08) : 0), radius: 12, y: 6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(palette.cardStroke, lineWidth: 1)
        )
        .offset(y: hovering ? -3 : 0)
        .onHover { inside in
            withAnimation(.spring(duration: 0.35, bounce: 0.45)) { hovering = inside }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Small rounded bar used for disk and memory.
private struct FillBar: View {
    @Environment(\.palette) private var palette
    let fraction: Double
    let tint: Color
    @State private var grown = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.text.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    // A glossy stripe on top, like a candy bar.
                    .overlay(alignment: .top) {
                        Capsule().fill(.white.opacity(0.4)).frame(height: 2.5).padding(.horizontal, 4).padding(.top, 1.5)
                    }
                    .frame(width: max(9, geo.size.width * min(1, max(0, grown ? fraction : 0))))
                    .animation(.spring(duration: 0.9, bounce: 0.3), value: fraction)
            }
        }
        .frame(height: 9)
        // Fills up once when the window first appears.
        .onAppear { withAnimation(.spring(duration: 1.1, bounce: 0.35).delay(0.3)) { grown = true } }
        .accessibilityHidden(true)
    }
}

/// Small pill for the tile actions.
private struct TileButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(12, .bold))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(palette.text.opacity(configuration.isPressed ? 0.16 : 0.08)))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.5), value: configuration.isPressed)
    }
}

private func barColor(_ fraction: Double) -> Color {
    if fraction > 0.9 { return Color(hex: 0xE5484D) }
    if fraction > 0.75 { return Color(hex: 0xF5A524) }
    return Color(hex: 0x30A46C)
}

// MARK: - Tiles

private struct DiskTile: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let s = app.monitor.sample
        let used = s.diskTotal > 0 ? 1 - Double(s.diskFree) / Double(s.diskTotal) : 0
        StatTile(kind: .disk,
                 value: app.monitor.hasSample ? s.diskFree.byteString : "…",
                 detail: "free on \(s.diskName)") {
            FillBar(fraction: used, tint: barColor(used))
        } footer: {
            Button("Free Up") { Task { await app.smartScan() } }
                .buttonStyle(TileButtonStyle())
                .disabled(app.stage == .scanning || app.stage == .cleaning)
        }
    }
}

private struct MemoryTile: View {
    @Environment(AppModel.self) private var app
    @State private var showing = false

    var body: some View {
        let s = app.monitor.sample
        let free = s.memTotal > s.memUsed ? Int64(s.memTotal - s.memUsed) : 0
        let used = s.memTotal > 0 ? Double(s.memUsed) / Double(s.memTotal) : 0
        StatTile(kind: .memory,
                 value: app.monitor.hasSample ? free.byteString : "…",
                 detail: "free of \(Int64(s.memTotal).byteString)") {
            FillBar(fraction: used, tint: barColor(used))
        } footer: {
            Button("Free Up") { showing = true }
                .buttonStyle(TileButtonStyle())
                .popover(isPresented: $showing, arrowEdge: .bottom) {
                    MemoryPopover(monitor: app.monitor)
                }
        }
    }
}

private struct BatteryTile: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        let battery = app.monitor.sample.battery
        let low = (battery?.percent ?? 100) <= 20 && !(battery?.isPluggedIn ?? false)
        StatTile(kind: .battery,
                 symbol: symbol(battery),
                 value: battery.map { "\($0.percent) %" } ?? "—",
                 valueColor: low ? Color(hex: palette.isDark ? 0xFF6B6B : 0xC9302C) : nil,
                 detail: detail(battery)) {
            if let battery {
                FillBar(fraction: Double(battery.percent) / 100,
                        tint: low ? Color(hex: 0xE5484D) : Color(hex: 0x30A46C))
            }
        } footer: {
            EmptyView()
        }
    }

    private func symbol(_ b: BatteryInfo?) -> String {
        guard let b else { return "powerplug" }
        if b.isCharging { return "battery.100percent.bolt" }
        switch b.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func detail(_ b: BatteryInfo?) -> String {
        guard let b else { return "No battery" }
        if b.isCharging {
            if let m = b.minutesLeft { return "Full in \(format(m))" }
            return "Charging"
        }
        if b.isPluggedIn { return "On power" }
        if let m = b.minutesLeft { return "\(format(m)) left" }
        return "Estimating…"
    }

    private func format(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}

private struct CPUTile: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        let s = app.monitor.sample
        let load = s.cpu ?? 0
        StatTile(kind: .cpu,
                 value: s.cpu.map { "\(Int(($0 * 100).rounded())) %" } ?? "…",
                 detail: s.temperature.map { "\(Int($0.rounded())) °C" } ?? app.monitor.thermal.label) {
            FillBar(fraction: load, tint: barColor(load))
        } footer: {
            EmptyView()
        }
    }
}

private struct NetworkTile: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var showing = false

    var body: some View {
        let s = app.monitor.sample
        StatTile(kind: .network,
                 value: "↓ \(rate(s.downBytesPerSecond))",
                 detail: "↑ \(rate(s.upBytesPerSecond))") {
            Sparkline(values: app.monitor.downHistory, tint: StatKind.network.pastel, dark: palette.isDark)
                .frame(height: 18)
        } footer: {
            Button("Speed Test") {
                showing = true
                if app.monitor.speedTest != .running {
                    Task { await app.monitor.runSpeedTest() }
                }
            }
            .buttonStyle(TileButtonStyle())
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                SpeedTestPopover(monitor: app.monitor)
            }
        }
    }

    private func rate(_ bytesPerSecond: Double) -> String {
        Int64(bytesPerSecond).byteString + "/s"
    }
}

private struct Sparkline: View {
    let values: [Double]
    let tint: Color
    let dark: Bool

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let peak = max(values.max() ?? 1, 1)
            let step = size.width / CGFloat(values.count - 1)
            var line = Path()
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat(v / peak) * (size.height - 2) - 1)
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            let stroke = dark ? tint : Color(hex: 0x3B82C4)
            ctx.fill(area, with: .color(stroke.opacity(0.18)))
            ctx.stroke(line, with: .color(stroke), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Popovers

private struct MemoryPopover: View {
    let monitor: SystemMonitor
    @State private var apps: [AppMemory] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hungriest apps")
                .font(.rounded(15, .bold))
            Text("Quitting an app gives its memory back. Fussel asks the app nicely, so unsaved work is safe.")
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
                        Text(Int64(app.bytes).byteString)
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
            apps = await monitor.memoryHogs()
            loading = false
        }
    }
}

private struct SpeedTestPopover: View {
    let monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 12) {
            switch monitor.speedTest {
            case .idle, .running:
                FusselBadge(mood: .busy, size: 70)
                Text("Measuring your connection…")
                    .font(.rounded(14, .bold))
                Text("This takes about 20 seconds.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .done(let down, let up):
                FusselBadge(mood: .happy, size: 70)
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
                FusselBadge(mood: .idle, size: 70)
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
