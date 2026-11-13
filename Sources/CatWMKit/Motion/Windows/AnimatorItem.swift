import CoreGraphics
import QuartzCore

extension Animator {
    package struct Move {
        package let window: Window
        package let target: CGRect
        package let bounds: CGRect
        package var from: CGRect?

        package init(window: Window, to target: CGRect, bounds: CGRect, from: CGRect? = nil) {
            self.window = window
            self.target = target
            self.bounds = bounds
            self.from = from
        }
    }

    package struct Batch {
        package let moves: [Move]
        package let spec: MotionSpec

        package init(moves: [Move], spec: MotionSpec) {
            self.moves = moves
            self.spec = spec
        }
    }

    package struct Item {
        let move: Move
        var start: CFTimeInterval?
        let duration: Double
        let tracks: [Trajectory]
        var fill: WindowFillPlan?

        package init(move: Move, from: CGRect, start: CFTimeInterval?, spec: MotionSpec, velocity: [Double]? = nil) {
            self.move = move
            self.start = start
            duration = spec.duration
            let target = move.target
            let pairs = [(from.minX, target.minX), (from.minY, target.minY),
                         (from.width, target.width), (from.height, target.height)]
            tracks = pairs.enumerated().map { index, pair in
                Trajectory(from: pair.0, to: pair.1, spec: spec, velocity: velocity?[index])
            }
        }

        package init(move: Move, tracks: [Trajectory], start: CFTimeInterval?, duration: Double) {
            self.move = move
            self.start = start
            self.duration = duration
            self.tracks = tracks
        }
    }
}

extension Animator.Item {
    package var end: CFTimeInterval? { start.map { $0 + duration } }

    package func request(at times: WindowLead.Times) -> CGRect {
        guard let fill else { return frame(position: times.position, size: times.size) }
        func inner(_ time: CFTimeInterval) -> CGRect { fill.request { frame(at: time + $0, aligned: false) } }
        return CGRect(origin: inner(times.position).origin, size: inner(times.size).size)
    }

    package func frame(at now: CFTimeInterval, aligned: Bool = true) -> CGRect {
        frame(position: now, size: now, aligned: aligned)
    }

    private func frame(position: CFTimeInterval, size: CFTimeInterval, aligned: Bool = true) -> CGRect {
        let values = tracks.indices.map { index in
            let time = index < 2 ? position : size
            return tracks[index].value(at: time - (start ?? time))
        }
        let frame = CGRect(x: values[0], y: values[1], width: max(1, values[2]), height: max(1, values[3]))
        return aligned ? frame.pixelAligned : frame
    }

    package func velocity(at now: CFTimeInterval) -> [Double]? {
        start.map { start in tracks.map { $0.velocity(at: now - start) } }
    }
}
