import CoreGraphics

package enum MotionTiming {
    package static let quietAfterWrite = 0.4
    package static let landsAtOnceBelow = 0.01
    package static let shortestFill = 0.08
    package static let landingCheckDelay = 0.12
}

package enum FrameTolerance {
    package static let landed: CGFloat = 2
    package static let refused: CGFloat = 1
    package static let fill: CGFloat = 0.25
    package static let observed: CGFloat = 0.5
}
