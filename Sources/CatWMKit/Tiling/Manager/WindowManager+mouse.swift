import AppKit

extension WindowManager {
    package func mouseMoved() {
        guard focusFollowsMouseNow else { return }
        focusUnderMouse()
    }

    private var focusFollowsMouseNow: Bool {
        config.focusFollowsMouse && (!config.focusFollowsMouseInModeOnly || surface.inMode)
    }

    private func focusUnderMouse() {
        guard focusFollowsMouseNow, !closeAndSort.sortSession, Date() > ignoreMouseUntil,
              !anyButtonDown(), !desktops.movingToSpace else { return }
        let point = mouseLocation()
        guard let hit = CGWindowInfo.normalWindow(at: point), let window = windows[hit.id], visible.contains(window.id),
              focusedWindow()?.id != window.id else { return }
        Log.debug("ffm: focusing \(window.id) \(window.bundleID ?? "")")
        focus(window, warp: false)
    }

    package func mouseUp() {
        guard tabUI.drag.lifted == nil else { return }
        let point = mouseLocation()
        let joins = tabUI.drag.allowsJoin
        let hovered = joins && drags.count == 1 ? drags.first.flatMap { settledTabHover(for: $0.key, at: point) } : nil
        let previewed = tabUI.drag.finish(drags.first?.key, on: surface).preview
        if let previewed, let id = drags.first?.key, drags.count == 1, !desktops.movingToSpace {
            drags = [:]
            dropIntoStrip(id, group: previewed.group, at: previewed.index)
            return settleParkedTabs()
        }
        guard !drags.isEmpty, !desktops.movingToSpace else {
            drags = [:]
            return settleParkedTabs()
        }
        let finished = drags
        drags = [:]
        let dragged = finished.keys.compactMap { windows[$0] }
        readFrames(dragged) { [weak self] in
            guard let self else { return }
            defer { self.settleParkedTabs() }
            guard !self.primaryButtonDown(), !self.desktops.movingToSpace else { return }
            self.finishMouseDrag(finished, at: point, hovered: hovered, joins: joins)
        }
    }

    private func finishMouseDrag(_ finished: [CGWindowID: Bool], at point: CGPoint, hovered: CGWindowID?,
                                 joins: Bool) {
        let screens = backend.screens()
        var swapped: [CGWindowID: String] = [:]
        for (id, resized) in finished {
            guard let window = windows[id], let src = screen(of: window, in: screens) else { continue }
            let band = joins && holds(window, at: point) ? tabDropTarget(for: id, at: point) : nil
            if !resized, finished.count == 1, let host = band ?? hovered {
                joinTabs(of: id, onto: host)
                return
            }
            if floatsFreely(id) {
                if let dst = screen(containing: window.cachedFrame, in: screens), dst.uuid != src.uuid,
                   let workspace = shown[dst.uuid] {
                    assignManagedWindow(id, to: workspace)
                }
                continue
            }
            if resized {
                if config.mouseResizesWindows { applyMouseResize(window, on: src) }
                continue
            }
            let dst = screens.first { $0.frame.contains(point) } ?? src
            if config.mouseSwapsWindows,
               let hit = tiled(on: dst).first(where: { $0 != id && targets[$0]?.contains(point) == true }) {
                swapOrder(id, hit)
                if dst.uuid != src.uuid { swapped[hit] = src.uuid }
            } else if dst.uuid != src.uuid {
                assignTabs(of: id, to: shown[dst.uuid])
            }
        }
        corrections = [:]
        refresh(recording: swapped)
    }

    func applyMouseResize(_ window: Window, on screen: Screen) {
        let screenState = state(for: screen)
        let ids = tiled(on: screen)
        let rect = usableRect(screen), frame = window.cachedFrame
        guard !frame.isNull else { return }
        let layout = screenState.layout
        if layout == .dwindle { return dragDwindleEdges(of: window, to: frame, on: screen) }
        guard let idx = ids.firstIndex(of: window.id),
              let (mains, axis) = SplitDivider.split(layout, mainCount: screenState.mainCount, count: ids.count,
                                                     in: rect) else { return }
        let isMain = idx < mains
        let touchesSplit = switch layout {
        case .widescreenTall: !isMain || mains == 1 || idx == mains - 1
        case .widescreenTallRight: !isMain || mains == 1 || idx == 0
        case .threeColumnLeft, .threeColumnRight: isMain
        case .tall, .tallRight, .wide, .middleWide, .fullscreen, .column, .row, .floating, .bsp, .dwindle,
             .threeColumnMiddle, .twoPane, .twoPaneRight: true
        }
        guard touchesSplit else { return }
        let gap = windowGap(count: ids.count, on: screen)
        let total = axis.horizontal ? rect.width : rect.height
        func boundary(_ slot: CGRect) -> CGFloat {
            switch (axis.horizontal, axis.fromStart, isMain) {
            case (true, true, true): slot.maxX - rect.minX + gap
            case (true, true, false): slot.minX - rect.minX
            case (true, false, true): rect.maxX - slot.minX + gap
            case (true, false, false): rect.maxX - slot.maxX
            case (false, _, true): slot.maxY - rect.minY + gap
            case (false, _, false): slot.minY - rect.minY
            }
        }
        if let slot = layoutTargets(ids, screenState, on: screen)?[window.id],
           abs(boundary(slot) - screenState.ratio * (total + gap)) > 3 { return }
        screenState.ratio = SplitDivider.clamped(boundary(frame) / (total + gap))
    }
}
