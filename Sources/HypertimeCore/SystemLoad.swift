import Foundation

/// What the popup's load bar reports. Each metric is a fraction of the machine's capacity,
/// so 1.0 is the point where it stops coping — the common scale is the whole point of showing
/// the three side by side.
public enum SystemMetric: String, CaseIterable, Codable, Sendable {
    case cpu
    case memory
    case disk

    /// Short enough for the menu bar.
    public var label: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "RAM"
        case .disk: return "SSD"
        }
    }
}

/// One reading, every figure 0 … 1.
public struct SystemLoad: Equatable, Sendable {
    public var cpu: Double
    public var memory: Double
    public var disk: Double

    public init(cpu: Double = 0, memory: Double = 0, disk: Double = 0) {
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
    }

    public subscript(metric: SystemMetric) -> Double {
        switch metric {
        case .cpu: return cpu
        case .memory: return memory
        case .disk: return disk
        }
    }

    /// Rounded to whole percent, which is all the bar ever shows.
    public func percent(_ metric: SystemMetric) -> Int {
        Int((min(max(self[metric], 0), 1) * 100).rounded())
    }
}

/// Where a reading comes from. The app uses `MachSystemLoadSource`; tests use their own.
public protocol SystemLoadSource: AnyObject, Sendable {
    func sample() -> SystemLoad
    /// Cheap counters only, for the launch path.
    func prime()
}

public extension SystemLoadSource {
    func prime() { _ = sample() }
}

/// CPU time is reported as a running total of ticks, so usage only exists between two reads.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64 = 0, system: UInt64 = 0, idle: UInt64 = 0, nice: UInt64 = 0) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    public var busy: UInt64 { user &+ system &+ nice }
    public var total: UInt64 { busy &+ idle }
}

/// The arithmetic, kept apart from the Mach calls so it can be tested with numbers rather
/// than with a machine.
public enum SystemLoadMath {

    /// Busy share of the ticks that passed between two reads. The first read has nothing to
    /// compare against, which reads as idle rather than as a spike.
    public static func cpuUsage(from previous: CPUTicks, to current: CPUTicks) -> Double {
        let elapsed = current.total >= previous.total ? current.total - previous.total : 0
        guard elapsed > 0 else { return 0 }
        let busy = current.busy >= previous.busy ? current.busy - previous.busy : 0
        return clamped(Double(busy) / Double(elapsed))
    }

    /// Memory that cannot be handed to something else without swapping: what a process is
    /// actually using, plus what the kernel has pinned, plus what has already been squeezed.
    ///
    /// Deliberately not "total minus free". macOS fills idle memory with cache on purpose, so
    /// a free-memory figure sits near zero on a healthy machine and would cry wolf all day.
    public static func memoryUsage(active: UInt64, wired: UInt64, compressed: UInt64,
                                   pageSize: UInt64, physical: UInt64) -> Double {
        guard physical > 0 else { return 0 }
        let used = (active &+ wired &+ compressed) &* pageSize
        return clamped(Double(used) / Double(physical))
    }

    /// Share of the volume that is spoken for. `available` is the figure the system reports
    /// for important usage, which already accounts for what it could purge.
    public static func diskUsage(total: Int64, available: Int64) -> Double {
        guard total > 0 else { return 0 }
        let free = min(max(available, 0), total)
        return clamped(Double(total - free) / Double(total))
    }

    private static func clamped(_ value: Double) -> Double { min(max(value, 0), 1) }
}
