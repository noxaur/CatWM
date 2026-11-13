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
        guard let primary = NSScreen.screens.first else { return [] }
        let height = primary.frame.height
        func flip(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        }
        let screens = NSScreen.userScreens.compactMap { screen -> Screen? in
            guard let id = screen.displayID else { return nil }
            let uuid = screen.displayUUID ?? "\(id)"
            return Screen(id: id, uuid: uuid, frame: flip(screen.frame), visible: flip(screen.visibleFrame),
                          isBuiltin: CGDisplayIsBuiltin(id) != 0, nsScreen: screen)
        }
        .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        return (Instance.scope ?? Instance.embedding.scope)?.filter(screens) ?? screens
    }
}

package func mouseLocation() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }
