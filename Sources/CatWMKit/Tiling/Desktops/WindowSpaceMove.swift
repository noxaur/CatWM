import AppKit
import Foundation
import MachO
import ObjectiveC

@MainActor package struct WindowSpaceMove {
    package var membership: () -> [UInt64]
    package var submit: () -> Bool
    package var isOnScreen: () -> Bool
    package var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    package var schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter( // style-ok: polls Space membership, which has no event
            deadline: .now() + delay
        ) { work() }
    }

    package func run(to target: UInt64, waitUntilOnScreen: Bool, completion: @escaping (Bool) -> Void) {
        guard target != 0 else { completion(false); return }
        let arrived = membership() == [target]
        if arrived, !waitUntilOnScreen || isOnScreen() { completion(true); return }
        guard arrived || submit() else { completion(false); return }
        let deadline = now() + 0.5
        var retries = 0
        @MainActor func check() {
            if membership() == [target], !waitUntilOnScreen || isOnScreen() { completion(true); return }
            let remaining = deadline - now()
            guard remaining > 0 else { completion(false); return }
            let delay = retries < 4 ? 0.001 : 0.004
            retries += 1
            schedule(min(delay, remaining), check)
        }
        check()
    }
}
