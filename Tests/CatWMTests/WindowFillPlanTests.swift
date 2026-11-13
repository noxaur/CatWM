import AppKit
@testable import CatWM
import CatWMFakes
@testable import CatWMKit
import Testing

struct WindowFillPlanTests {
    private let display = WindowFillPlan.Display(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    private let minimum = CGSize(width: 40, height: 40)

    private func plan(_ from: CGRect, _ target: CGRect, scale: CGFloat = 2, duration: Double? = 0.12)
        -> WindowFillPlan? {
        WindowFillPlan(from: from, to: target, minimum: minimum, scale: scale, displays: [display], duration: duration)
    }

    private func item(from: CGRect, to target: CGRect, fill: Bool = true) throws -> Animator.Item {
        let backend = FakeBackend()
        let id = backend.addWindow(frame: from)
        let window = Window(id: id, element: try #require(backend.element(id)), pid: -100,
                            bundleID: nil, backend: backend)
        var item = Animator.Item(move: .init(window: window, to: target, bounds: from.union(target)),
                                 from: from, start: 0, spec: .init(duration: 1, curve: .easeOut, bounce: 0))
        if fill { item.fill = try #require(plan(from, target, duration: nil)) }
        return item
    }

    private static let moves = [
        (CGRect(x: 720, y: 0, width: 720, height: 900), CGRect(x: 864, y: 0, width: 576, height: 900)),
        (CGRect(x: 0, y: 0, width: 720, height: 900), CGRect(x: 0, y: 0, width: 864, height: 900)),
        (CGRect(x: 720, y: 450, width: 720, height: 450), CGRect(x: 720, y: 300, width: 720, height: 300)),
        (CGRect(x: 0, y: 0, width: 960, height: 900), CGRect(x: 960, y: 450, width: 480, height: 450)),
        (CGRect(x: 960, y: 450, width: 480, height: 450), CGRect(x: 0, y: 0, width: 960, height: 900))
    ]

    @Test func everyTiledShapeEngagesIncludingAMovingTopAndASwap() {
        for (from, target) in Self.moves { #expect(plan(from, target) != nil, "\(from) → \(target)") }
    }

    @Test func aFillStaysOutOfMovesItCannotHelpOrDraw() {
        let from = CGRect(x: 0, y: 0, width: 720, height: 900)
        #expect(plan(from, from.offsetBy(dx: 100, dy: 0)) == nil)
        #expect(plan(from, CGRect(x: 0, y: 0, width: 30, height: 900)) == nil)
        #expect(plan(from, CGRect(x: 1000, y: 0, width: 800, height: 900)) == nil)
        #expect(plan(from, CGRect(x: 0, y: 0, width: 800, height: 900), scale: 1) == nil)
        #expect(plan(from, CGRect(x: 0, y: 0, width: 800, height: 900), duration: 0.05) == nil)
    }

    @Test func theNativeWindowStaysInsideTheOutlineItShowsUnder() throws {
        for (from, target) in Self.moves {
            let item = try item(from: from, to: target)
            for time in stride(from: 0.0, through: 1.0, by: 0.05) {
                let native = item.request(at: .init(position: time, size: time))
                #expect(item.frame(at: time, aligned: false).insetBy(dx: -0.01, dy: -0.01).contains(native),
                        "\(from) → \(target) at \(time)")
            }
        }
    }

    @Test func inwardEdgesLeadAndOutwardEdgesTrail() throws {
        let item = try item(from: CGRect(x: 720, y: 450, width: 720, height: 450),
                            to: CGRect(x: 960, y: 0, width: 480, height: 600))
        let native = item.request(at: .init(position: 0.2, size: 0.2))
        let ahead = item.frame(at: 0.2 + MotionTiming.fillAhead, aligned: false)
        let behind = item.frame(at: 0.2, aligned: false)
        #expect(native.minX == ceil(ahead.minX) && native.maxY == floor(ahead.maxY))
        #expect(native.minY == ceil(behind.minY) && native.maxX == floor(behind.maxX))
    }

    @Test func positionAndSizeEachKeepTheEdgesOfTheirOwnVsync() throws {
        let item = try item(from: CGRect(x: 0, y: 0, width: 960, height: 900),
                            to: CGRect(x: 960, y: 450, width: 480, height: 450))
        let native = item.request(at: .init(position: 0.1, size: 0.3))
        let early = item.request(at: .init(position: 0.1, size: 0.1))
        let late = item.request(at: .init(position: 0.3, size: 0.3))
        #expect(native.origin == early.origin && native.size == late.size)
    }

    @Test func shrinkingWritesIntermediateNativeSizesBeforeLanding() async throws {
        let source = CGRect(x: 0, y: 38, width: 1000, height: 600)
        let target = CGRect(x: 0, y: 38, width: 700, height: 600)
        let item = try item(from: source, to: target)
        let window = item.move.window
        let backend = try #require(window.backend as? FakeBackend)
        window.remember(source)
        let writer = AXWriter(pid: window.pid, backend: backend)
        backend.clearWrites()
        for time in [0.01, 0.2, 0.5, 0.9] {
            writer.step(window, .init(shown: 0, presentation: 0)) { _ in
                item.request(at: .init(position: time, size: time))
            }
            await withCheckedContinuation { continuation in writer.run { continuation.resume() } }
        }
        await withCheckedContinuation { continuation in
            writer.land(window, at: target) { _ in continuation.resume() }
        }
        #expect(backend.frame(of: window.id) == target)
        let widths = backend.writes.compactMap { write -> CGFloat? in
            if case let .size(_, size) = write { return size.width }
            return nil
        }
        #expect(widths.count >= 4 && widths == widths.sorted(by: >) && widths.last == 700, "\(widths)")
    }

    @Test func withoutAPlanAMoveKeepsOrdinaryPredictiveMotion() throws {
        let item = try item(from: CGRect(x: 910, y: 38, width: 800, height: 600),
                            to: CGRect(x: 850, y: 38, width: 860, height: 600), fill: false)
        #expect(item.request(at: .init(position: 0.3, size: 0.3)) == item.frame(at: 0.3))
    }

    @Test func aFillShowsOnlyWhileTheNativeWindowFallsShortOnItsDisplay() throws {
        let plan = try #require(plan(CGRect(x: 0, y: 0, width: 720, height: 900),
                                     CGRect(x: 0, y: 0, width: 864, height: 900)))
        let desired = CGRect(x: 0, y: 0, width: 800, height: 900)
        #expect(plan.hole(desired: desired, actual: CGRect(x: 0, y: 0, width: 760, height: 900), expected: nil) != nil)
        #expect(plan.hole(desired: desired, actual: desired.insetBy(dx: -10, dy: 0), expected: nil) == nil)
        #expect(plan.hole(desired: desired, actual: CGRect(x: 900, y: 0, width: 300, height: 900), expected: nil)
            == nil)
        #expect(plan.hole(desired: desired, actual: CGRect(x: 0, y: 0, width: 30, height: 900), expected: nil) == nil)
        let top = CGRect(x: 0, y: 60, width: 800, height: 840)
        #expect(plan.hole(desired: desired, actual: top, expected: nil) == top)
    }

    @Test func theHoleFitsTheWindowWhicheverOfItsOriginAndSizeShowFirst() throws {
        let plan = try #require(plan(CGRect(x: 720, y: 0, width: 720, height: 900),
                                     CGRect(x: 864, y: 0, width: 576, height: 900)))
        let desired = CGRect(x: 780, y: 0, width: 660, height: 900)
        let hole = plan.hole(desired: desired, actual: CGRect(x: 790, y: 0, width: 650, height: 900),
                             expected: CGRect(x: 820, y: 0, width: 620, height: 900))
        #expect(hole == CGRect(x: 820, y: 0, width: 590, height: 900))
    }

    @Test func aRetargetKeepsItsFillWhenTheTopEdgeChanges() throws {
        let plan = try #require(plan(CGRect(x: 0, y: 0, width: 720, height: 900),
                                     CGRect(x: 0, y: 0, width: 864, height: 900)))
        #expect(plan.retargeted(to: CGRect(x: 0, y: 300, width: 864, height: 600)) != nil)
    }
}
