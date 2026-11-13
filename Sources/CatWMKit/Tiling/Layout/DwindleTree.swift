import CoreGraphics

package enum DwindleDirection: Equatable {
    case automatic, sideBySide, stacked

    func sideBySide(in rect: CGRect) -> Bool {
        switch self {
        case .automatic: rect.width >= rect.height
        case .sideBySide: true
        case .stacked: false
        }
    }
}

package struct DwindleSplit: Equatable {
    package var direction = DwindleDirection.automatic
    package var ratio: CGFloat = 0.5
    package var swapped = false
    package var first: DwindleNode
    package var second: DwindleNode
}

package indirect enum DwindleNode: Equatable {
    case leaf
    case split(DwindleSplit)

    var leafCount: Int {
        switch self {
        case .leaf: 1
        case .split(let split): split.first.leafCount + split.second.leafCount
        }
    }
}

package struct DwindleRoot {
    package let sideBySide: Bool
    package let swapped: Bool
    package let firstCount: Int
}

package struct DwindleTree: Equatable {
    private struct Placement {
        let sideBySide: Bool
        let ratio: CGFloat
        let range: ClosedRange<CGFloat>
        let first: CGRect
        let second: CGRect
        let firstMins: ArraySlice<CGSize>
        let secondMins: ArraySlice<CGSize>
    }

    private struct Step {
        let placement: Placement
        let swapped: Bool
        let inFirst: Bool
        let rect: CGRect
    }

    package private(set) var root: DwindleNode?
    package private(set) var ids: [CGWindowID] = []

    package init() {}

    package mutating func sync(_ new: [CGWindowID]) {
        guard new != ids else { return }
        let kept = Set(new), old = Set(ids)
        for index in ids.indices.reversed() where !kept.contains(ids[index]) {
            root = root.flatMap { Self.removing(index, from: $0) }
        }
        for (index, id) in new.enumerated() where !old.contains(id) {
            guard let current = root else { root = .leaf; continue }
            root = Self.splitting(max(0, index - 1), in: current)
        }
        ids = new
    }

    package func frames(in rect: CGRect, minimums: [CGSize] = []) -> [CGRect] {
        guard let root else { return [] }
        return Self.frames(of: root, in: rect, mins: mins(minimums))
    }

    package mutating func toggleSplit(at index: Int, in rect: CGRect) {
        let steps = steps(to: index, in: rect)
        guard let parent = steps.last else { return }
        modify(depth: steps.count - 1, along: steps) {
            $0.direction = parent.placement.sideBySide ? .stacked : .sideBySide
        }
    }

    package mutating func swapSplit(at index: Int, in rect: CGRect) {
        let steps = steps(to: index, in: rect)
        guard !steps.isEmpty else { return }
        modify(depth: steps.count - 1, along: steps) { $0.swapped.toggle() }
    }

    @discardableResult
    package mutating func setRatio(at index: Int, in rect: CGRect, _ change: (CGFloat) -> CGFloat) -> CGFloat? {
        let steps = steps(to: index, in: rect)
        guard !steps.isEmpty else { return nil }
        var ratio: CGFloat?
        modify(depth: steps.count - 1, along: steps) {
            $0.ratio = min(0.9, max(0.1, change($0.ratio)))
            ratio = $0.ratio
        }
        return ratio
    }

    package mutating func resize(at index: Int, by delta: CGSize, in rect: CGRect) {
        let steps = steps(to: index, in: rect)
        for (sideBySide, amount) in [(true, delta.width), (false, delta.height)] where amount != 0 {
            guard let depth = steps.lastIndex(where: { $0.placement.sideBySide == sideBySide }) else { continue }
            move(depth, along: steps, by: (steps[depth].inFirst ? 1 : -1) * amount)
        }
    }

    package mutating func moveEdge(at index: Int, sideBySide: Bool, end: Bool, by amount: CGFloat, in rect: CGRect,
                                   minimums: [CGSize] = []) {
        let steps = steps(to: index, in: rect, minimums: minimums)
        guard let depth = steps.lastIndex(where: {
            $0.placement.sideBySide == sideBySide && ($0.inFirst != $0.swapped) == end
        }) else { return }
        move(depth, along: steps, by: steps[depth].swapped ? -amount : amount)
    }

    package func rootSplit(in rect: CGRect, minimums: [CGSize] = []) -> DwindleRoot? {
        guard case .split(let split)? = root else { return nil }
        let placement = Self.place(split, in: rect, mins: mins(minimums))
        return DwindleRoot(sideBySide: placement.sideBySide, swapped: split.swapped, firstCount: split.first.leafCount)
    }

    package mutating func setRootRatio(_ ratio: CGFloat, in rect: CGRect, minimums: [CGSize] = []) -> Bool {
        guard case .split(var split)? = root else { return false }
        let range = Self.place(split, in: rect, mins: mins(minimums)).range
        let clamped = min(max(ratio, range.lowerBound), range.upperBound)
        guard abs(clamped - split.ratio) > 0.0005 else { return false }
        split.ratio = clamped
        root = .split(split)
        return true
    }

    package mutating func swapRoot() {
        guard case .split(var split)? = root else { return }
        split.swapped.toggle()
        root = .split(split)
    }

    private func mins(_ minimums: [CGSize]) -> ArraySlice<CGSize> {
        (minimums.count == ids.count ? minimums : Array(repeating: .zero, count: root?.leafCount ?? 0))[...]
    }

    private func steps(to index: Int, in rect: CGRect, minimums: [CGSize] = []) -> [Step] {
        var steps: [Step] = [], node = root, rect = rect, index = index, mins = mins(minimums)
        while case .split(let split)? = node {
            let placement = Self.place(split, in: rect, mins: mins)
            let count = split.first.leafCount
            let inFirst = index < count
            steps.append(Step(placement: placement, swapped: split.swapped, inFirst: inFirst, rect: rect))
            node = inFirst ? split.first : split.second
            rect = inFirst ? placement.first : placement.second
            mins = inFirst ? placement.firstMins : placement.secondMins
            if !inFirst { index -= count }
        }
        return steps
    }

    private mutating func move(_ depth: Int, along steps: [Step], by amount: CGFloat) {
        let step = steps[depth], placement = step.placement
        let length = placement.sideBySide ? step.rect.width : step.rect.height
        guard length > 0 else { return }
        let ratio = min(max(placement.ratio + amount / length, placement.range.lowerBound), placement.range.upperBound)
        modify(depth: depth, along: steps) { $0.ratio = ratio }
    }

    private mutating func modify(depth: Int, along steps: [Step], _ change: (inout DwindleSplit) -> Void) {
        root = root.map { Self.modify($0, steps: steps[...], depth: depth, change) }
    }

    private static func modify(_ node: DwindleNode, steps: ArraySlice<Step>, depth: Int,
                               _ change: (inout DwindleSplit) -> Void) -> DwindleNode {
        guard case .split(var split) = node, let step = steps.first else { return node }
        if depth == 0 {
            change(&split)
        } else if step.inFirst {
            split.first = modify(split.first, steps: steps.dropFirst(), depth: depth - 1, change)
        } else {
            split.second = modify(split.second, steps: steps.dropFirst(), depth: depth - 1, change)
        }
        return .split(split)
    }

    private static func place(_ split: DwindleSplit, in rect: CGRect, mins: ArraySlice<CGSize>) -> Placement {
        let count = split.first.leafCount
        let firstMins = mins.prefix(count), secondMins = mins.dropFirst(count)
        let first = need(split.first, firstMins), second = need(split.second, secondMins)
        let fitsSide = first.width + second.width <= rect.width
        let fitsStack = first.height + second.height <= rect.height
        var sideBySide = split.direction.sideBySide(in: rect)
        if split.direction == .automatic, sideBySide ? !fitsSide && fitsStack : !fitsStack && fitsSide {
            sideBySide.toggle()
        }
        let length = sideBySide ? rect.width : rect.height
        let low = sideBySide ? first.width : first.height, high = length - (sideBySide ? second.width : second.height)
        var ratio = split.ratio, range: ClosedRange<CGFloat> = 0.1...0.9
        if length > 0, low <= high {
            ratio = min(max(ratio * length, low), high) / length
            let lower = max(0.1, low / length), upper = min(0.9, high / length)
            range = lower <= upper ? lower...upper : ratio...ratio
        }
                let edge: CGRectEdge = sideBySide ? (split.swapped ? .maxXEdge : .minXEdge)
            : (split.swapped ? .maxYEdge : .minYEdge)
        let (one, two) = rect.divided(atDistance: length * ratio, from: edge)
        return Placement(sideBySide: sideBySide, ratio: ratio, range: range, first: one, second: two,
                         firstMins: firstMins, secondMins: secondMins)
    }

    private static func frames(of node: DwindleNode, in rect: CGRect, mins: ArraySlice<CGSize>) -> [CGRect] {
        guard case .split(let split) = node else { return [rect] }
        let placement = place(split, in: rect, mins: mins)
        return frames(of: split.first, in: placement.first, mins: placement.firstMins)
            + frames(of: split.second, in: placement.second, mins: placement.secondMins)
    }

    private static func need(_ node: DwindleNode, _ mins: ArraySlice<CGSize>) -> CGSize {
        guard case .split(let split) = node else { return mins.first ?? .zero }
        let count = split.first.leafCount
        let first = need(split.first, mins.prefix(count)), second = need(split.second, mins.dropFirst(count))
        let side = CGSize(width: first.width + second.width, height: max(first.height, second.height))
        let stack = CGSize(width: max(first.width, second.width), height: first.height + second.height)
        switch split.direction {
        case .sideBySide: return side
        case .stacked: return stack
        case .automatic: return CGSize(width: min(side.width, stack.width), height: min(side.height, stack.height))
        }
    }

    private static func removing(_ index: Int, from node: DwindleNode) -> DwindleNode? {
        guard case .split(var split) = node else { return index == 0 ? nil : node }
        let count = split.first.leafCount
        if index < count {
            guard let first = removing(index, from: split.first) else { return split.second }
            split.first = first
        } else {
            guard let second = removing(index - count, from: split.second) else { return split.first }
            split.second = second
        }
        return .split(split)
    }

    private static func splitting(_ index: Int, in node: DwindleNode) -> DwindleNode {
        guard case .split(var split) = node else {
            return .split(DwindleSplit(first: .leaf, second: .leaf))
        }
        let count = split.first.leafCount
        if index < count {
            split.first = splitting(index, in: split.first)
        } else {
            split.second = splitting(index - count, in: split.second)
        }
        return .split(split)
    }
}
