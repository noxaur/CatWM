import AppKit

package struct DesktopGuardReply {
    package private(set) var ready = false, finished = false, context = 0
    package private(set) var released = -1
    package private(set) var restoreSubmitted = -1
    private var buffer = ""

    package mutating func receive(_ text: String) {
        buffer += text
        while let end = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<end])
            buffer.removeSubrange(...end)
            if line == "READY" { ready = true }
            if line == "DONE" { finished = true }
            if line.hasPrefix("CONTEXT_READY "), let id = Int(line.dropFirst(14)) { context = max(context, id) }
            if line.hasPrefix("RELEASED "), let id = Int(line.dropFirst(9)) { released = max(released, id) }
            if line.hasPrefix("RESTORE_SUBMITTED "), let id = Int(line.dropFirst(18)) {
                restoreSubmitted = max(restoreSubmitted, id)
            }
        }
    }
}
