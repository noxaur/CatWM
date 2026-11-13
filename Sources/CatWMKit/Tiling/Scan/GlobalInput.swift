import CoreGraphics

package struct GlobalInput: Equatable {
    package let keys: Bool
    package let capsLock: Bool
    package let mouseTaps: Bool
    package let pointerAndFocus: Bool

    package init(scope: WindowScope?, keys: String?, embedded: Bool = false) {
        self.keys = scope == nil || keys == "on" || embedded
        capsLock = scope == nil && !embedded
        mouseTaps = scope == nil
        pointerAndFocus = scope == nil
    }
}
