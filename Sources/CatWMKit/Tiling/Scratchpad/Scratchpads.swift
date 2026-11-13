import CoreGraphics
import Foundation

package struct Scratchpads {
    package struct Entry: Equatable {
        package let id: CGWindowID
        package var name: String
        package var hidden: Bool
    }

    package static let defaultName = "scratchpad"

    package private(set) var entries: [Entry] = []

    package static func name(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? defaultName : trimmed
    }

    package var hiddenIDs: Set<CGWindowID> { Set(entries.filter(\.hidden).map(\.id)) }

    package func name(of id: CGWindowID) -> String? { entries.first { $0.id == id }?.name }

    package func isHidden(_ id: CGWindowID) -> Bool { entries.contains { $0.id == id && $0.hidden } }

    package func shown(named name: String) -> [CGWindowID] {
        entries.filter { $0.name == name && !$0.hidden }.map(\.id)
    }

    package func lastHidden(named name: String) -> CGWindowID? {
        entries.last { $0.name == name && $0.hidden }?.id
    }

    package mutating func stash(_ id: CGWindowID, as name: String) {
        forget(id)
        entries.append(Entry(id: id, name: name, hidden: true))
    }

    package mutating func hide(_ id: CGWindowID) {
        guard let name = name(of: id) else { return }
        stash(id, as: name)
    }

    package mutating func reveal(_ id: CGWindowID) {
        if let index = entries.firstIndex(where: { $0.id == id }) { entries[index].hidden = false }
    }

    package mutating func forget(_ id: CGWindowID) { entries.removeAll { $0.id == id } }
}

package struct PinnedWindows {
    package private(set) var ids: Set<CGWindowID> = []
    private var retryAfter: [CGWindowID: Date] = [:]

    package func contains(_ id: CGWindowID) -> Bool { ids.contains(id) }

    package mutating func pin(_ id: CGWindowID) { ids.insert(id) }

    package mutating func forget(_ id: CGWindowID) {
        ids.remove(id)
        retryAfter[id] = nil
    }

    package mutating func claimFollow(_ id: CGWindowID, now: Date = Date()) -> Bool {
        guard retryAfter[id].map({ now >= $0 }) ?? true else { return false }
        retryAfter[id] = now.addingTimeInterval(1)
        return true
    }
}
