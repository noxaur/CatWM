import AppKit

package struct TilingContext {
    package let window: Window?
    package let screen: Screen
    package let state: ScreenState
    package let ids: [CGWindowID]
}

extension WindowManager {
    package func context() -> TilingContext? {
        guard let screen = currentScreen() else { return nil }
        return TilingContext(window: focusedWindow(), screen: screen, state: state(for: screen), ids: tiled(on: screen))
    }
}
