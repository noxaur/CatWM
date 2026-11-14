import AppKit
import CatWMKit
import SwiftUI

extension MenuModel {
    func rebuild() {
        items = source()
    }

    func reset() {
        query = ""
        path = []
        highlight = [:]
        appeared = false
        openWork.cancel()
        trimWork.cancel()
    }

    func item(_ id: String, in list: [MenuItem]? = nil) -> MenuItem? {
        for candidate in list ?? items {
            if candidate.id == id { return candidate }
            if let found = item(id, in: candidate.children) { return found }
        }
        return nil
    }

    func column(_ level: Int) -> [MenuItem] {
        if !query.isEmpty { return level == 0 ? results.map(\.item) : [] }
        guard level > 0 else { return items }
        guard level <= path.count, let parent = item(path[level - 1]) else { return [] }
        return parent.children
    }

    func hover(_ item: MenuItem, level: Int) {
        guard item.selectable else { return }
        highlight[level] = item.id
        trimWork.cancel()
        openWork.cancel()
        let open = path.count > level ? path[level] : nil
        if item.kind == .sub {
            guard open != item.id else { return }
            opening = item.id
            openWork.schedule(after: 0.1) { [weak self] in
                guard let self else { return }
                withAnimation(Motion.easeOut) { self.path = Array(self.path.prefix(level)) + [item.id] }
            }
        } else if open != nil {
            trimLevel = level
            trimWork.schedule(after: 0.18) { [weak self] in self?.trim(to: level) }
        }
    }
}
