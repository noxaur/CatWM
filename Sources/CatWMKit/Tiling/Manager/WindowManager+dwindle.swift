import AppKit

extension WindowManager {
    private struct DwindleInput {
        let ids: [CGWindowID]
        let area: CGRect
    }

    @discardableResult
    package func changeDwindle(of target: Window? = nil,
                               _ change: (inout DwindleTree, _ index: Int, _ area: CGRect) -> Void) -> Bool {
        guard let window = target ?? focusedWindow(), let screen = screen(of: window),
              let tree = dwindleTree(on: screen), let index = tree.ids.firstIndex(of: window.id) else { return false }
        withDwindle(on: screen) { change(&$0, index, tree.area) }
        refresh()
        return true
    }

    package func dwindle(on screen: Screen) -> DwindleTree {
        let screenState = state(for: screen)
        return screenState.dwindles[dwindleDisplay(screen, screenState)] ?? DwindleTree()
    }

    @discardableResult
    package func withDwindle<Result>(on screen: Screen, _ body: (inout DwindleTree) -> Result) -> Result {
        let screenState = state(for: screen)
        return screenState.withDwindle(on: dwindleDisplay(screen, screenState), body)
    }

    func dwindleDisplay(_ screen: Screen, _ screenState: ScreenState) -> String {
        guard screenState.dwindles[screen.uuid] == nil, !screenState.dwindles.isEmpty else { return screen.uuid }
        let screens = backend.screens(), live = Set(screens.map(\.uuid))
        let showing = Set(screens.filter { state(for: $0) === screenState }.map(\.uuid))
        screenState.dwindles = screenState.dwindles.filter { live.contains($0.key) }
        if let idle = screenState.dwindles.keys.sorted().first(where: { !showing.contains($0) }) {
            screenState.dwindles[screen.uuid] = screenState.dwindles.removeValue(forKey: idle)
        }
        return screen.uuid
    }

    package func resizeWindow(_ window: Window, by delta: CGSize) {
        if changeDwindle(of: window, { $0.resize(at: $1, by: delta, in: $2) }) { return }
        let frame = animator.destination(window.id) ?? window.cachedFrame
        guard !frame.isNull else { return }
        resizeWindow(window, to: CGSize(width: max(1, frame.width + delta.width),
                                        height: max(1, frame.height + delta.height)))
    }

    func dragDwindleEdges(of window: Window, to frame: CGRect, on screen: Screen) {
        let screenState = state(for: screen)
        guard let tree = dwindleTree(on: screen), let index = tree.ids.firstIndex(of: window.id),
              let slot = layoutTargets(tree.ids, screenState, on: screen)?[window.id] else { return }
        let edges = [(true, frame.minX - slot.minX, frame.maxX - slot.maxX),
                     (false, frame.minY - slot.minY, frame.maxY - slot.maxY)]
        for (sideBySide, start, end) in edges {
            for (atEnd, amount) in [(false, start), (true, end)] where abs(amount) > 1 {
                withDwindle(on: screen) {
                    $0.moveEdge(at: index, sideBySide: sideBySide, end: atEnd, by: amount, in: tree.area)
                }
            }
        }
    }

    func dwindleDivider(on screen: Screen, ids: [CGWindowID], slots: [CGRect]) -> SplitDivider? {
        guard let tree = dwindleTree(on: screen), tree.ids == ids,
              let root = dwindle(on: screen).rootSplit(in: tree.area) else {
            return nil
        }
        return SplitDivider(vertical: root.sideBySide, fromStart: !root.swapped, mains: root.firstCount,
                            slots: slots, in: usableRect(screen))
    }

    func moveDwindleDivider(on screen: Screen, to ratio: CGFloat) {
        guard let tree = dwindleTree(on: screen),
              withDwindle(on: screen, { $0.setRootRatio(ratio, in: tree.area) }) else {
            return
        }
        corrections = [:]
        refresh()
    }

    func dwindleMinimums(_ ids: [CGWindowID], gap: CGFloat) -> [CGSize] {
        ids.map { id in minSizes[id].map { CGSize(width: $0.width + gap, height: $0.height + gap) } ?? .zero }
    }

    private func dwindleTree(on screen: Screen) -> DwindleInput? {
        let screenState = state(for: screen)
        guard screenState.layout == .dwindle else { return nil }
        let ids = tiled(on: screen), gap = windowGap(count: ids.count, on: screen)
        screenState.withDwindle(on: dwindleDisplay(screen, screenState)) {
            $0.sync(ids, minimums: dwindleMinimums(ids, gap: gap))
        }
        return DwindleInput(ids: ids, area: usableRect(screen).insetBy(dx: -gap / 2, dy: -gap / 2))
    }
}
