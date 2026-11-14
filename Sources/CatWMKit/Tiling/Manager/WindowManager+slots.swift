import AppKit

extension WindowManager {
    package func windowGap(count: Int, on screen: Screen, workspace: String? = nil) -> CGFloat {
        let scoped = config(on: screen, workspace: workspace)
        return scoped.windowMargins && !(scoped.smartWindowMargins && count == 1) ? scoped.windowMarginSize : 0
    }

    package func rawSlots(
        _ ids: [CGWindowID], on screen: Screen, _ screenState: ScreenState, ratio: CGFloat, workspace: String? = nil
    ) -> ([CGRect], CGFloat)? {
        let gap = windowGap(count: ids.count, on: screen, workspace: workspace)
        let alone = ids.count == 1 ? config(on: screen, workspace: workspace).singleWindowPadding : 0
        let area = usableRect(screen, workspace: workspace).insetBy(dx: alone - gap / 2, dy: alone - gap / 2)
        let frames: [CGRect]?
        if screenState.layout == .dwindle {
            frames = screenState.withDwindle(on: dwindleDisplay(screen, screenState)) { tree in
                tree.sync(ids, minimums: dwindleMinimums(ids, gap: gap))
                return tree.frames(in: area)
            }
        } else {
            frames = screenState.layout.frames(count: ids.count, in: area, ratio: ratio,
                                               mainCount: screenState.mainCount)
        }
        guard let raw = frames else { return nil }
        let slots = raw.map { $0.insetBy(dx: gap / 2, dy: gap / 2).pixelAligned }
        guard slots.allSatisfy({ [$0.minX, $0.minY, $0.width, $0.height].allSatisfy(\.isFinite) }) else { return nil }
        return (slots, gap)
    }

    package func windowRefusingRatio(
        _ ratio: CGFloat, from old: CGFloat, ids: [CGWindowID], on screen: Screen, _ screenState: ScreenState
    ) -> CGWindowID? {
        guard ids.contains(where: { minSizes[$0] != nil }),
              let (before, _) = rawSlots(ids, on: screen, screenState, ratio: old),
              let (after, _) = rawSlots(ids, on: screen, screenState, ratio: ratio) else { return nil }
        return zip(ids, zip(before, after)).first { id, slots in
            guard let minimum = minSizes[id] else { return false }
            let (previous, next) = slots
            return (minimum.width > next.width + 1 && next.width < previous.width - 1)
                || (minimum.height > next.height + 1 && next.height < previous.height - 1)
        }?.0
    }

    package func warnTooSmall(_ id: CGWindowID, on screen: Screen?) {
        let name = windows[id].flatMap { NSRunningApplication(processIdentifier: $0.pid)?.localizedName }
            ?? "This window"
        surface.warnHUD("\(name) can't get any smaller", on: screen?.nsScreen)
    }

    package func tiled(on screen: Screen) -> [CGWindowID] {
        let shares = sharesSpaces
        return order.filter {
            visible.contains($0) && windows[$0]?.isFloating == false && workspaceOf[$0] == shown[screen.uuid]
                && !model.tabs.isBehind($0)
                && (!shares || (displayOf[$0] ?? workspaceOf[$0].flatMap { monitorOf[$0] }) == screen.uuid)
        }
    }

    package func usableRect(_ screen: Screen, workspace: String? = nil) -> CGRect {
        let scoped = config(on: screen, workspace: workspace)
        var rect = screen.visible
        if scoped.ignoreMenuBar {
            rect = CGRect(x: rect.minX, y: screen.frame.minY, width: rect.width, height: rect.maxY - screen.frame.minY)
        }
        if let height = menuBarHeights[screen.uuid]?.height(on: screen.visible),
           screen.frame.minY + height > rect.minY {
            let top = screen.frame.minY + height
            rect = CGRect(x: rect.minX, y: top, width: rect.width, height: rect.maxY - top)
        }
        if scoped.disablePaddingOnBuiltinDisplay && screen.isBuiltin { return rect }
        return Self.padded(rect, left: scoped.paddingLeft, right: scoped.paddingRight,
                           top: scoped.paddingTop, bottom: scoped.paddingBottom)
    }

    package static func padded(_ rect: CGRect, left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) -> CGRect {
        func fit(_ start: CGFloat, _ end: CGFloat, in length: CGFloat) -> (CGFloat, CGFloat) {
            let start = max(0, start), end = max(0, end), total = start + end, room = length / 2
            guard total > room, total > 0 else { return (start, end) }
            return (start * room / total, end * room / total)
        }
        let (left, right) = fit(left, right, in: rect.width), (top, bottom) = fit(top, bottom, in: rect.height)
        return CGRect(x: rect.minX + left, y: rect.minY + top,
                      width: rect.width - left - right, height: rect.height - top - bottom)
    }

    package func learnMenuBar(_ target: CGRect, _ actual: CGRect) {
        guard let screen = screen(containing: target) else { return }
        let height = actual.minY - screen.frame.minY
        guard height > 0, height <= 60,
              height > menuBarHeights[screen.uuid]?.height(on: screen.visible) ?? 0 else { return }
        menuBarHeights[screen.uuid] = MenuBarFloor(height: height, visible: screen.visible)
        Log.info("\(screen.name) keeps windows \(Int(height)) pt below its top; tiling below it")
        corrections = [:]
        refresh()
    }

    package func learnMinimum(_ id: CGWindowID, _ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, abs(size.width) < 1e5, abs(size.height) < 1e5 else { return }
        let old = minSizes[id] ?? .zero
        let new = CGSize(width: max(old.width, size.width.rounded()), height: max(old.height, size.height.rounded()))
        guard new != old else { return }
        minSizes[id] = new
        corrections[id] = nil
        Log.info("window \(id) has a minimum size of \(Int(new.width))×\(Int(new.height)); re-tiling around it")
        if let change = dividerState.ratioChange, Date() < change.until {
            dividerState.ratioChange = nil
            warnTooSmall(id, on: backend.screens().first { $0.uuid == change.screen })
        }
        if let drag = dividerState.dividerDrag, let position = drag.position,
           let screen = backend.screens().first(where: { $0.uuid == drag.screen }) {
            moveDivider(on: screen, to: position)
        }
        scheduleRefresh()
    }
}
