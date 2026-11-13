import Foundation
import os

package enum TextPattern {
    package struct Failure: Error {
        package let message: String
    }

    private static let compiled = OSAllocatedUnfairLock(initialState: [String: NSRegularExpression?]())

    package static func split(_ text: String) -> (source: String, flags: String)? {
        guard text.first == "/", let end = text.lastIndex(of: "/"), end > text.startIndex else { return nil }
        let flags = text[text.index(after: end)...]
        guard flags.allSatisfy(\.isLetter) else { return nil }
        return (String(text[text.index(after: text.startIndex)..<end]), String(flags))
    }

    package static func written(source: String, flags: String) -> String { "/\(source)/\(flags)" }

    package static func regex(_ source: String, flags: String) throws -> NSRegularExpression {
        var options: NSRegularExpression.Options = []
        for flag in flags {
            switch flag {
            case "i": options.insert(.caseInsensitive)
            case "m": options.insert(.anchorsMatchLines)
            case "s": options.insert(.dotMatchesLineSeparators)
            case "g", "u", "y", "d": continue
            default: throw Failure(message: "uses the regular expression flag `\(flag)`, which CatWM can't match")
            }
        }
        do {
            return try NSRegularExpression(pattern: source, options: options)
        } catch {
            throw Failure(message: "is the regular expression /\(source)/, which CatWM can't match: "
                + error.localizedDescription)
        }
    }

    package static func regex(written text: String) throws -> NSRegularExpression? {
        guard let (source, flags) = split(text) else { return nil }
        return try regex(source, flags: flags)
    }

    package static func glob(_ text: String, _ pattern: String) -> Bool {
        pattern.hasSuffix("*") ? text.hasPrefix(String(pattern.dropLast())) : text == pattern
    }

    package static func lists(_ text: String, in entries: [String]) -> Bool {
        entries.contains { entry in
            guard entry.first == "/" else { return glob(text, entry) }
            return cached(entry).map { $0.hasMatch(in: text) } ?? glob(text, entry)
        }
    }

    private static func cached(_ entry: String) -> NSRegularExpression? {
        if let known = compiled.withLock({ $0[entry] }) { return known }
        let regex = try? regex(written: entry)
        compiled.withLock { $0[entry] = .some(regex) }
        return regex
    }
}

extension NSRegularExpression {
    package func hasMatch(in text: String) -> Bool {
        firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
