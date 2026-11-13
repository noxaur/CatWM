import AppKit

package final class ScreenState {
    package var layout: Layout
    package var ratio: CGFloat = 0.5
    package var mainCount = 1
    package var fullscreen: CGWindowID?
    var layouts: [Layout]?
    var layoutBeforeRule: Layout?
    package init(layout: Layout) { self.layout = layout }

    package func copy() -> ScreenState {
        let clone = ScreenState(layout: layout)
        clone.ratio = ratio; clone.mainCount = mainCount; clone.fullscreen = fullscreen
        clone.layouts = layouts; clone.layoutBeforeRule = layoutBeforeRule
        return clone
    }
}

extension WindowManager {
    package func state(for screen: Screen) -> ScreenState {
        state(workspace: workspaceKey(for: screen))
    }

    package func state(workspace key: String) -> ScreenState {
        if let existing = states[key] { return existing }
        let created = ScreenState(layout: config.layouts.primary)
        states[key] = created
        return created
    }
}
