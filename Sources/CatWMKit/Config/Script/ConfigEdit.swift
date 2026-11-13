import Foundation

enum ConfigEdit {
    static let marker = "// Settings"

    enum Kind {
        case ident, punct, string, template, number, regex
    }

    struct Token {
        var kind: Kind
        var text: String
        var start: Int
        var end: Int
        var line: Int
        var depth: Int
    }

    private struct Candidate {
        var value: Range<Int>
        var lines: ClosedRange<Int>
    }

    static func replacing(_ path: String, with value: JSON, in source: String, near line: Int) -> String? {
        guard let tokens = tokens(source) else { return nil }
        let found = candidates(path, in: tokens)
        let inside = found.last { $0.lines.contains(line) }
        let nearest = found.min { distance($0.lines, line) < distance($1.lines, line) }
        guard let hit = inside ?? nearest else { return nil }
        return splice(value, over: hit, tokens: tokens, in: source)
    }

    static func settings(_ path: String, _ value: JSON, in source: String) -> String {
        var text = source
        let lines = text.components(separatedBy: "\n")
        let markerLine = lines.lastIndex { $0.trimmingCharacters(in: .whitespaces) == marker }.map { $0 + 1 }
        if let markerLine, let tokens = tokens(text),
           let hit = candidates(path, in: tokens, exact: true).last(where: { $0.lines.lowerBound > markerLine }),
           let replaced = splice(value, over: hit, tokens: tokens, in: text) {
            return replaced
        }
        if markerLine == nil {
            if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
            if !text.isEmpty { text += "\n" }
            text += marker + "\n"
        }
        if !text.hasSuffix("\n") { text += "\n" }
        text += "catwm.\(path) = \(ConfigScript.literal(value))\n"
        return importsCatwm(text) ? text : "import { catwm } from \"./catwm\"\n" + text
    }

    private static func importsCatwm(_ text: String) -> Bool {
        text.range(of: #"import\s*\{[^}]*\bcatwm\b[^}]*\}"#, options: .regularExpression) != nil
    }

    private static func distance(_ lines: ClosedRange<Int>, _ line: Int) -> Int {
        lines.contains(line) ? 0 : min(abs(lines.lowerBound - line), abs(lines.upperBound - line))
    }

    private static func splice(_ value: JSON, over hit: Candidate, tokens: [Token], in source: String) -> String? {
        let bytes = Array(source.utf8)
        let first = tokens[hit.value.lowerBound], last = tokens[hit.value.upperBound - 1]
        var lineStart = first.start
        while lineStart > 0, bytes[lineStart - 1] != 0x0A { lineStart -= 1 }
        var indent = 0
        while lineStart + indent < bytes.count, bytes[lineStart + indent] == 0x20 { indent += 1 }
        let literal = ConfigScript.literal(value, indent: indent)
        guard let head = String(bytes: bytes[..<first.start], encoding: .utf8),
              let tail = String(bytes: bytes[last.end...], encoding: .utf8) else { return nil }
        return head + literal + tail
    }

    private static let continuations: Set<String> = [
        "+", "-", "*", "/", "%", ".", "(", "[", "?", ":", ",", "&", "|", "^", "<", ">", "=", "in", "instanceof", "as"
    ]
    private static let openers: Set<String> = [
        "else", "do", "return", "throw", "typeof", "void", "delete", "new", "await", "yield", "in", "of", "case",
        "default", "extends", "instanceof"
    ]

    private static func candidates(_ path: String, in tokens: [Token], exact: Bool = false) -> [Candidate] {
        var found: [Candidate] = []
        for index in tokens.indices where tokens[index].kind == .ident && tokens[index].text == "catwm"
            && tokens[index].depth == 0 && isStatementStart(index, tokens) {
            var last = index, parts: [String] = []
            while last + 2 < tokens.count, tokens[last + 1].text == ".", tokens[last + 2].kind == .ident {
                parts.append(tokens[last + 2].text)
                last += 2
            }
            let equals = last + 1
            guard !parts.isEmpty, equals + 1 < tokens.count, tokens[equals].kind == .punct,
                  tokens[equals].text == "=" else { continue }
            let chain = parts.joined(separator: ".")
            let from = tokens[index].line
            if chain == path {
                guard let end = literalEnd(equals + 1, tokens), isSettled(end, after: end - 1, tokens) else {
                    continue
                }
                found.append(Candidate(value: (equals + 1)..<end, lines: from...tokens[end - 1].line))
            } else if !exact, path.hasPrefix(chain + "."), tokens[equals + 1].text == "{" {
                let rest = path.dropFirst(chain.count + 1).split(separator: ".").map(String.init)
                guard let value = member(rest[...], in: equals + 1, tokens), let close = close(equals + 1, tokens)
                else { continue }
                found.append(Candidate(value: value, lines: from...tokens[close].line))
            }
        }
        return found
    }

    private static func isSettled(_ end: Int, after last: Int, _ tokens: [Token]) -> Bool {
        guard end < tokens.count else { return true }
        let next = tokens[end]
        if next.text == ";" { return true }
        return next.kind != .template && next.line > tokens[last].line && !continuations.contains(next.text)
    }

    private static func isStatementStart(_ index: Int, _ tokens: [Token]) -> Bool {
        guard index > 0 else { return true }
        let previous = tokens[index - 1]
        if previous.kind == .punct, previous.text == ";" || previous.text == "}" { return true }
        guard previous.line < tokens[index].line else { return false }
        switch previous.kind {
        case .string, .number, .template, .regex: return true
        case .ident: return !openers.contains(previous.text)
        case .punct:
            switch previous.text {
            case "]": return true
            case ")":
                let opens = tokens[..<(index - 1)].lastIndex { $0.text == "(" && $0.depth == previous.depth }
                guard let open = opens else { return false }
                return open == 0 || !["if", "for", "while", "with"].contains(tokens[open - 1].text)
            default: return false
            }
        }
    }

    private static func close(_ open: Int, _ tokens: [Token]) -> Int? {
        tokens[open...].firstIndex { $0.text == "}" && $0.depth == tokens[open].depth }
    }

    private static func member(_ rest: ArraySlice<String>, in open: Int, _ tokens: [Token]) -> Range<Int>? {
        guard let name = rest.first, let close = close(open, tokens) else { return nil }
        let inner = tokens[open].depth + 1
        var found: Range<Int>?
        var index = open + 1
        while index < close {
            let token = tokens[index]
            if token.depth == inner, [.ident, .string, .number].contains(token.kind), index + 2 < close,
               tokens[index + 1].text == ":", key(token) == name {
                let value = index + 2
                found = nil
                if rest.count == 1 {
                    if let end = literalEnd(value, tokens), end <= close,
                       tokens[end].text == "," || tokens[end].text == "}" {
                        found = value..<end
                    }
                } else if tokens[value].text == "{" {
                    found = member(rest.dropFirst(), in: value, tokens)
                }
            }
            while index < close, !(tokens[index].depth == inner && tokens[index].text == ",") { index += 1 }
            index += 1
        }
        return found
    }

    private static func key(_ token: Token) -> String {
        token.kind == .string ? String(token.text.dropFirst().dropLast()) : token.text
    }

    private static func literalEnd(_ start: Int, _ tokens: [Token]) -> Int? {
        guard start < tokens.count else { return nil }
        let token = tokens[start]
        switch token.kind {
        case .string, .number: return start + 1
        case .ident: return ["true", "false", "null"].contains(token.text) ? start + 1 : nil
        case .punct where token.text == "-":
            return start + 1 < tokens.count && tokens[start + 1].kind == .number ? start + 2 : nil
        case .punct where token.text == "[": return list(start, tokens)
        case .punct where token.text == "{": return object(start, tokens)
        default: return nil
        }
    }

    private static func list(_ open: Int, _ tokens: [Token]) -> Int? {
        var index = open + 1
        while index < tokens.count {
            if tokens[index].text == "]" { return index + 1 }
            guard let end = literalEnd(index, tokens), end < tokens.count else { return nil }
            index = end
            if tokens[index].text == "," { index += 1 } else if tokens[index].text != "]" { return nil }
        }
        return nil
    }

    private static func object(_ open: Int, _ tokens: [Token]) -> Int? {
        var index = open + 1
        while index + 2 < tokens.count {
            if tokens[index].text == "}" { return index + 1 }
            guard [.ident, .string, .number].contains(tokens[index].kind), tokens[index + 1].text == ":",
                  let end = literalEnd(index + 2, tokens), end < tokens.count else { return nil }
            index = end
            if tokens[index].text == "," { index += 1 } else if tokens[index].text != "}" { return nil }
        }
        return index < tokens.count && tokens[index].text == "}" ? index + 1 : nil
    }
}
