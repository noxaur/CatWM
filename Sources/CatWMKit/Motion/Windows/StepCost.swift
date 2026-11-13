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
