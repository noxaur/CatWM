import AppKit

@MainActor package protocol WindowPresentation: AnyObject, Sendable {
    func plan(for move: Animator.Move, from: CGRect, spec: MotionSpec) -> WindowFillPlan?
    func prepare(_ plans: [CGWindowID: WindowFillPlan], moving: Set<CGWindowID>) -> Set<CGWindowID>
    func follow(_ moves: [Animator.Move])
    func update(_ frames: [CGWindowID: CGRect], observed: [CGWindowID: CGRect], expected: [CGWindowID: CGRect])
    func cancel(_ id: CGWindowID)
    func close()
    func fill(of id: CGWindowID) -> CGRect?
}
