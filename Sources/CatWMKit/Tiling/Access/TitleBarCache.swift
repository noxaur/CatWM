import AppKit
import CoreGraphics

@MainActor package final class TitleBarCache {
    private var entries: [CGWindowID: (width: CGFloat, bar: TitleBar)] = [:]

    package init() {}

    package func titleBar(of window: Window, on scanner: WindowScanner,
                          _ done: @escaping @MainActor (TitleBar?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        let id = window.id, width = window.cachedFrame.width, element = AXReference(window.element)
        if let entry = entries[id], entry.width == width { return done(entry.bar) }
        guard !AXStalls.shared.isStalled(window.pid) else { return done(nil) }
        scanner.run(window.pid) { [weak self] in
            let bar = TitleBar.read(element.object)
            DispatchQueue.main.async {
                if let bar { self?.entries[id] = (width, bar) }
                done(bar)
            }
        }
    }

    package func forget(_ id: CGWindowID) {
        entries[id] = nil
    }
}
