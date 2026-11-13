import CoreGraphics
import QuartzCore

package struct StepCost: Sendable {
    private static let rise = 0.8, fall = 0.4

    package private(set) var seconds: Double?

    package var lead: Double { seconds ?? 0 }

    package mutating func add(_ cost: Double) {
        let cost = min(cost, MotionTiming.writeCostLimit)
        guard let seconds else { self.seconds = cost; return }
        self.seconds = seconds + (cost > seconds ? Self.rise : Self.fall) * (cost - seconds)
    }
}

package struct WindowWriteCost: Sendable {
    private var cost = StepCost()
    private var sampledAt: CFTimeInterval?

    package func lead(at now: CFTimeInterval) -> Double {
        guard let sampledAt, (0...MotionTiming.writeCostMemory).contains(now - sampledAt) else { return 0 }
        return cost.lead
    }

    package mutating func add(_ seconds: Double, at now: CFTimeInterval) {
        if let sampledAt, !(0...MotionTiming.writeCostMemory).contains(now - sampledAt) { cost = StepCost() }
        cost.add(seconds)
        sampledAt = now
    }
}

package struct WindowLead: Sendable {
    package enum Order: Sendable { case positionOnly, positionFirst, sizeFirst }
    package struct Times: Equatable, Sendable {
        package let position: CFTimeInterval, size: CFTimeInterval
    }
    package struct Plan: Equatable, Sendable {
        package let times: Times, order: Order, frames: [Int]
    }
    package struct Observation: Sendable {
        package let frame: CGRect, shown: CFTimeInterval, period: Double
    }
    package struct Call: Sendable {
        package let value: CGPoint, seconds: Double, finished: CFTimeInterval

        package init(_ value: CGPoint, seconds: Double, finished: CFTimeInterval) {
            (self.value, self.seconds, self.finished) = (value, seconds, finished)
        }
    }
    private struct Write: Sendable {
        let number: Int
        let calls: [Call?]
    }
    private struct Axis: Sendable {
        var cost = WindowWriteCost()
        var delays: [Double] = []
        var learnedAt: CFTimeInterval?
        var visible: CGPoint?
        var seen = 0
        var frames: Int?

        func delay(at now: CFTimeInterval) -> Double? {
            guard let learnedAt, now - learnedAt <= MotionTiming.leadMemory, !delays.isEmpty else { return nil }
            return delays.sorted()[(delays.count - 1) / 2]
        }
    }

    private var axes = [Axis(), Axis()]
    private var writes: [Write] = []
    private var written = 0
    private var observedAt: CFTimeInterval?
    package private(set) var order = Order.sizeFirst

    package init() {}

    package var inherited: WindowLead {
        var copy = WindowLead()
        copy.axes = axes.map { Axis(delays: $0.delays, learnedAt: $0.learnedAt) }
        return copy
    }

    package func delays(at now: CFTimeInterval) -> [Double?] { axes.map { $0.delay(at: now) } }

    package mutating func wrote(position: Call?, size: Call?, learns: Bool) {
        let calls = [position, size]
        if learns {
            for (axis, call) in zip(axes.indices, calls) {
                if let call { axes[axis].cost.add(call.seconds, at: call.finished) }
            }
        }
        guard position != nil || size != nil else { return }
        written += 1
        writes.append(Write(number: written, calls: calls))
        if writes.count > MotionTiming.leadHistory { writes.removeFirst(writes.count - MotionTiming.leadHistory) }
    }

    @discardableResult
    package mutating func observe(_ observation: Observation) -> Bool {
        let adjacent = observedAt.map { observation.shown - $0 < observation.period * 1.5 } ?? false
        observedAt = observation.shown
        let frame = observation.frame
        let values = [frame.origin, CGPoint(x: frame.width, y: frame.height)]
        var learned = false
        for axis in axes.indices {
            let value = values[axis]
            defer { axes[axis].visible = value }
            guard let before = axes[axis].visible, !Self.near(before, value),
                  let match = writes.lazy.compactMap({ write in write.calls[axis].map { (write.number, $0) } })
                      .first(where: { number, call in
                          number > axes[axis].seen && call.finished <= observation.shown && Self.near(call.value, value)
                      }) else { continue }
            axes[axis].seen = match.0
            guard adjacent else { continue }
            axes[axis].delays.append(min(MotionTiming.leadLimit, max(0, observation.shown - match.1.finished)))
            if axes[axis].delays.count > MotionTiming.leadSamples { axes[axis].delays.removeFirst() }
            axes[axis].learnedAt = observation.shown
            learned = true
        }
        return learned
    }

    package func plan(at now: CFTimeInterval, presentation: CFTimeInterval, period: Double,
                      order: Order? = nil) -> Plan {
        let order = order ?? self.order
        guard period > 0 else {
            return Plan(times: Times(position: presentation, size: presentation), order: order, frames: [0, 0])
        }
        let costs = axes.map { $0.cost.lead(at: now) }, delays = axes.map { $0.delay(at: now) }
        let done = switch order {
        case .positionOnly: [costs[0], costs[0]]
        case .positionFirst: [costs[0], costs[0] + costs[1]]
        case .sizeFirst: [costs[1] + costs[0], costs[1]]
        }
        let frames = axes.indices.map { axis in
            let delay = delays[axis] ?? delays[1 - axis] ?? 0
            let lead = min(MotionTiming.leadLimit, max(0, done[axis] + delay))
            let due = (now + lead - presentation) / period
            let held = axes[axis].frames.flatMap {
                abs(due - Double($0)) <= 0.5 + MotionTiming.leadHysteresis ? $0 : nil
            }
            return held ?? Int(max(0, due).rounded())
        }
        return Plan(times: Times(position: presentation + Double(frames[0]) * period,
                                 size: presentation + Double(frames[1]) * period),
                    order: order, frames: frames)
    }

    package mutating func commit(_ plan: Plan) {
        order = plan.order
        for axis in axes.indices { axes[axis].frames = plan.frames[axis] }
    }

    private static func near(_ one: CGPoint, _ other: CGPoint) -> Bool {
        abs(one.x - other.x) <= FrameTolerance.observed && abs(one.y - other.y) <= FrameTolerance.observed
    }
}
