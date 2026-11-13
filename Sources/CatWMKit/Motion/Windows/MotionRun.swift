import CoreGraphics
import Foundation

@MainActor package final class MotionRun {
    private struct Settling {
        let target: CGRect, end: CFTimeInterval, pid: pid_t, anchored: [Int]
        var arrived: CFTimeInterval?
    }
    package var measures = false
    package var beginRun: (String) -> (([SlowApp]) -> Void)? = { _ in nil }
    package var onEnd: ((_ ticks: Stat, _ quality: MotionQuality?) -> Void)?
    private var endRun: (([SlowApp]) -> Void)?
    private var timing = Animator.Timing()
    private var quality: MotionQuality?
    private var previous: [CGWindowID: (actual: CGRect, desired: CGRect)] = [:]
    private var arrivals: [CGWindowID: CFTimeInterval] = [:]
    private var settling: [CGWindowID: Settling] = [:]

    var isSettling: Bool { !settling.isEmpty }

    func begin(_ kind: String) {
        endRun = beginRun(kind)
        quality = Log.verbose || measures ? MotionQuality() : nil
    }

    func tick(at now: CFTimeInterval) { timing.tick(at: now) }
    func ticked(_ seconds: Double) { timing.ticks.add(seconds) }

    func finished(_ item: Animator.Item) {
        guard quality != nil else { return }
        let id = item.move.window.id
        let anchored = item.start.map {
            MotionQuality.anchored(from: item.frame(at: $0, aligned: false), to: item.move.target)
        } ?? []
        settling[id] = Settling(target: item.move.target, end: item.end ?? 0, pid: item.move.window.pid,
                                anchored: anchored, arrived: arrivals.removeValue(forKey: id))
        previous[id] = nil
    }

    func measure(_ items: [CGWindowID: Animator.Item], observed: [CGWindowID: CGRect], at time: CFTimeInterval,
                 shown: (any WindowPresentation)?, read: (CGWindowID) -> CGRect?) {
        guard quality != nil else { return }
        for (id, item) in items {
            settling[id] = nil
            guard let actual = observed[id], let start = item.start else { continue }
            let frame = { item.frame(at: $0, aligned: false) }
            let desired = frame(time), target = item.move.target, from = frame(start)
            let lag = MotionQuality.lag(at: time, actual: actual, span: start...(start + item.duration), frame: frame)
            let stutter = previous[id].map { last in
                MotionQuality.stutter(actual: (last.actual, actual), desired: (last.desired, desired))
            }
            previous[id] = (actual, desired)
            let resting = actual.approxEqual(target, tolerance: FrameTolerance.observed)
            arrivals[id] = resting ? arrivals[id] ?? time : nil
            quality?.add(.init(desired: desired, actual: actual, fill: shown?.fill(of: id), lag: lag,
                               overshoot: MotionQuality.overshoot(actual, from: from, to: target), stutter: stutter,
                               anchored: MotionQuality.anchored(from: from, to: target)),
                         pid: item.move.window.pid)
        }
        for (id, landing) in settling {
            guard let actual = read(id) else { continue }
            if let drift = MotionQuality.drift(desired: landing.target, actual: actual, fill: shown?.fill(of: id),
                                               anchored: landing.anchored) {
                quality?.add(drift: drift, pid: landing.pid)
            }
            let resting = actual.approxEqual(landing.target, tolerance: FrameTolerance.observed)
            let arrived = resting ? landing.arrived ?? time : nil
            guard arrived != nil || time - landing.end >= MotionQuality.tailLimit else {
                settling[id]?.arrived = nil
                continue
            }
            quality?.add(tail: max(0, (arrived ?? time) - landing.end), pid: landing.pid)
            settling[id] = nil
        }
    }

    func end(_ stats: [(pid_t, AXWriter.Stats)]) {
        endRun?(stats.compactMap(Animator.slowApp))
        endRun = nil
        timing.log(stats, quality: quality)
        onEnd?(timing.ticks, quality)
        timing = Animator.Timing()
        quality = nil
        previous = [:]
        arrivals = [:]
        settling = [:]
    }
}
