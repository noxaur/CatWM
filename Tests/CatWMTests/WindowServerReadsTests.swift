import AppKit
@testable import CatWM
import CatWMFakes
@testable import CatWMKit
import Testing

struct WindowServerReadsTests {
    @Test func splitHandlesDoNotOccludeTilesButForegroundWindowsStillDo() {
        let tile = CGRect(x: 0, y: 25, width: 600, height: 875)
        let handle = CGRect(x: 591, y: 25, width: 18, height: 875)
        let floating = CGRect(x: 100, y: 100, width: 200, height: 100)
        let frames: [CGWindowID: CGRect] = [1: tile, 2: handle, 3: floating]
        #expect(WindowServerReads.unobscured([tile], participants: [1], excluding: [2],
                                             order: [2, 1], frame: { frames[$0] }))
        #expect(!WindowServerReads.unobscured([tile], participants: [1], excluding: [2],
                                              order: [2, 3, 1], frame: { frames[$0] }))
        #expect(!WindowServerReads.unobscured([tile], participants: [1], excluding: [2],
                                              order: [2], frame: { frames[$0] }))
    }

    @Test func foregroundWindowsKeepTheirOcclusionDuringResize() {
        let tile = CGRect(x: 100, y: 100, width: 600, height: 400)
        let floating = CGRect(x: 150, y: 150, width: 200, height: 100)
        let frames: [CGWindowID: CGRect] = [1: tile, 2: floating]
        #expect(!WindowServerReads.unobscured([tile], participants: [1], order: [2, 1], frame: { frames[$0] }))
        #expect(WindowServerReads.unobscured([tile], participants: [1], order: [1, 2], frame: { frames[$0] }))
        #expect(WindowServerReads.unobscured([tile], participants: [1, 2], order: [2, 1], frame: { frames[$0] }))
        #expect(WindowServerReads.unobscured([tile.offsetBy(dx: 800, dy: 0)], participants: [1],
                                             order: [2, 1], frame: { frames[$0] }))
        #expect(!WindowServerReads.unobscured([tile], participants: [1], order: [2], frame: { frames[$0] }))
    }
}
