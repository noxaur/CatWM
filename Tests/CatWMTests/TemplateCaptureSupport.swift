@testable import CatWM
@testable import CatWMKit
import Foundation

func sampleTemplate(title: String = "Draft") -> WorkspaceTemplate {
    WorkspaceTemplate(name: "Writing", tilingEnabled: true, displays: [
        .init(
            id: "desk", name: "Desk", frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visible: CGRect(x: 0, y: 24, width: 1000, height: 776), isMain: true, layout: "tall",
            ratio: 0.65, mainCount: 2
        )
    ], windows: [
        .init(bundleID: "com.example.editor", appName: "Editor", title: title, document: "file:///tmp/draft.txt",
              display: "desk", frame: CGRect(x: 0, y: 24, width: 650, height: 776), floating: false, minimized: false,
              maximised: false, zoomed: false, focused: true, windowID: 42, launchDate: nil)
    ])
}

struct TemplateScratch {
    let url: URL
    init() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        url = directory.appendingPathComponent("templates.json")
    }
    @MainActor func library() -> TemplateLibrary { TemplateLibrary(url: url) }
    func remove() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}

final class CaptureCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int { lock.withLock { stored } }
    @discardableResult
    func bump() -> Int { lock.withLock { stored += 1; return stored } }
}
