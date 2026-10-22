import Foundation
import Testing
@testable import HypertimeCore

@Suite("SystemLoad")
struct SystemLoadTests {

    @Test("CPU usage is the busy share of the ticks between two reads")
    func cpu() {
        let first = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let second = CPUTicks(user: 140, system: 70, idle: 1790, nice: 0)   // 60 busy of 1000
        #expect(abs(SystemLoadMath.cpuUsage(from: first, to: second) - 0.06) < 0.0001)
        // Nothing to compare against yet, and a counter that went backwards after a wake:
        // both read as idle rather than as a spike.
        #expect(SystemLoadMath.cpuUsage(from: second, to: second) == 0)
        #expect(SystemLoadMath.cpuUsage(from: second, to: first) == 0)
    }

    @Test("CPU usage never leaves the 0…1 scale the bar is drawn on")
    func cpuBounds() {
        let idle = CPUTicks(user: 0, system: 0, idle: 1000, nice: 0)
        let pinned = CPUTicks(user: 1000, system: 0, idle: 1000, nice: 0)
        #expect(SystemLoadMath.cpuUsage(from: idle, to: pinned) == 1)
        #expect(SystemLoadMath.cpuUsage(from: idle, to: CPUTicks(user: 0, system: 0, idle: 2000)) == 0)
    }

    @Test("memory counts what cannot be given away, not what is merely occupied")
    func memory() {
        let page: UInt64 = 16_384
        let physical: UInt64 = 16 * 1024 * 1024 * 1024
        let quarter = physical / 4 / page
        // A machine with a quarter of its RAM genuinely spoken for reads 25 %, however much
        // of the rest macOS is holding as cache.
        #expect(abs(SystemLoadMath.memoryUsage(active: quarter, wired: 0, compressed: 0,
                                               pageSize: page, physical: physical) - 0.25) < 0.0001)
        #expect(abs(SystemLoadMath.memoryUsage(active: quarter / 2, wired: quarter / 4,
                                               compressed: quarter / 4,
                                               pageSize: page, physical: physical) - 0.25) < 0.0001)
        #expect(SystemLoadMath.memoryUsage(active: 0, wired: 0, compressed: 0,
                                           pageSize: page, physical: 0) == 0)
    }

    @Test("disk is the share of the volume that is spoken for")
    func disk() {
        #expect(SystemLoadMath.diskUsage(total: 1000, available: 250) == 0.75)
        #expect(SystemLoadMath.diskUsage(total: 1000, available: 0) == 1)
        #expect(SystemLoadMath.diskUsage(total: 1000, available: 1000) == 0)
        // Nonsense from the filesystem must not produce a bar outside its own track.
        #expect(SystemLoadMath.diskUsage(total: 1000, available: -5) == 1)
        #expect(SystemLoadMath.diskUsage(total: 1000, available: 9999) == 0)
        #expect(SystemLoadMath.diskUsage(total: 0, available: 0) == 0)
    }

    @Test("a reading rounds to the whole percent the bar shows")
    func percent() {
        let load = SystemLoad(cpu: 0.234, memory: 0.615, disk: 1.4)
        #expect(load.percent(.cpu) == 23)
        #expect(load.percent(.memory) == 62)
        #expect(load.percent(.disk) == 100)
        #expect(load[.memory] == 0.615)
    }

    @Test("the real source answers, and answers inside the scale")
    func machSource() {
        let source = MachSystemLoadSource()
        _ = source.sample()                       // the first read has no CPU delta to work from
        let load = source.sample()
        for metric in SystemMetric.allCases {
            #expect(load[metric] >= 0 && load[metric] <= 1, "\(metric) out of range: \(load[metric])")
        }
        // A machine running a test suite has some memory in use and some disk written.
        #expect(load.memory > 0)
        #expect(load.disk > 0)
    }
}
