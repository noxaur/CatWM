import CoreGraphics

package struct Measure: Equatable {
    package var value: CGFloat
    package var percent = false
    package var relative = false

    package static func exact(_ points: CGFloat) -> Self { Self(value: points) }

    package init?(_ token: Substring, exact: Bool) {
        var text = token
        let percent = text.last == "%"
        if percent { text.removeLast() }
        guard let value = Double(text), value.isFinite else { return nil }
        let signed = text.hasPrefix("+") || text.hasPrefix("-")
        guard exact || signed || percent || value == 0 else { return nil }
        self.value = CGFloat(value)
        self.percent = percent
        relative = !exact && (signed || !percent)
    }

    private init(value: CGFloat) { self.value = value }

    package func amount(of extent: CGFloat) -> CGFloat { percent ? value / 100 * extent : value }

    package func resolve(from current: CGFloat, of extent: CGFloat) -> CGFloat {
        relative ? current + amount(of: extent) : amount(of: extent)
    }

    package static func pair(_ arg: String) -> (Measure, Measure)? {
        var tokens = arg.lowercased().split(whereSeparator: \.isWhitespace)
        let exact = tokens.first == "exact"
        if exact { tokens.removeFirst() }
        guard tokens.count == 2, let first = Measure(tokens[0], exact: exact),
              let second = Measure(tokens[1], exact: exact) else { return nil }
        return (first, second)
    }
}
