import Dispatch
import os
import Testing

final class Gate: Sendable {
    private let group = DispatchGroup()
    private let opened = OSAllocatedUnfairLock(initialState: false)
    private let limit: DispatchTimeInterval

    init(limit: DispatchTimeInterval = .seconds(120)) {
        self.limit = limit
        group.enter()
    }

    deinit { open() }

    func open() {
        guard opened.withLock({ wasOpen in defer { wasOpen = true }; return !wasOpen }) else { return }
        group.leave()
    }

    func block(sourceLocation: SourceLocation = #_sourceLocation) {
        guard group.wait(timeout: .now() + limit) == .timedOut else { return }
        recordShut(sourceLocation)
    }

    func wait(sourceLocation: SourceLocation = #_sourceLocation) async {
        let opened = await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [group, limit] in
                continuation.resume(returning: group.wait(timeout: .now() + limit) == .success)
            }
        }
        if !opened { recordShut(sourceLocation) }
    }

    private func recordShut(_ sourceLocation: SourceLocation) {
        Issue.record("The gate stayed shut for \(limit). Nothing opened it.", sourceLocation: sourceLocation)
    }

    static func bounded(sourceLocation: SourceLocation = #_sourceLocation,
                        _ work: @escaping @Sendable () async -> Void) async {
        let done = Gate()
        Task {
            await work()
            done.open()
        }
        await done.wait(sourceLocation: sourceLocation)
    }
}
