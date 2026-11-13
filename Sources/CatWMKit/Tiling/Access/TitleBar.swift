import AppKit
import CoreGraphics

package struct TitleBar: Equatable {
    package enum Kind: Equatable {
        case standard
        case unifiedToolbar
        case fullSizeContent
        case none
    }

    package static let reach: CGFloat = 96

    package let kind: Kind
    package let clearTop: CGFloat?
    package let lights: CGRect?

    package init(lights: CGRect?, contentTop: CGFloat?, controlTop: CGFloat?) {
        self.lights = lights
        if let lights {
            if let controlTop, controlTop < lights.maxY {
                kind = .unifiedToolbar
            } else if contentTop.map({ $0 < lights.maxY }) ?? true {
                kind = .fullSizeContent
            } else {
                kind = .standard
            }
        } else {
            kind = .none
        }
        if let controlTop {
            clearTop = max(0, min(controlTop, Self.reach))
        } else {
            clearTop = kind == .standard ? Self.reach : nil
        }
    }
}
