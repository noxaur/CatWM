import AppKit

package enum WindowServerReads {
    private typealias NewConnection = @convention(c) (Int32, UnsafeMutablePointer<Int32>) -> Int32
    private typealias ReleaseConnection = @convention(c) (Int32) -> Int32
    private typealias Capture = @convention(c) (
        Int32, UnsafePointer<CGWindowID>, Int32, UInt32, CGRect
    ) -> Unmanaged<CFArray>?
    private static let newConnection: NewConnection? = symbol("SLSNewConnection")
    private static let releaseConnection: ReleaseConnection? = symbol("SLSReleaseConnection")
    private static let capture: Capture? = symbol("SLSHWCaptureWindowListInRect")
    private typealias ReadFrame = @convention(c) (Int32, CGWindowID, UnsafeMutablePointer<CGRect>) -> Int32
    private static let readFrame: ReadFrame? = symbol("SLSGetScreenRectForWindow")
    private typealias Integer = @convention(c) (Int32, CGWindowID, UnsafeMutablePointer<Int32>) -> Int32
    private static let windowLevel: Integer? = symbol("SLSGetWindowLevel")

    private final class Session: Sendable {
        let connection: Int32
        init?() {
            guard let newConnection, releaseConnection != nil else { return nil }
            var connection: Int32 = 0
            guard newConnection(0, &connection) == 0, connection != 0 else { return nil }
            self.connection = connection
        }
        deinit { _ = releaseConnection?(connection) }
    }
    private static let session = Session()
    private static let orderSession = Session()

    package static func windowImage(_ id: CGWindowID) -> (image: CGImage, frame: CGRect)? {
        guard CGPreflightScreenCaptureAccess(), let session, let capture,
              let frame = currentFrame(id), !frame.isEmpty else { return nil }
        var window = id
        let images = capture(session.connection, &window, 1, 0, frame)?.takeRetainedValue() as? [CGImage]
        guard let image = images?.first, let after = currentFrame(id), after.approxEqual(frame, tolerance: 1) else {
            return nil
        }
        return (image, frame)
    }

    package static func currentFrame(_ id: CGWindowID) -> CGRect? {
        guard let session, let readFrame else { return nil }
        var frame = CGRect.null
        guard readFrame(session.connection, id, &frame) == 0, !frame.isNull else { return nil }
        return frame
    }

    package static func windowOrder() -> [CGWindowID]? {
        guard let orderSession else { return nil }
        return WindowServerList.onScreen(connection: orderSession.connection)
    }

    package static func canPresent(_ region: CGRect, of id: CGWindowID, excluding excluded: Set<CGWindowID> = [],
                                   order requested: [CGWindowID]? = nil) -> Bool {
        guard let order = requested ?? windowOrder() else { return false }
        return obscured([id: region], excluding: excluded, order: order).isEmpty
    }

    package static func obscured(_ regions: [CGWindowID: CGRect], moving: Set<CGWindowID> = [],
                                 excluding excluded: Set<CGWindowID>, order: [CGWindowID]) -> Set<CGWindowID> {
        obscured(regions, moving: moving, excluding: excluded, order: order, frame: occludingFrame)
    }

    private static func occludingFrame(_ id: CGWindowID) -> CGRect? {
        guard let session, let windowLevel else { return nil }
        var level: Int32 = 0
        guard windowLevel(session.connection, id, &level) == 0 else { return nil }
        return level == 0 ? currentFrame(id) : .zero
    }

    package static func obscured(_ regions: [CGWindowID: CGRect], moving: Set<CGWindowID> = [],
                                 excluding excluded: Set<CGWindowID> = [], order: [CGWindowID],
                                 frame: (CGWindowID) -> CGRect?) -> Set<CGWindowID> {
        var remaining = Set(regions.keys), blocked = Set<CGWindowID>(), front: [CGRect] = []
        for id in order where !remaining.isEmpty && !excluded.contains(id) {
            if let region = regions[id] {
                remaining.remove(id)
                if front.contains(where: { region.intersection($0).width > 1 && region.intersection($0).height > 1 }) {
                    blocked.insert(id)
                }
            } else if !moving.contains(id) {
                guard let other = frame(id) else { return blocked.union(remaining) }
                front.append(other)
            }
        }
        return blocked.union(remaining)
    }
}
