import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct MenuModelTests {
    @Test @MainActor func keyboardMoveCancelsPendingHoverSubmenu() {
        let model = MenuModel()
        let layout = MenuItem(id: "layout", kind: .sub, label: "Layout", children: [
            MenuItem(id: "next-layout", label: "Next Layout")
        ])
        model.items = [layout, MenuItem(id: "settings", label: "Settings…")]

        model.hover(layout, level: 0)
        #expect(model.openWork.isPending)
        defer { model.openWork.cancel() }
        model.move(1)
        model.openWork.perform()

        #expect(model.highlight[0] == "settings")
        #expect(model.path.isEmpty)
    }

    @Test @MainActor func hoverStillOpensSubmenuWithoutKeyboardInput() {
        let model = MenuModel()
        let layout = MenuItem(id: "layout", kind: .sub, label: "Layout", children: [
            MenuItem(id: "next-layout", label: "Next Layout")
        ])
        model.items = [layout]

        model.hover(layout, level: 0)
        #expect(model.openWork.isPending)
        defer { model.openWork.cancel() }
        model.openWork.perform()

        #expect(model.path == ["layout"])
    }

    @Test @MainActor func keyboardReopenCancelsPendingHoverTrim() {
        let model = MenuModel()
        let layout = MenuItem(id: "layout", kind: .sub, label: "Layout", children: [
            MenuItem(id: "next-layout", label: "Next Layout")
        ])
        let settings = MenuItem(id: "settings", label: "Settings…")
        model.items = [layout, settings]
        model.path = ["layout"]

        model.hover(settings, level: 0)
        #expect(model.trimWork.isPending)
        defer { model.trimWork.cancel() }
        model.move(-1)
        model.openHighlighted()
        model.trimWork.perform()

        #expect(model.path == ["layout"])
        #expect(model.highlight[1] == "next-layout")
    }
}
