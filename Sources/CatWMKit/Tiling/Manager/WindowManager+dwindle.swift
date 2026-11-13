import AppKit

extension WindowManager {
    private struct DwindleInput {
        let ids: [CGWindowID]
        let area: CGRect
        let minimums: [CGSize]
    }

    @discardableResult
    package func changeDwindle(of target: Window? = nil,
                               _ change: (inout DwindleTree, _ index: Int, _ area: CGRect) -> Void) -> Bool {
        guard let window = target ?? focusedWindow(), let screen = screen(of: window),
              let tree = dwindleTree(on: screen), let index = tree.ids.firstIndex(of: window.id) else { return false }
        change(&state(for: screen).dwindle, index, tree.area)
        refresh()
        return true
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
                screenState.dwindle.moveEdge(at: index, sideBySide: sideBySide, end: atEnd, by: amount,
                                             in: tree.area, minimums: tree.minimums)
            }
        }
    }

    func dwindleDivider(on screen: Screen, ids: [CGWindowID], slots: [CGRect]) -> SplitDivider? {
        guard let tree = dwindleTree(on: screen), tree.ids == ids,
              let root = state(for: screen).dwindle.rootSplit(in: tree.area, minimums: tree.minimums) else {
            return nil
        }
        return SplitDivider(vertical: root.sideBySide, fromStart: !root.swapped, mains: root.firstCount,
                            slots: slots, in: usableRect(screen))
    }

    func moveDwindleDivider(on screen: Screen, to ratio: CGFloat) {
        guard let tree = dwindleTree(on: screen),
              state(for: screen).dwindle.setRootRatio(ratio, in: tree.area, minimums: tree.minimums) else { return }
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
        screenState.dwindle.sync(ids)
        return DwindleInput(ids: ids, area: usableRect(screen).insetBy(dx: -gap / 2, dy: -gap / 2),
                            minimums: dwindleMinimums(ids, gap: gap))
    }
}
