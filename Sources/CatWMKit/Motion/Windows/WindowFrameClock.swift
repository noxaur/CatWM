import AppKit
import QuartzCore

extension Animator {
    package typealias Tick = @MainActor (_ shown: CFTimeInterval, _ presentation: CFTimeInterval) -> Void
    package typealias MakeClock = @MainActor (NSScreen?, @escaping Tick) -> (any FrameClock)?
    package static let displayLink: MakeClock = { screen, tick in
        screen.map { WindowFrameClock(screen: $0, update: tick) }
    }
    package typealias Delay = (TimeInterval, @escaping @MainActor () -> Void) -> Void
    package static let mainQueue: Delay = { seconds, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { work() } // style-ok: ignored writes send no event
    }
}

@MainActor package protocol FrameClock: AnyObject, Sendable {
    var displayID: CGDirectDisplayID? { get }
    func stop()
}

@MainActor package final class WindowFrameClock: NSObject, FrameClock {
    package let displayID: CGDirectDisplayID?
    private var link: CADisplayLink?
    private let update: Animator.Tick

    package init(screen: NSScreen, update: @escaping Animator.Tick) {
        displayID = screen.displayID
        self.update = update
        super.init()
        let link = screen.displayLink(target: self, selector: #selector(frame(_:)))
        let rate = Float(screen.maximumFramesPerSecond)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
        self.link = link
        link.add(to: .main, forMode: .common)
    }

    package func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func frame(_ link: CADisplayLink) { update(link.timestamp, link.targetTimestamp) }
}
