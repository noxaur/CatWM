import Foundation
import QuartzCore

@MainActor package final class DesktopTransitionTiming {
    private let start: CFTimeInterval
    private var previous: CFTimeInterval
    private var phases: [String] = []
    private var moved = false

    package init(since start: CFTimeInterval) { self.start = start; previous = start }

    package func checkpoint(_ phase: String) {
        let now = CACurrentMediaTime()
        phases.append(String(format: "%@ %.2f", phase, (now - previous) * 1000))
        previous = now
    }

    package func motion() {
        guard !moved else { return }
        moved = true
        checkpoint("frame")
        Log.info(String(format: "native workspaces: request to motion %.2f ms (%@)",
                        (previous - start) * 1000, phases.joined(separator: ", ")))
    }
}
