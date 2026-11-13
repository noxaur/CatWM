import CoreGraphics

package struct WindowFillPlan: Sendable {
    package struct Display: Sendable {
        package let frame: CGRect, scale: CGFloat

        package init(frame: CGRect, scale: CGFloat) { (self.frame, self.scale) = (frame, scale) }
    }

    package let source: CGRect, target: CGRect, minimum: CGSize
    private let display: Display

    package init?(from source: CGRect, to target: CGRect, minimum: CGSize, scale: CGFloat, displays: [Display],
                  duration: Double? = nil) {
        guard duration.map({ $0 >= MotionTiming.shortestFill }) ?? true, !source.isNull, !target.isNull,
              source.size != target.size,
              [source, target].allSatisfy({ $0.width >= minimum.width && $0.height >= minimum.height }),
              let display = displays.first(where: { $0.frame.contains(source) && $0.frame.contains(target) }),
              abs(display.scale - scale) < 0.01 else { return nil }
        (self.source, self.target, self.minimum, self.display) = (source, target, minimum, display)
    }

    package init?(from source: CGRect, to target: CGRect, appearance: WindowFillAppearance, displays: [Display],
                  duration: Double? = nil) {
        self.init(from: source, to: target, minimum: appearance.minimumSize, scale: appearance.scale,
                  displays: displays, duration: duration)
    }

    package func retargeted(to frame: CGRect) -> WindowFillPlan? {
        WindowFillPlan(from: source, to: frame, minimum: minimum, scale: display.scale, displays: [display])
    }

    package var releasesSpace: Bool { target.width < source.width || target.height < source.height }

    package func request(_ frame: (_ offset: Double) -> CGRect) -> CGRect {
        let early = frame(0), late = frame(MotionTiming.fillAhead)
        let left = ceil(max(early.minX, late.minX)), top = ceil(max(early.minY, late.minY))
        let right = floor(min(early.maxX, late.maxX)), bottom = floor(min(early.maxY, late.maxY))
        guard right - left >= minimum.width, bottom - top >= minimum.height else { return frame(0).pixelAligned }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    package func hole(desired: CGRect, actual: CGRect, expected: CGRect?) -> CGRect? {
        let anchor = WindowAnchor(from: source, to: target)
        let holes = expected.map { next in
            let left = max(actual.minX, next.minX), top = max(actual.minY, next.minY)
            let right = anchor?.maxX == nil ? min(actual.minX, next.minX) + min(actual.width, next.width) : actual.maxX
            let bottom = anchor?.maxY == nil ? min(actual.minY, next.minY) + min(actual.height, next.height)
                : actual.maxY
            return [CGRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top)),
                    actual.intersection(next)]
        } ?? [actual]
        return holes.first {
            display.frame.contains(desired) && display.frame.contains($0)
                && Self.shows(desired: desired, actual: $0, minimum: minimum)
        }
    }

    package static func shows(desired: CGRect, actual: CGRect, minimum: CGSize) -> Bool {
        !desired.isNull && !actual.isNull && [desired, actual].allSatisfy {
            $0.width > 0 && $0.height > 0 && $0.width >= minimum.width && $0.height >= minimum.height
        } && desired.intersects(actual) && !actual.contains(desired)
            && !desired.approxEqual(actual, tolerance: FrameTolerance.fill)
    }
}
