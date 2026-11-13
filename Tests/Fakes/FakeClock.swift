import CatWMKit
import QuartzCore

@MainActor package final class FakeClock {
    package private(set) var time: CFTimeInterval = 0
    private var pending: [(due: CFTimeInterval, work: @MainActor () -> Void)] = []

    package nonisolated init() {}

    package func now() -> CFTimeInterval { time }

    package var nextDue: CFTimeInterval? { pending.map(\.due).min() }

    package func delay(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        pending.append((time + seconds, work))
    }

    package func advance(by seconds: TimeInterval) {
        let end = time + seconds, last = end + 1e-9
        while let next = pending.indices.min(by: { pending[$0].due < pending[$1].due }), pending[next].due <= last {
            let timer = pending.remove(at: next)
            time = max(time, timer.due)
            timer.work()
        }
        time = end
    }
}
