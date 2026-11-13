import CoreGraphics
import Foundation

package struct MotionQuality {
    package struct Sample: Equatable {
        package let error: Double, spill: Double, gap: Double
        package let lag: Double?
        package let filled: Bool

        package init(desired: CGRect, actual: CGRect, filled: Bool, lag: Double? = nil) {
            let outward = [desired.minX - actual.minX, actual.maxX - desired.maxX,
                           desired.minY - actual.minY, actual.maxY - desired.maxY].map(Double.init)
            let most = outward.max() ?? 0, least = outward.min() ?? 0
            error = max(most, -least, 0)
            spill = most > 0 ? most : 0
            gap = filled || least >= 0 ? 0 : -least
            self.lag = lag
            self.filled = filled
        }
    }

    package struct Spread: Equatable {
        package let p50: Double, p95: Double, max: Double

        package init?(_ values: [Double]) {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            func rank(_ share: Double) -> Double { sorted[Swift.max(0, Int(ceil(share * Double(sorted.count))) - 1)] }
            p50 = rank(0.5)
            p95 = rank(0.95)
            max = sorted[sorted.count - 1]
        }

        func text(_ scale: Double, _ unit: String) -> String {
            String(format: "%.1f/%.1f/%.1f%@", p50 * scale, p95 * scale, max * scale, unit)
        }
    }

    package struct Summary {
        package let samples: Int, filled: Int
        package let error: Spread, spill: Spread, gap: Spread
        package let lag: Spread?

        package var text: String {
            "motion (p50/p95/max) error \(error.text(1, "px")) | lag \(lag?.text(1000, "ms") ?? "-") "
                + "| spill \(spill.text(1, "px")) | gap \(gap.text(1, "px")) | \(samples) samples, \(filled) filled"
        }
    }

    package static let lagSpeed = 100.0
    private var samples: [pid_t: [Sample]] = [:]

    package init() {}

    package var pids: [pid_t] { Array(samples.keys) }

    package mutating func add(_ sample: Sample, pid: pid_t) { samples[pid, default: []].append(sample) }

    package func summary(_ pid: pid_t? = nil) -> Summary? {
        let all = pid.map { samples[$0] ?? [] } ?? samples.values.flatMap(\.self)
        guard let error = Spread(all.map(\.error)), let spill = Spread(all.map(\.spill)),
              let gap = Spread(all.map(\.gap)) else { return nil }
        return Summary(samples: all.count, filled: all.filter(\.filled).count, error: error, spill: spill, gap: gap,
                       lag: Spread(all.compactMap(\.lag)))
    }

    package static func lag(at shown: Double, actual: CGRect, span: ClosedRange<Double>,
                            frame: (Double) -> CGRect) -> Double? {
        let edges: [KeyPath<CGRect, CGFloat>] = [\.minX, \.maxX, \.minY, \.maxY]
        let probe = 1e-3, before = frame(shown - probe), after = frame(shown + probe)
        let speeds = edges.map { abs(after[keyPath: $0] - before[keyPath: $0]) / (2 * probe) }
        guard span.upperBound > span.lowerBound, let fastest = speeds.indices.max(by: { speeds[$0] < speeds[$1] }),
              speeds[fastest] >= lagSpeed else { return nil }
        let edge = edges[fastest], value = actual[keyPath: edge]
        func closest(_ times: [Double]) -> Double {
            let misses = times.map { abs(frame($0)[keyPath: edge] - value) }
            let least = misses.min() ?? 0
            return zip(times, misses).filter { $0.1 <= least + 0.05 }.map(\.0)
                .min { abs($0 - shown) < abs($1 - shown) } ?? shown
        }
        func grid(_ range: ClosedRange<Double>, _ step: Double) -> [Double] {
            Array(stride(from: range.lowerBound, through: range.upperBound, by: step)) + [range.upperBound]
        }
        let coarse = closest(grid(span, 2e-3))
        let fine = closest(grid(max(span.lowerBound, coarse - 2e-3)...min(span.upperBound, coarse + 2e-3), 1e-4))
        return shown - fine
    }
}

@MainActor package final class MotionRun {
    package var measures = false
    package var readFrame: @MainActor (CGWindowID) -> CGRect?
    package var beginRun: (String) -> (([SlowApp]) -> Void)? = { _ in nil }
    package var onEnd: ((_ ticks: Stat, _ quality: MotionQuality?) -> Void)?
    private var endRun: (([SlowApp]) -> Void)?
    private var timing = Animator.Timing()
    private var quality: MotionQuality?

    init(readFrame: @escaping @MainActor (CGWindowID) -> CGRect?) { self.readFrame = readFrame }

    func begin(_ kind: String) {
        endRun = beginRun(kind)
        quality = Log.verbose || measures ? MotionQuality() : nil
    }

    func tick(at now: CFTimeInterval) { timing.tick(at: now) }
    func ticked(_ seconds: Double) { timing.ticks.add(seconds) }

    func measure(_ items: [CGWindowID: Animator.Item], at time: CFTimeInterval, shown: (any WindowPresentation)?) {
        guard quality != nil else { return }
        for (id, item) in items {
            guard let actual = readFrame(id) else { continue }
            let frame = { item.frame(at: $0, aligned: false) }
            let lag = MotionQuality.lag(at: time, actual: actual, span: item.start...(item.start + item.duration),
                                        frame: frame)
            quality?.add(.init(desired: frame(time), actual: actual, filled: shown?.isFilling(id) == true, lag: lag),
                         pid: item.move.window.pid)
        }
    }

    func end(_ stats: [(pid_t, AXWriter.Stats)]) {
        endRun?(stats.compactMap(Animator.slowApp))
        endRun = nil
        timing.log(stats, quality: quality)
        onEnd?(timing.ticks, quality)
        timing = Animator.Timing()
        quality = nil
    }
}
