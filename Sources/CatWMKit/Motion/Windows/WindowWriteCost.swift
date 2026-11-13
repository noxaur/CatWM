import CoreGraphics
import QuartzCore

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
