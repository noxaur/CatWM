import CoreGraphics

package struct FollowedMoves {
    private var moves: [CGWindowID: Animator.Move] = [:]
    private var refusals: [CGWindowID: CGSize] = [:]

    package var frames: [CGWindowID: CGRect] { moves.mapValues(\.target) }

    package subscript(id: CGWindowID) -> Animator.Move? { moves[id] }

    package mutating func add(_ move: Animator.Move) { moves[move.window.id] = move }

    package mutating func remove(_ id: CGWindowID) {
        moves[id] = nil
        refusals[id] = nil
    }

    package mutating func removeAll() -> [Animator.Move] {
        defer { moves = [:]; refusals = [:] }
        return Array(moves.values)
    }

    package mutating func minimum(after move: Animator.Move, actual: CGSize?) -> CGSize? {
        let id = move.window.id
        guard moves[id] != nil, let actual else { return nil }
        guard let minimum = LandingCheck.minimum(actual, for: move.target.size) else { refusals[id] = nil; return nil }
        defer { refusals[id] = actual }
        guard let previous = refusals[id], abs(previous.width - actual.width) <= FrameTolerance.refused,
              abs(previous.height - actual.height) <= FrameTolerance.refused else { return nil }
        return minimum
    }
}
