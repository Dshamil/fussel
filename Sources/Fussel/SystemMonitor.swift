import Foundation
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Values

struct BatteryInfo: Sendable, Equatable {
    var percent: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    /// Minutes until empty (on battery) or full (charging); nil while macOS is still estimating.
    var minutesLeft: Int?
    /// macOS's own verdict, e.g. "Good" or "Fair"; nil on Macs that don't report it.
    var health: String? = nil
}

struct SystemSample: Sendable {
    var diskName = "Macintosh HD"
    var diskFree: Int64 = 0
    var diskTotal: Int64 = 0
    var memUsed: UInt64 = 0
    var memTotal: UInt64 = 0
    var battery: BatteryInfo?
    var cpu: Double?
    var temperature: Double?
    var downBytesPerSecond: Double = 0
    var upBytesPerSecond: Double = 0
}

/// A running app and how much it uses: memory in bytes, or CPU as a share of one core.
struct AppUsage: Identifiable, Sendable {
    var id: pid_t { pid }
    let pid: pid_t
    let name: String
    var bytes: UInt64 = 0
    var cpu: Double? = nil
    let path: String?
}

enum SpeedTestState: Equatable {
    case idle, running
    case done(downMbps: Double, upMbps: Double)
    case failed
}

// MARK: - Live model

/// Polls the Mac's vital signs every two seconds while the window is open.
@Observable
@MainActor
final class SystemMonitor {
    var sample = SystemSample()
    /// The disk's size on its own: it never changes, so views that only need it (like a tool's share of
    /// the disk) aren't redrawn with every new sample.
    var diskTotal: Int64 = 0
    var downHistory: [Double] = Array(repeating: 0, count: 30)
    var thermal: ProcessInfo.ThermalState = .nominal
    var speedTest: SpeedTestState = .idle
    var hasSample = false

    private var loop: Task<Void, Never>?
    private let sampler = Sampler()
    /// Every 2 s while the window is open, every 30 s in the background (just enough for Fussel's mood).
    private(set) var fast = true
    /// Ends the current pause early, e.g. when the window opens.
    private var wakeNow = false
    private var forceDisk = false

    /// One loop for the app's whole life, so only one sample ever runs at a time.
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                var waited = 0.0
                while !Task.isCancelled {
                    guard let self else { return }
                    if self.wakeNow || waited >= (self.fast ? 2.0 : 30.0) { break }
                    try? await Task.sleep(for: .seconds(1))
                    waited += 1
                }
                self?.wakeNow = false
            }
        }
    }

    /// Switch between live updates (window open) and a slow background pace.
    func setFast(_ isFast: Bool) {
        guard isFast != fast else { return }
        fast = isFast
        if isFast { wakeNow = true }
    }

    /// Read free disk space again on the next tick (after cleaning).
    func refreshDisk() {
        forceDisk = true
        wakeNow = true
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    private func tick() async {
        let sampler = self.sampler
        let force = forceDisk
        forceDisk = false
        let next = await Task.detached(priority: .utility) { sampler.sample(forceDisk: force) }.value
        sample = next
        if next.diskTotal != diskTotal { diskTotal = next.diskTotal }
        hasSample = true
        thermal = ProcessInfo.processInfo.thermalState
        downHistory.append(next.downBytesPerSecond)
        if downHistory.count > 30 { downHistory.removeFirst(downHistory.count - 30) }
    }

    func runSpeedTest() async {
        speedTest = .running
        let result = await Task.detached(priority: .userInitiated) { SpeedTest.run() }.value
        if let result {
            speedTest = .done(downMbps: result.down, upMbps: result.up)
        } else {
            speedTest = .failed
        }
    }

    func memoryHogs() async -> [AppUsage] {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .map { ($0.processIdentifier, $0.localizedName ?? "App", $0.bundleURL?.path) }
        return await Task.detached(priority: .userInitiated) {
            apps.compactMap { pid, name, path -> AppUsage? in
                guard let bytes = Sampler.footprint(of: pid) else { return nil }
                return AppUsage(pid: pid, name: name, bytes: bytes, path: path)
            }
            .sorted { $0.bytes > $1.bytes }
            .prefix(6)
            .map { $0 }
        }.value
    }

    /// The apps using the most CPU right now, read from `ps` (percent of one core).
    func cpuHogs() async -> [AppUsage] {
        let apps = Dictionary(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
                .map { ($0.processIdentifier, ($0.localizedName ?? "App", $0.bundleURL?.path)) },
            uniquingKeysWith: { first, _ in first })
        return await Task.detached(priority: .userInitiated) {
            let ps = Process()
            ps.executableURL = URL(fileURLWithPath: "/bin/ps")
            ps.arguments = ["-Aeo", "pid=,pcpu="]
            let pipe = Pipe()
            ps.standardOutput = pipe
            guard (try? ps.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            ps.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .compactMap { line -> AppUsage? in
                    let parts = line.split(separator: " ")
                    guard parts.count == 2, let pid = pid_t(parts[0]), let cpu = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
                          let app = apps[pid] else { return nil }
                    return AppUsage(pid: pid, name: app.0, cpu: cpu, path: app.1)
                }
                .sorted { ($0.cpu ?? 0) > ($1.cpu ?? 0) }
                .prefix(6)
                .map { $0 }
        }.value
    }

    func quit(_ app: AppUsage) {
        NSRunningApplication(processIdentifier: app.pid)?.terminate()
    }
}

// MARK: - Readers

/// Keeps the previous CPU and network counters to compute rates.
/// Only SystemMonitor's single loop calls it, one sample at a time.
final class Sampler: @unchecked Sendable {
    private var lastTicks: [UInt64]?
    private var lastNet: (rx: UInt64, tx: UInt64, time: Date)?
    private var smc = SMC()
    private var lastDisk: (name: String, total: Int64, free: Int64, time: Date)?
    /// `forceDisk` after cleaning, so the disk tile shows the new free space right away.
    func sample(forceDisk: Bool) -> SystemSample {
        var s = SystemSample()

        // Free space is comparatively expensive for macOS to work out: refresh it every ~30 s.
        if lastDisk == nil || Date().timeIntervalSince(lastDisk!.time) > 28 || forceDisk {
            let root = URL(fileURLWithPath: "/")
            if let v = try? root.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey,
                                                          .volumeAvailableCapacityForImportantUsageKey]) {
                lastDisk = (v.volumeName ?? "Macintosh HD", Int64(v.volumeTotalCapacity ?? 0),
                            v.volumeAvailableCapacityForImportantUsage ?? 0, Date())
            }
        }
        if let disk = lastDisk {
            s.diskName = disk.name
            s.diskTotal = disk.total
            s.diskFree = disk.free
        }

        let mem = Self.memory()
        s.memUsed = mem.used
        s.memTotal = mem.total
        s.battery = Self.battery()
        s.cpu = cpuUsage()

        let net = Self.networkBytes()
        let now = Date()
        if let last = lastNet {
            let dt = max(0.2, now.timeIntervalSince(last.time))
            s.downBytesPerSecond = net.rx >= last.rx ? Double(net.rx - last.rx) / dt : 0
            s.upBytesPerSecond = net.tx >= last.tx ? Double(net.tx - last.tx) / dt : 0
        }
        lastNet = (net.rx, net.tx, now)

        s.temperature = smc?.cpuTemperature()
        return s
    }

    static func memory() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        let page = UInt64(vm_kernel_page_size)
        let appPages = UInt64(stats.internal_page_count) * page
        let purgeable = UInt64(stats.purgeable_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        // Same idea as Activity Monitor's "Memory Used": app memory + wired + compressed.
        let used = (appPages > purgeable ? appPages - purgeable : 0) + wired + compressed
        return (min(used, total), total)
    }

    func cpuUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        let current = [UInt64(t.0), UInt64(t.1), UInt64(t.2), UInt64(t.3)] // user, system, idle, nice
        defer { lastTicks = current }
        guard let last = lastTicks else { return nil }
        let d = zip(current, last).map { $0 >= $1 ? $0 - $1 : 0 }
        let busy = d[0] + d[1] + d[3]
        let total = busy + d[2]
        return total > 0 ? Double(busy) / Double(total) : nil
    }

    static func battery() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(1, desc[kIOPSMaxCapacityKey] as? Int ?? 100)
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let plugged = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let minutesKey = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = desc[minutesKey] as? Int
            return BatteryInfo(
                percent: Int((Double(current) / Double(maximum) * 100).rounded()),
                isCharging: charging,
                isPluggedIn: plugged,
                minutesLeft: (minutes ?? -1) > 0 ? minutes : nil,
                health: desc[kIOPSBatteryHealthKey] as? String
            )
        }
        return nil
    }

    static func networkBytes() -> (rx: UInt64, tx: UInt64) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return (0, 0) }
        defer { freeifaddrs(head) }
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let ifa = entry.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               let data = ifa.ifa_data, String(cString: ifa.ifa_name).hasPrefix("en") {
                let counters = data.assumingMemoryBound(to: if_data.self).pointee
                rx += UInt64(counters.ifi_ibytes)
                tx += UInt64(counters.ifi_obytes)
            }
            cursor = ifa.ifa_next
        }
        return (rx, tx)
    }

    /// Physical memory footprint of a process, the number Activity Monitor shows.
    static func footprint(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }
}

// MARK: - Speed test

enum SpeedTest {
    /// Runs Apple's built-in `networkQuality` tool and returns Mbit/s.
    static func run() -> (down: Double, up: Double)? {
        let tool = URL(fileURLWithPath: "/usr/bin/networkQuality")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { return nil }
        let process = Process()
        process.executableURL = tool
        process.arguments = ["-c"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func number(_ key: String) -> Double? {
            if let d = json[key] as? Double { return d }
            if let i = json[key] as? Int { return Double(i) }
            return nil
        }
        guard let down = number("dl_throughput"), let up = number("ul_throughput") else { return nil }
        return (down / 1_000_000, up / 1_000_000)
    }
}

// MARK: - SMC (temperature)

/// Reads temperature sensors from the System Management Controller. Works without admin rights
/// on Intel and Apple silicon; returns nil when no known sensor answers.
final class SMC {
    private var connection: io_connect_t = 0

    private struct Version {
        var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
        var release: UInt16 = 0
    }
    private struct PLimit {
        var version: UInt16 = 0, length: UInt16 = 0
        var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0
    }
    private struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }
    /// Mirrors SMCKeyData_t (80 bytes); `padding` keeps `result` at offset 40 like the C struct.
    private struct Param {
        var key: UInt32 = 0
        var vers = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    /// CPU die sensors for Intel, M1, M2 and M3/M4 chips.
    private static let cpuKeys = [
        "TC0P", "TC0D", "TC0E", "TC0F",
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",
        "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp0f", "Tp0j",
        "Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
    ]
    private var workingKeys: [String]?

    init?() {
        guard MemoryLayout<Param>.stride == 80 else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit {
        IOServiceClose(connection)
    }

    func cpuTemperature() -> Double? {
        let keys = workingKeys ?? Self.cpuKeys
        var found: [String] = []
        var values: [Double] = []
        for key in keys {
            if let t = read(key), t > 5, t < 125 {
                found.append(key)
                values.append(t)
            }
        }
        if workingKeys == nil { workingKeys = found }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func code(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func call(_ input: inout Param) -> Param? {
        var output = Param()
        var size = MemoryLayout<Param>.stride
        let result = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<Param>.stride, &output, &size)
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    private func read(_ key: String) -> Double? {
        var infoRequest = Param()
        infoRequest.key = Self.code(key)
        infoRequest.data8 = 9 // read key info
        guard let info = call(&infoRequest), info.keyInfo.dataSize > 0 else { return nil }

        var readRequest = Param()
        readRequest.key = infoRequest.key
        readRequest.keyInfo.dataSize = info.keyInfo.dataSize
        readRequest.data8 = 5 // read bytes
        guard let out = call(&readRequest) else { return nil }

        let b = out.bytes
        switch info.keyInfo.dataType {
        case Self.code("flt "):
            let bits = UInt32(b.0) | UInt32(b.1) << 8 | UInt32(b.2) << 16 | UInt32(b.3) << 24
            return Double(Float(bitPattern: bits))
        case Self.code("sp78"):
            let raw = Int16(bitPattern: UInt16(b.0) << 8 | UInt16(b.1))
            return Double(raw) / 256
        default:
            return nil
        }
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Very hot"
        @unknown default: return "—"
        }
    }
}
