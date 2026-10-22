import AppKit
import HypertimeCore

/// The load figures that ride along in the menu bar, one item each, in the order the metrics
/// are declared rather than the order they were switched on — so a figure always comes back to
/// the same place.
///
/// Items are created and destroyed as they are switched on and off: an `NSStatusItem` that
/// exists holds a slot in the menu bar whether or not it draws anything, and a menu bar is the
/// one place in the app where taking up room nobody asked for is rude.
@MainActor
final class LoadStatusItems {
    private var items: [SystemMetric: NSStatusItem] = [:]
    private var load = SystemLoad()

    var onClick: (() -> Void)?

    /// Switches items in and out to match the chosen set.
    func update(metrics: Set<SystemMetric>) {
        for metric in items.keys where !metrics.contains(metric) {
            if let item = items.removeValue(forKey: metric) {
                NSStatusBar.system.removeStatusItem(item)
            }
        }
        for metric in SystemMetric.allCases where metrics.contains(metric) && items[metric] == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(clicked)
            item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: Tokens.Typography.menuBarTime.size,
                                                                weight: .regular)
            items[metric] = item
        }
        redraw()
    }

    func update(load: SystemLoad) {
        self.load = load
        redraw()
    }

    var isShowing: Set<SystemMetric> { Set(items.keys) }

    private func redraw() {
        for (metric, item) in items {
            let title = "\(metric.label) \(load.percent(metric))%"
            guard item.button?.title != title else { continue }
            item.button?.title = title
            item.button?.toolTip = "\(metric.label) at \(load.percent(metric)) % of capacity"
        }
    }

    @objc private func clicked() { onClick?() }

    func tearDown() {
        for item in items.values { NSStatusBar.system.removeStatusItem(item) }
        items.removeAll()
    }
}
