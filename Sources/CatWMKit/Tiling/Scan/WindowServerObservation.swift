import AppKit

package struct WindowServerObservation {
    package var windows: [CGWindowInfo] = []
    package var allWindows: [CGWindowInfo] = []
    package var spaces: [CGWindowID: Set<UInt64>] = [:]

    package init(windows: [CGWindowInfo] = [], allWindows: [CGWindowInfo] = [],
                 spaces: [CGWindowID: Set<UInt64>] = [:]) {
        (self.windows, self.allWindows, self.spaces) = (windows, allWindows, spaces)
    }

    package func keeping(_ keep: (pid_t) -> Bool) -> Self {
        Self(windows: windows.filter { keep($0.pid) }, allWindows: allWindows.filter { keep($0.pid) }, spaces: spaces)
    }

    package static func read(known: Set<CGWindowID>) -> Self {
        dispatchPrecondition(condition: .onQueue(.main))
        if let observation = WindowServerQuery.observation(known: known) { return observation }
        let windows = CGWindowInfo.onScreen()
        let all = CGWindowInfo.onScreen(options: [.optionAll, .excludeDesktopElements])
        let ids = known.union(all.map(\.id))
        return Self(windows: windows, allWindows: all,
                    spaces: WindowServerQuery.memberships(for: ids))
    }
}
