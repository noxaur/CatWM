import Foundation

extension ConfigEdit {
    static let valueWords: Set<String> = [
        "return", "typeof", "case", "in", "of", "instanceof", "void", "delete"
    ]

    static func tokens(_ source: String) -> [Token]? {
        var scanner = Lexer(bytes: Array(source.utf8))
        while scanner.next() {}
        return scanner.failed ? nil : scanner.tokens
    }

    struct Lexer {
        let bytes: [UInt8]
        var tokens: [Token] = []
        var index = 0, line = 1, depth = 0
        var failed = false

        init(bytes: [UInt8]) { self.bytes = bytes }

        private func peek(_ offset: Int = 0) -> UInt8 { index + offset < bytes.count ? bytes[index + offset] : 0 }

        private static func isIdentifier(_ byte: UInt8) -> Bool {
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
                || byte == 0x5F || byte == 0x24 || byte >= 0x80
        }

        private static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

        mutating func next() -> Bool {
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x0A {
                    line += 1
                    index += 1
                } else if byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0B || byte == 0x0C {
                    index += 1
                } else if byte == 0x2F, peek(1) == 0x2F {
                    while index < bytes.count, bytes[index] != 0x0A { index += 1 }
                } else if byte == 0x2F, peek(1) == 0x2A {
                    guard skipBlockComment() else { return fail() }
                } else {
                    return token(byte)
                }
            }
            return false
        }

        private mutating func fail() -> Bool {
            failed = true
            return false
        }

        private mutating func skipBlockComment() -> Bool {
            index += 2
            while index < bytes.count {
                if bytes[index] == 0x2A, peek(1) == 0x2F {
                    index += 2
                    return true
                }
                if bytes[index] == 0x0A { line += 1 }
                index += 1
            }
            return false
        }

        private mutating func token(_ byte: UInt8) -> Bool {
            let start = index, startLine = line
            guard let kind = scan(byte) else { return fail() }
            let text = String(bytes: bytes[start..<index], encoding: .utf8) ?? ""
            var tokenDepth = depth
            if kind == .punct, "{([".contains(text) {
                depth += 1
            } else if kind == .punct, "})]".contains(text) {
                depth = max(0, depth - 1)
                tokenDepth = depth
            }
            tokens.append(Token(kind: kind, text: text, start: start, end: index, line: startLine, depth: tokenDepth))
            return true
        }

        private mutating func scan(_ byte: UInt8) -> Kind? {
            if byte == 0x22 || byte == 0x27 { return skipString(byte) ? .string : nil }
            if byte == 0x60 { return skipTemplate() ? .template : nil }
            if Self.isDigit(byte) || (byte == 0x2E && Self.isDigit(peek(1))) {
                skipNumber()
                return .number
            }
            if Self.isIdentifier(byte) {
                while Self.isIdentifier(peek()), index < bytes.count { index += 1 }
                return .ident
            }
            if byte == 0x2F, startsRegex() { return skipRegex() ? .regex : nil }
            if byte == 0x3D, peek(1) == 0x3D || peek(1) == 0x3E {
                index += peek(1) == 0x3D && peek(2) == 0x3D ? 3 : 2
            } else {
                index += 1
            }
            return .punct
        }

        private mutating func skipString(_ quote: UInt8) -> Bool {
            index += 1
            while index < bytes.count {
                let byte = bytes[index]
                if byte == quote {
                    index += 1
                    return true
                }
                if byte == 0x0A { return false }
                index += byte == 0x5C ? 2 : 1
            }
            return false
        }

        private mutating func skipTemplate() -> Bool {
            index += 1
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x60 {
                    index += 1
                    return true
                }
                if byte == 0x0A { line += 1 }
                if byte == 0x24, peek(1) == 0x7B {
                    index += 2
                    guard skipExpression() else { return false }
                    continue
                }
                index += byte == 0x5C ? 2 : 1
            }
            return false
        }

        private mutating func skipExpression() -> Bool {
            var braces = 1
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x22 || byte == 0x27 {
                    guard skipString(byte) else { return false }
                    continue
                }
                if byte == 0x60 {
                    guard skipTemplate() else { return false }
                    continue
                }
                if byte == 0x0A { line += 1 }
                if byte == 0x7B { braces += 1 }
                if byte == 0x7D {
                    braces -= 1
                    if braces == 0 {
                        index += 1
                        return true
                    }
                }
                index += 1
            }
            return false
        }

        private mutating func skipNumber() {
            while index < bytes.count {
                let byte = bytes[index]
                let sign = (byte == 0x2B || byte == 0x2D) && (bytes[index - 1] | 0x20) == 0x65
                if Self.isIdentifier(byte) || byte == 0x2E || sign { index += 1 } else { return }
            }
        }

        private func startsRegex() -> Bool {
            guard let previous = tokens.last else { return true }
            switch previous.kind {
            case .number, .string, .template, .regex: return false
            case .ident: return ConfigEdit.valueWords.contains(previous.text)
            case .punct: return ![")", "]", "}"].contains(previous.text)
            }
        }

        private mutating func skipRegex() -> Bool {
            index += 1
            var inClass = false
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x0A { return false }
                if byte == 0x5C {
                    index += 2
                    continue
                }
                if byte == 0x5B { inClass = true }
                if byte == 0x5D { inClass = false }
                index += 1
                if byte == 0x2F, !inClass {
                    while Self.isIdentifier(peek()), index < bytes.count { index += 1 }
                    return true
                }
            }
            return false
        }
    }
}
