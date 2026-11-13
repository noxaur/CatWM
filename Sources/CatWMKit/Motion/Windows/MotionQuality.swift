import CoreGraphics
import Foundation

package struct MotionQuality {
    package struct Sample: Equatable {
        package let error: Double, spill: Double, gap: Double, cover: Double, overshoot: Double
        package let lag: Double?, stutter: Double?
        package var filled: Bool { fill != nil }
        private let fill: CGRect?

        package init(desired: CGRect, actual: CGRect, fill: CGRect? = nil, lag: Double? = nil, overshoot: Double = 0,
                     stutter: Double? = nil) {
            func outward(_ inner: CGRect) -> [Double] {
                [inner.minX - actual.minX, actual.maxX - inner.maxX, inner.minY - actual.minY, actual.maxY - inner.maxY]
                    .map(Double.init)
            }
            let edges = outward(desired), most = edges.max() ?? 0, least = edges.min() ?? 0
            let open = fill.map { hole -> Double in
                let inner = desired.intersection(hole)
                return max(0, inner.isNull ? -least : -(outward(inner).min() ?? 0))
            }
            error = max(most, -least, 0)
            spill = most > 0 ? most : 0
            gap = open ?? max(0, -least)
            cover = fill == nil ? 0 : max(0, -least)
            self.lag = lag
            self.overshoot = overshoot
            self.stutter = stutter
            self.fill = fill
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
        package let error: Spread, spill: Spread, gap: Spread, cover: Spread, overshoot: Spread
        package let lag: Spread?, stutter: Spread?, tail: Spread?

        package var text: String {
            "motion (p50/p95/max) error \(error.text(1, "px")) | lag \(lag?.text(1000, "ms") ?? "-") "
                + "| spill \(spill.text(1, "px")) | gap \(gap.text(1, "px")) | cover \(cover.text(1, "px")) "
                + "| stutter \(stutter?.text(1, "px") ?? "-") | overshoot \(overshoot.text(1, "px")) "
                + "| tail \(tail?.text(1000, "ms") ?? "-") | \(samples) samples, \(filled) filled"
        }
    }

    package static let lagSpeed = 100.0
    package static let tailLimit = 0.3
    private var samples: [pid_t: [Sample]] = [:]
    private var tails: [pid_t: [Double]] = [:]

    package init() {}

    package var pids: [pid_t] { Array(samples.keys) }

    package mutating func add(_ sample: Sample, pid: pid_t) { samples[pid, default: []].append(sample) }
    package mutating func add(tail: Double, pid: pid_t) { tails[pid, default: []].append(tail) }

    package func summary(_ pid: pid_t? = nil) -> Summary? {
        let all = pid.map { samples[$0] ?? [] } ?? samples.values.flatMap(\.self)
        let tail = pid.map { tails[$0] ?? [] } ?? tails.values.flatMap(\.self)
        guard let error = Spread(all.map(\.error)), let spill = Spread(all.map(\.spill)),
              let gap = Spread(all.map(\.gap)), let cover = Spread(all.map(\.cover)),
              let overshoot = Spread(all.map(\.overshoot)) else { return nil }
        return Summary(samples: all.count, filled: all.filter(\.filled).count, error: error, spill: spill, gap: gap,
                       cover: cover, overshoot: overshoot, lag: Spread(all.compactMap(\.lag)),
                       stutter: Spread(all.compactMap(\.stutter)), tail: Spread(tail))
    }

    private static func edges(_ frame: CGRect) -> [Double] {
        [frame.minX, frame.maxX, frame.minY, frame.maxY].map(Double.init)
    }

    package static func overshoot(_ actual: CGRect, from: CGRect, to target: CGRect) -> Double {
        zip(edges(actual), zip(edges(from), edges(target))).map { value, span in
            let travel = span.1 - span.0
            return travel == 0 ? 0 : max(0, travel > 0 ? value - span.1 : span.1 - value)
        }.max() ?? 0
    }

    package static func stutter(actual: (CGRect, CGRect), desired: (CGRect, CGRect)) -> Double {
        let moved = zip(edges(actual.1), edges(actual.0)).map { $0 - $1 }
        let planned = zip(edges(desired.1), edges(desired.0)).map { $0 - $1 }
        return zip(moved, planned).map { abs($0 - $1) }.max() ?? 0
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
