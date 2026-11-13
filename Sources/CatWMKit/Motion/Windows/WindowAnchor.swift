import CoreGraphics

package struct WindowAnchor: Equatable, Sendable {
    package let maxX: CGFloat?, maxY: CGFloat?

    package init?(from source: CGRect, to target: CGRect) {
        func far(_ edge: KeyPath<CGRect, CGFloat>, _ length: KeyPath<CGRect, CGFloat>) -> CGFloat? {
            abs(source[keyPath: edge] - target[keyPath: edge]) <= FrameTolerance.observed
                && abs(source[keyPath: length] - target[keyPath: length]) > FrameTolerance.observed
                ? target[keyPath: edge] : nil
        }
        guard !source.isNull, !target.isNull else { return nil }
        (maxX, maxY) = (far(\.maxX, \.width), far(\.maxY, \.height))
        guard maxX != nil || maxY != nil else { return nil }
    }

    package func pinned(_ frame: CGRect, showing size: CGSize) -> CGRect {
        CGRect(x: maxX.map { $0 - size.width } ?? frame.minX, y: maxY.map { $0 - size.height } ?? frame.minY,
               width: frame.width, height: frame.height)
    }
}
