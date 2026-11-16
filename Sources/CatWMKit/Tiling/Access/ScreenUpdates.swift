import os

enum ScreenUpdates {
    private typealias Toggle = @convention(c) () -> Void
    private static let disable: Toggle? = symbol(
        "NSDisableScreenUpdates", in: "/System/Library/Frameworks/AppKit.framework/AppKit")
    private static let enable: Toggle? = symbol(
        "NSEnableScreenUpdates", in: "/System/Library/Frameworks/AppKit.framework/AppKit")
    private struct State { var holds = 0, disabled = false }
    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func perform(_ body: () -> Void) {
        guard let disable, let enable else { body(); return }
        let begin = state.withLock { state -> Bool in
            state.holds += 1
            guard !state.disabled else { return false }
            state.disabled = true
            return true
        }
        if begin { disable() }
        defer {
            let end = state.withLock { state -> Bool in
                state.holds = max(0, state.holds - 1)
                guard state.holds == 0, state.disabled else { return false }
                state.disabled = false
                return true
            }
            if end { enable() }
        }
        body()
    }
}
