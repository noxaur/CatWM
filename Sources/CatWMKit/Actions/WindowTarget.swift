import Foundation

package struct WindowTarget: Equatable, Sendable {
    package struct Failure: Error {
        package let message: String
    }

    package let condition: Condition

    private static let fields: [String: Fact] = [
        "app": .app, "title": .title, "id": .id, "address": .id, "pid": .pid, "workspace": .workspace,
        "display": .display
    ]

    package static let syntax = "`app:<bundle ID, `*` at the end, or /regex/>`, `title:<text or /regex/>`, "
        + "`id:<window ID>`, `pid:<pid>`, `workspace:<name>` or `display:<name>`"

    package init(_ text: String) throws {
        let body = text.hasPrefix("@") ? String(text.dropFirst()) : text
        guard let colon = body.firstIndex(of: ":"), let fact = Self.fields[body[..<colon].lowercased()] else {
            throw Failure(message: "`\(text)` is not a window target. Use \(Self.syntax)")
        }
        var value = String(body[body.index(after: colon)...])
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }
        guard !value.isEmpty else { throw Failure(message: "`\(text)` has no value after the colon") }
        switch fact {
        case .id, .pid:
            guard let number = Int(value) else { throw Failure(message: "`\(text)` needs a number") }
            condition = .compare(fact, .equal, .int(number))
        default:
            do {
                condition = try Condition.text(fact, value)
            } catch let failure as TextPattern.Failure {
                throw Failure(message: "`\(text)` \(failure.message)")
            }
        }
    }

    package static func leading(in arg: String) throws -> (target: WindowTarget, rest: String)? {
        guard arg.hasPrefix("@") else { return nil }
        let chars = Array(arg)
        var index = chars.firstIndex(of: ":").map { $0 + 1 } ?? chars.count
        if index < chars.count, chars[index] == "\"" {
            index += 1
            while index < chars.count, chars[index] != "\"" { index += 1 }
            index = min(index + 1, chars.count)
        } else if index < chars.count, chars[index] == "/" {
            index += 1
            while index < chars.count, chars[index] != "/" { index += chars[index] == "\\" ? 2 : 1 }
            index = min(index, chars.count)
        }
        while index < chars.count, !chars[index].isWhitespace { index += 1 }
        let rest = String(chars[index...]).trimmingCharacters(in: .whitespaces)
        return (try WindowTarget(String(chars[..<index])), rest)
    }
}
