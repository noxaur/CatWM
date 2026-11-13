import CoreGraphics

package enum MotionTiming {
    package static let quietAfterWrite = 0.4
    package static let landsAtOnceBelow = 0.01
    package static let shortestFill = 0.08
    package static let fillAhead = 0.008
    package static let landingCheckDelay = 0.12
    package static let writeCostLimit = 0.05
    package static let writeCostMemory = 1.0
    package static let leadLimit = 0.1
    package static let leadMemory = 10.0
    package static let leadSamples = 5
    package static let leadHistory = 12
    package static let leadHysteresis = 0.25
}

package enum FrameTolerance {
    package static let landed: CGFloat = 2
    package static let refused: CGFloat = 1
    package static let fill: CGFloat = 0.25
    package static let observed: CGFloat = 0.5
}
