import AppKit
@testable import CatWMKit
import Testing

@Suite struct ScreenFlipTests {
    @Test func aFlipRoundTripsAndPlacesAKnownRect() {
        let rect = CGRect(x: 40, y: 100, width: 200, height: 50)
        #expect(rect.flipped(primaryHeight: 1000) == CGRect(x: 40, y: 850, width: 200, height: 50))
        #expect(rect.flipped(primaryHeight: 1000).flipped(primaryHeight: 1000) == rect)
        #expect(rect.flipped(primaryHeight: 0).flipped(primaryHeight: 0) == rect)
        let point = CGPoint(x: 40, y: 100)
        #expect(point.flipped(primaryHeight: 1000) == CGPoint(x: 40, y: 900))
        #expect(point.flipped(primaryHeight: 1000).flipped(primaryHeight: 1000) == point)
    }

    @Test @MainActor func thePropertyFlipsAcrossThePrimaryScreen() {
        _ = NSApplication.shared
        let height = NSScreen.screens.first.map(\.frame.height) ?? 0
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        #expect(rect.flipped == rect.flipped(primaryHeight: height))
        #expect(CGPoint(x: 8, y: 15).flipped == CGPoint(x: 8, y: 15).flipped(primaryHeight: height))
    }
}
