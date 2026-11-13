import AppKit
import Foundation
import QuartzCore

package struct Stat {
    package var count = 0, total = 0.0, max = 0.0
    package var isEmpty: Bool { count < 1 }
    package mutating func add(_ seconds: Double) { count += 1; total += seconds; max = Swift.max(max, seconds) }
    package var text: String {
        isEmpty ? "-" : String(format: "avg %.2fms max %.2fms ×%d", total / Double(count) * 1000, max * 1000, count)
    }
}

package struct SlowApp {
    package let bundle: String
    package let stepMs: Double
    package let skipped: Double
}

extension Animator {
    package static func slowApp(_ pid: pid_t, _ stats: AXWriter.Stats) -> SlowApp? {
        guard !stats.position.isEmpty,
              let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }
        let step = (stats.size.isEmpty ? 0 : stats.size.total / Double(stats.size.count))
            + stats.position.total / Double(stats.position.count)
        return .init(bundle: bundle, stepMs: step * 1000,
                     skipped: Double(stats.skipped) / Double(stats.skipped + stats.position.count))
    }

    package struct Timing {
        var ticks = Stat(), gaps = Stat()
        var firstTick: CFTimeInterval?, lastTick: CFTimeInterval?

        package mutating func tick(at now: CFTimeInterval) {
            if let lastTick { gaps.add(now - lastTick) }
            if firstTick == nil { firstTick = now }
            lastTick = now
        }

        package func log(_ writers: [(pid_t, AXWriter.Stats)], quality: MotionQuality? = nil) {
            let apps = writers.filter { $0.1.size.count + $0.1.position.count + $0.1.land.count > 0 }
            guard Log.verbose, !ticks.isEmpty else { return }
            Log.debug(String(format: "animate: %d ticks in %.0fms (display link) | tick %@ | gap %@",
                             ticks.count, (CACurrentMediaTime() - (firstTick ?? 0)) * 1000, ticks.text, gaps.text))
            let sorted = apps.sorted {
                $0.1.size.total + $0.1.position.total > $1.1.size.total + $1.1.position.total
            }
            for (pid, stats) in sorted {
                let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"
                Log.debug(
                    "animate:   \(name) (\(pid)) size \(stats.size.text) | position \(stats.position.text) "
                        + "| land \(stats.land.text) | skipped \(stats.skipped)"
                )
                if let summary = quality?.summary(pid) { Log.debug("animate:   \(name) (\(pid)) \(summary.text)") }
            }
        }
    }
}
