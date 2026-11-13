import AppKit
import QuartzCore

@MainActor package final class WindowResizeFills: WindowPresentation {
    private struct Cached {
        let appearance: WindowFillAppearance
        let frame: CGRect
        let time: CFTimeInterval
    }
    private struct Active {
        var plan: WindowFillPlan
        let appearance: WindowFillAppearance
        var fill: WindowResizeFill?
        var hole: CGRect?
        var samples = 0, visible = 0
    }
    private let captureQueue = DispatchQueue(label: "catwm.fill-preparation", qos: .userInitiated)
    private var cache: [CGWindowID: Cached] = [:]
    private var warming: Set<CGWindowID> = []
    private var active: [CGWindowID: Active] = [:]
    package init() {}

    package var refresh: (@MainActor () -> Void)?
    package var excluded: @MainActor () -> Set<CGWindowID> = { [] }

    package func warm(_ windows: [CGWindowID: Window], busy: @escaping @MainActor (CGWindowID) -> Bool) {
        cache = cache.filter { windows[$0.key] != nil }
        let own = excluded()
        var order: [CGWindowID]?
        for id in windows.keys where !warming.contains(id) && !busy(id) {
            guard let frame = WindowServerReads.currentFrame(id), !frame.isEmpty,
                  cache[id].map({ $0.frame.size != frame.size || CACurrentMediaTime() - $0.time > 5 }) ?? true else {
                continue
            }
            order = order ?? WindowServerReads.windowOrder()
            guard let order, WindowServerReads.canPresent(frame, of: id, excluding: own, order: order) else { continue }
            warming.insert(id)
            captureQueue.async { [weak self] in
                let snapshot = WindowServerReads.windowImage(id)
                let appearance = snapshot.flatMap { WindowFillAppearance(image: $0.image, size: $0.frame.size) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.warming.remove(id)
                    guard let snapshot, let appearance else {
                        Log.debug("window-fill: unsupported or unavailable appearance \(id)")
                        return
                    }
                    guard !busy(id),
                          WindowServerReads.currentFrame(id)?
                            .approxEqual(snapshot.frame, tolerance: FrameTolerance.fill) == true else {
                        return
                    }
                    self.cache[id] = Cached(appearance: appearance, frame: snapshot.frame, time: CACurrentMediaTime())
                    Log.debug("window-fill: prepared \(id)")
                }
            }
        }
    }

    private static func displays() -> [WindowFillPlan.Display] {
        Screen.all().compactMap { screen in
            screen.nsScreen.map { WindowFillPlan.Display(frame: screen.frame, scale: $0.backingScaleFactor) }
        }
    }

    package func plan(for move: Animator.Move, from: CGRect, spec: MotionSpec) -> WindowFillPlan? {
        cache[move.window.id].flatMap {
            WindowFillPlan(from: from, to: move.target, appearance: $0.appearance, displays: Self.displays(),
                           duration: spec.duration)
        }
    }

    package func prepare(_ plans: [CGWindowID: WindowFillPlan], moving: Set<CGWindowID>) -> Set<CGWindowID> {
        guard !plans.isEmpty, let order = WindowServerReads.windowOrder() else { return [] }
        let own = Set(active.values.compactMap { $0.fill?.windowID }).union(excluded())
        let shown = Set(plans.keys).subtracting(WindowServerReads.obscured(
            plans.mapValues { $0.source.union($0.target) }, moving: moving, excluding: own, order: order
        ))
        for id in shown {
            guard let plan = plans[id] else { continue }
            if active[id] != nil {
                active[id]?.plan = plan
            } else if let cached = cache[id] {
                active[id] = Active(plan: plan, appearance: cached.appearance)
            }
        }
        return shown
    }

    package func follow(_ moves: [Animator.Move]) {
        let displays = Self.displays()
        let plans = moves.reduce(into: [CGWindowID: WindowFillPlan]()) { plans, move in
            let id = move.window.id
            guard active[id] == nil, let cached = cache[id] else { return }
            plans[id] = WindowFillPlan(from: move.window.cachedFrame, to: move.target,
                                       appearance: cached.appearance, displays: displays)
        }
        _ = prepare(plans, moving: Set(moves.map(\.window.id)))
    }

    package func update(_ frames: [CGWindowID: CGRect], observed: [CGWindowID: CGRect],
                        expected: [CGWindowID: CGRect]) {
        for id in active.keys where frames[id] == nil { cancel(id) }
        for (id, entry) in active {
            guard let desired = frames[id], let actual = observed[id] ?? WindowServerReads.currentFrame(id) else {
                cancel(id); continue
            }
            active[id]?.samples += 1
            guard let hole = entry.plan.hole(desired: desired, actual: actual, expected: expected[id]) else {
                entry.fill?.close()
                active[id]?.hole = nil
                continue
            }
            let fill = entry.fill ?? WindowResizeFill(window: id, appearance: entry.appearance)
            if entry.fill == nil {
                fill.onDismiss = { [weak self] in self?.cancel(id) }
                active[id]?.fill = fill
            }
            fill.update(desired: desired, actual: hole)
            active[id]?.hole = fill.visible ? hole : nil
            if fill.visible { active[id]?.visible += 1 }
        }
    }

    package func fill(of id: CGWindowID) -> CGRect? { active[id]?.hole }

    package func cancel(_ id: CGWindowID) {
        guard let entry = active.removeValue(forKey: id) else { return }
        entry.fill?.close()
        Log.debug("window-fill: \(id) samples \(entry.samples) visible \(entry.visible)")
    }

    package func close() {
        for id in active.keys { cancel(id) }
    }
}
