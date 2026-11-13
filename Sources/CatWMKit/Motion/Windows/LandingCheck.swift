import CoreGraphics

package enum LandingCheck {
    package struct Refusal: Sendable {
        package let actual: CGRect
        package let minimum: CGSize?
        package let refusedTop: Bool
    }

    package static func run(_ move: Animator.Move, writer: AXWriter, backend: any WindowBackend,
                            isCurrent: () -> Bool) -> Refusal? {
        let window = move.window, target = move.target
        var actual = window.frame
        guard isCurrent(), !window.placementSuspended, !backend.blocksPlacement(window),
              !actual.isNull, !actual.approxEqual(target, tolerance: FrameTolerance.landed) else { return nil }
        writer.suspendEnhancedUI()
        defer { writer.resumeEnhancedUI() }
        guard isCurrent(), !window.placementSuspended else { return nil }
        window.setFrame(target)
        actual = window.frame
        guard isCurrent(), !window.placementSuspended else { return nil }
        let minimum = actual.isNull ? nil : minimum(actual.size, for: target.size)
        if minimum != nil {
            var origin = target.origin
            origin.x = max(move.bounds.minX, min(origin.x, move.bounds.maxX - actual.width))
            origin.y = max(move.bounds.minY, min(origin.y, move.bounds.maxY - actual.height))
            window.setPosition(origin)
        }
        return Refusal(actual: actual, minimum: minimum,
                       refusedTop: !actual.isNull && actual.minY > target.minY + FrameTolerance.refused)
    }

    package static func minimum(_ actual: CGSize, for target: CGSize) -> CGSize? {
        let wider = actual.width > target.width + FrameTolerance.refused
        let taller = actual.height > target.height + FrameTolerance.refused
        guard wider || taller else { return nil }
        return CGSize(width: wider ? actual.width : 0, height: taller ? actual.height : 0)
    }
}
