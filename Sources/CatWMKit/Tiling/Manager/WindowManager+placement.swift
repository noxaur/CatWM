import AppKit

extension WindowManager {
    package func setFloating(_ floating: Bool, for window: Window) {
        guard window.isFloating != floating else { return }
        window.userFloating = .chosen(floating)
        floats.floatZoom[window.id] = nil
        if floating {
            targets[window.id] = nil
        } else {
            if let screen = screen(containing: window.cachedFrame) {
                assignManagedWindow(window.id, to: shown[screen.uuid])
            }
            corrections[window.id] = nil
        }
        refresh()
    }

    package func resizeWindow(_ window: Window, _ width: Measure, _ height: Measure) {
        guard floatsFreely(window.id) else { return resizeTiled(window, width, height) }
        guard window.resizable else { return }
        placeFloating(window) { frame, screen in
            let size = CGSize(width: width.resolve(from: frame.width, of: screen.visible.width),
                              height: height.resolve(from: frame.height, of: screen.visible.height))
            return size.width > 0 && size.height > 0 ? CGRect(origin: frame.origin, size: size) : nil
        }
    }

    package func moveWindow(_ window: Window, _ x: Measure, _ y: Measure) {
        placeFloating(window) { frame, screen in
            let visible = screen.visible
            return CGRect(x: visible.minX + x.resolve(from: frame.minX - visible.minX, of: visible.width),
                          y: visible.minY + y.resolve(from: frame.minY - visible.minY, of: visible.height),
                          width: frame.width, height: frame.height)
        }
    }

    package func centerWindow(_ window: Window) {
        placeFloating(window) { frame, screen in
            CGRect(x: screen.visible.midX - frame.width / 2, y: screen.visible.midY - frame.height / 2,
                   width: frame.width, height: frame.height)
        }
    }

    private func resizeTiled(_ window: Window, _ width: Measure, _ height: Measure) {
        guard let screen = screen(of: window) else { return }
        let screenState = state(for: screen), ids = tiled(on: screen)
        let rect = usableRect(screen)
        var axis = screenState.layout.ratioAxis
        if screenState.layout == .bsp { axis?.horizontal = rect.width >= rect.height }
        let mains = SplitDivider.mains(screenState.layout, mainCount: screenState.mainCount, count: ids.count)
        guard let horizontal = axis?.horizontal, let index = ids.firstIndex(of: window.id), ids.count > mains,
              case let measure = horizontal ? width : height, measure.relative else {
            return Log.info("resizeactive: a tiled window changes with a relative size on its layout's split axis")
        }
        let extent = horizontal ? rect.width : rect.height
        let change = measure.amount(of: extent) / extent
        adjustRatio("exact \(screenState.ratio + (index < mains ? change : -change))", on: screen)
    }

    private func placeFloating(_ window: Window, _ target: (_ frame: CGRect, _ screen: Screen) -> CGRect?) {
        guard floatsFreely(window.id), let screen = screen(of: window) else { return }
        let frame = animator.destination(window.id) ?? window.cachedFrame
        guard !frame.isNull else { return }
        guard var rect = target(frame, screen) else { return }
        rect.origin.x = max(screen.visible.minX, min(rect.minX, screen.visible.maxX - rect.width))
        rect.origin.y = max(screen.visible.minY, min(rect.minY, screen.visible.maxY - rect.height))
        floats.floatZoom[window.id] = nil
        animator.animate([.init(window: window, to: rect.pixelAligned, bounds: screen.visible)],
                         spec: motion(of: window))
    }
}
