import AppKit
import ApplicationServices

package struct Screen {
    package let id: CGDirectDisplayID
    package let uuid: String
    package let frame: CGRect
    package let visible: CGRect
    package let isBuiltin: Bool
    package let nsScreen: NSScreen?

    package init(id: CGDirectDisplayID, uuid: String, frame: CGRect, visible: CGRect, isBuiltin: Bool,
                 nsScreen: NSScreen?) {
        (self.id, self.uuid, self.frame, self.visible) = (id, uuid, frame, visible)
        (self.isBuiltin, self.nsScreen) = (isBuiltin, nsScreen)
    }

    package var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
    package var name: String { nsScreen?.localizedName ?? uuid }

    package static func all() -> [Screen] {
        guard !NSScreen.screens.isEmpty else { return [] }
        let screens = NSScreen.userScreens.compactMap { screen -> Screen? in
            guard let id = screen.displayID else { return nil }
            let uuid = screen.displayUUID ?? "\(id)"
            return Screen(id: id, uuid: uuid, frame: screen.frame.flipped, visible: screen.visibleFrame.flipped,
                          isBuiltin: CGDisplayIsBuiltin(id) != 0, nsScreen: screen)
        }
        .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        return (Instance.scope ?? Instance.embedding.scope)?.filter(screens) ?? screens
    }
}

private func primaryScreenHeight() -> CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

extension CGPoint {
    package var flipped: CGPoint { flipped(primaryHeight: primaryScreenHeight()) }

    package func flipped(primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: x, y: primaryHeight - y)
    }
}

extension CGRect {
    package var flipped: CGRect { flipped(primaryHeight: primaryScreenHeight()) }

    package func flipped(primaryHeight: CGFloat) -> CGRect {
        CGRect(x: minX, y: primaryHeight - maxY, width: width, height: height)
    }
}
