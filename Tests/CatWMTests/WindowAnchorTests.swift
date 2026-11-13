@testable import CatWMKit
import CoreGraphics
import Testing

@Suite struct WindowAnchorTests {
    private let period = 1.0 / 60

    @Test func aFarEdgeThatStaysWhileItsSideResizesIsAnchored() {
        let right = WindowAnchor(from: CGRect(x: 720, y: 0, width: 720, height: 900),
                                 to: CGRect(x: 864, y: 0, width: 576, height: 900))
        #expect(right?.maxX == 1440 && right?.maxY == nil)
        let corner = WindowAnchor(from: CGRect(x: 720, y: 450, width: 720, height: 450),
                                  to: CGRect(x: 480, y: 300, width: 960, height: 600))
        #expect(corner?.maxX == 1440 && corner?.maxY == 900)
        #expect(WindowAnchor(from: CGRect(x: 0, y: 0, width: 720, height: 900),
                             to: CGRect(x: 0, y: 0, width: 864, height: 900)) == nil)
        #expect(WindowAnchor(from: CGRect(x: 0, y: 0, width: 720, height: 900),
                             to: CGRect(x: 100, y: 0, width: 720, height: 900)) == nil)
    }

    @Test func theOriginFollowsTheSizeThatShowsWithIt() throws {
        let anchor = try #require(WindowAnchor(from: CGRect(x: 720, y: 0, width: 720, height: 900),
                                               to: CGRect(x: 864, y: 0, width: 576, height: 900)))
        var lead = WindowLead()
        lead.wrote(position: .init(CGPoint(x: 772, y: 0), seconds: 0, finished: 1),
                   size: .init(CGPoint(x: 668, y: 900), seconds: 0, finished: 1), learns: false,
                   sizeShows: 1 + 3 * period)
        let frame = CGRect(x: 810, y: 0, width: 630, height: 900)
        let late = lead.pinned(frame, to: anchor, times: .init(position: 1 + 2 * period, size: 1 + 4 * period),
                               period: period, resizes: true)
        #expect(late == frame)
        let shown = lead.pinned(frame, to: anchor, times: .init(position: 1 + 3 * period, size: 1 + 5 * period),
                                period: period, resizes: true)
        #expect(shown == CGRect(x: 772, y: 0, width: 630, height: 900))
        let together = lead.pinned(frame.offsetBy(dx: 3, dy: 0), to: anchor,
                                   times: .init(position: 1 + 3 * period, size: 1 + 3 * period), period: period,
                                   resizes: true)
        #expect(together == frame)
        #expect(lead.pinned(frame.offsetBy(dx: 3, dy: 0), to: nil, times: .init(position: 1, size: 2),
                            period: period, resizes: true) == frame.offsetBy(dx: 3, dy: 0))
    }
}
