import Darwin
import Foundation

/// Reads the three figures from the kernel. Foundation and Mach only — nothing here needs a
/// window, so it stays in core with the rest of the testable work (`SystemLoadMath` holds the
/// arithmetic; this file only fetches numbers and hands them over).
///
/// Every call is a counter read: no sampling thread, no polling of its own, and nothing that
/// needs a permission. The disk figure is cached, because a volume's capacity does not move
/// fast enough to be worth a filesystem round trip every second.
public final class MachSystemLoadSource: SystemLoadSource, @unchecked Sendable {
    private let lock = NSLock()
    private var previousTicks: CPUTicks?
    private var cachedDisk: Double = 0
    private var diskReadAt: Date = .distantPast
    private let diskInterval: TimeInterval
    private let clock: Clock
    private let volume: URL

    public init(clock: Clock = SystemClock(), volume: URL = URL(fileURLWithPath: "/"),
                diskInterval: TimeInterval = 30) {
        self.clock = clock
        self.volume = volume
        self.diskInterval = diskInterval
    }

    /// Reads the counters without touching the filesystem. Used at launch: processor usage
    /// needs a previous read to exist before the first real one means anything, but asking a
    /// 90 %-full volume for its capacity is a round trip nobody should wait on to see a menu
    /// bar icon. The disk figure arrives with the first heartbeat instead.
    public func prime() {
        lock.lock()
        defer { lock.unlock() }
        if let ticks = Self.cpuTicks() { previousTicks = ticks }
    }

    public func sample() -> SystemLoad {
        lock.lock()
        defer { lock.unlock() }

        var load = SystemLoad()

        if let ticks = Self.cpuTicks() {
            if let previous = previousTicks {
                load.cpu = SystemLoadMath.cpuUsage(from: previous, to: ticks)
            }
            previousTicks = ticks
        }

        if let memory = Self.memory() {
            load.memory = SystemLoadMath.memoryUsage(
                active: memory.active, wired: memory.wired, compressed: memory.compressed,
                pageSize: memory.pageSize, physical: ProcessInfo.processInfo.physicalMemory)
        }

        let now = clock.now()
        if now.timeIntervalSince(diskReadAt) >= diskInterval {
            diskReadAt = now
            if let disk = disk() { cachedDisk = disk }
        }
        load.disk = cachedDisk

        return load
    }

    // MARK: - Kernel reads

    private static func cpuTicks() -> CPUTicks? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size
                                          / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: UInt64(info.cpu_ticks.0),
                        system: UInt64(info.cpu_ticks.1),
                        idle: UInt64(info.cpu_ticks.2),
                        nice: UInt64(info.cpu_ticks.3))
    }

    private struct Memory {
        var active: UInt64
        var wired: UInt64
        var compressed: UInt64
        var pageSize: UInt64
    }

    private static func memory() -> Memory? {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
                                          / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Memory(active: UInt64(stats.active_count),
                      wired: UInt64(stats.wire_count),
                      compressed: UInt64(stats.compressor_page_count),
                      pageSize: UInt64(sysconf(_SC_PAGESIZE)))
    }

    private func disk() -> Double? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? volume.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return SystemLoadMath.diskUsage(total: Int64(total), available: available)
    }
}
