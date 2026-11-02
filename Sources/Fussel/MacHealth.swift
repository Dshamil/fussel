import Foundation
import IOKit

/// How the Mac is holding up: the battery's wear, the disk's own verdict and the last restart.
/// Only reads; nothing leaves the Mac.
struct MacHealth: Sendable, Equatable {
    /// What the battery still holds compared to when it was new, in percent. Nil on Macs without one.
    var batteryCapacity: Int?
    var batteryCycles: Int?
    /// The capacity some time ago, to see the trend.
    var batteryEarlier: BatteryReading?
    /// The disk's own self-check, as macOS reports it, e.g. "Verified". Nil when it doesn't report one.
    var diskStatus: String?
    var lastRestart: Date?

    var diskIsHealthy: Bool { diskStatus == "Verified" }

    /// "Healthy", "Check your disk", or nil when the disk doesn't report.
    var diskVerdict: String? {
        guard let diskStatus, diskStatus != "Not Supported" else { return nil }
        return diskIsHealthy ? "Healthy" : "Check your disk"
    }

    static func read() -> MacHealth {
        let battery = readBattery()
        var health = MacHealth(batteryCapacity: battery.capacity, batteryCycles: battery.cycles,
                               diskStatus: readDiskStatus(), lastRestart: readLastRestart())
        if let capacity = battery.capacity {
            let history = BatteryHistory.adding(capacity, on: Date(), to: BatteryHistory.load())
            BatteryHistory.save(history)
            health.batteryEarlier = BatteryHistory.earlier(than: Date(), in: history)
        }
        return health
    }

    /// Capacity as System Settings counts it: what a full charge holds now against what it held new.
    private static func readBattery() -> (capacity: Int?, cycles: Int?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }
        func number(_ key: String) -> Int? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        }
        return (capacity(full: number("NominalChargeCapacity"), design: number("DesignCapacity")), number("CycleCount"))
    }

    static func capacity(full: Int?, design: Int?) -> Int? {
        guard let full, let design, design > 0, full > 0 else { return nil }
        return min(100, Int((Double(full) / Double(design) * 100).rounded()))
    }

    private static func readDiskStatus() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return info?["SMARTStatus"] as? String
    }

    private static func readLastRestart() -> Date? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
    }
}

struct BatteryReading: Codable, Sendable, Equatable {
    var date: Date
    var capacity: Int
}

/// One reading of the battery's capacity a month, so the slow trend can be shown.
/// Stored in ~/Library/Application Support/Fussel/battery.json.
enum BatteryHistory {
    private static var file: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fussel", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("battery.json")
    }

    static func load() -> [BatteryReading] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([BatteryReading].self, from: $0) } ?? []
    }

    static func save(_ readings: [BatteryReading]) {
        if let data = try? JSONEncoder().encode(readings) { try? data.write(to: file, options: .atomic) }
    }

    /// Adds a reading unless this month has one, keeping the last five years.
    static func adding(_ capacity: Int, on date: Date, to readings: [BatteryReading]) -> [BatteryReading] {
        let calendar = Calendar.current
        if readings.contains(where: { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }) { return readings }
        return Array((readings + [BatteryReading(date: date, capacity: capacity)]).suffix(60))
    }

    /// The reading closest to a year ago, or else the oldest one, if it's at least a month old.
    static func earlier(than now: Date, in readings: [BatteryReading]) -> BatteryReading? {
        let month = 30 * 86_400.0, year = 365 * 86_400.0
        return readings
            .filter { now.timeIntervalSince($0.date) >= month }
            .min { abs(now.timeIntervalSince($0.date) - year) < abs(now.timeIntervalSince($1.date) - year) }
    }
}
