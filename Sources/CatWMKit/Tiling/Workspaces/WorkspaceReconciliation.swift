import AppKit
import CoreGraphics

package struct WorkspaceReconciliation {
    package var model: WorkspaceModel
    package var displayOf: [CGWindowID: String]
    package let visible: Set<CGWindowID>

    package static func reconcile(_ observation: WorkspaceObservation, model input: WorkspaceModel,
                                  displayOf previous: [CGWindowID: String]) -> Self {
        var model = input
        var displayOf = previous
        let displays = observation.displays
        guard !displays.isEmpty else { return Self(model: model, displayOf: displayOf, visible: []) }
        let uuids = Set(displays.map(\.id))
        for uuid in model.shown.keys where !uuids.contains(uuid) { model.shown[uuid] = nil }
        for uuid in model.virtualShown.keys where !uuids.contains(uuid) { model.virtualShown[uuid] = nil }
        for display in displays {
            model.show(WorkspaceKey.space(display: display.id, space: display.space), on: display.id)
            if let workspace = model.shown[display.id] { model.monitorOf[workspace] = display.id }
        }
        hostMaximised(observation, in: &model)
        followMovedWindows(observation, in: &model, displayOf: &displayOf, uuids: uuids)
        var moves: [CGWindowID: String] = [:]
        for id in observation.present where !model.isShown(model.workspaceOf[id]) {
            let target = display(containing: observation.frames[id] ?? .null, among: displays)
            moves[id] = model.shown[target]
        }
        model.assign(moves)
        let visible = observation.present.filter { model.isShown(model.workspaceOf[$0]) }
        return Self(model: model, displayOf: displayOf, visible: visible)
    }

    private static func hostMaximised(_ observation: WorkspaceObservation, in model: inout WorkspaceModel) {
        model.maximisedHost = [:]
        for (id, space) in observation.maximised.sorted(by: { $0.key < $1.key }) {
            guard let owner = observation.displays.first(where: { $0.spaces.contains(space) }) else { continue }
            let workspace = WorkspaceKey.space(display: owner.id, space: space)
            model.hostMaximised(id, in: workspace)
            model.monitorOf[workspace] = owner.id
            model.maximisedHost[workspace] = id
        }
    }

    private static func followMovedWindows(
        _ observation: WorkspaceObservation, in model: inout WorkspaceModel,
        displayOf: inout [CGWindowID: String], uuids: Set<String>
    ) {
        let displays = observation.displays
        for id in observation.present where !observation.held.contains(id) {
            guard let workspace = model.workspaceOf[id], model.isShown(workspace),
                  let frame = observation.frames[id], !frame.isNull,
                  displays.reduce(CGFloat(0), { $0 + area($1.frame.intersection(frame)) }) >= 400 else { continue }
            let now = display(containing: frame, among: displays)
            defer { displayOf[id] = now }
            guard let was = displayOf[id], was != now, uuids.contains(was),
                  let monitor = model.monitorOf[workspace], monitor != now,
                  let destination = model.shown[now] else { continue }
            model.assign(id, to: destination)
        }
    }

    private static func display(containing frame: CGRect, among displays: [WorkspaceObservation.Display]) -> String {
        let fallback = displays.first?.id ?? ""
        guard !frame.isNull else { return fallback }
        return displays.max { first, second in
            area(first.frame.intersection(frame)) < area(second.frame.intersection(frame))
        }?.id ?? fallback
    }

    private static func area(_ frame: CGRect) -> CGFloat { frame.isNull ? 0 : frame.width * frame.height }
}
