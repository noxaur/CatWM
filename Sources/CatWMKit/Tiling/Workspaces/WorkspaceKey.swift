import CoreGraphics

package enum WorkspaceKey {
    package static let spacePrefix = "space:"
    package static let pendingPrefix = "sort-close:"

    package static func space(display: String, space: UInt64) -> String { "\(spacePrefix)\(display):\(space)" }

    package static func make(_ number: String, on display: String, perDisplay: Bool) -> String {
        perDisplay ? "\(display)/\(number)" : number
    }

    package static func display(_ key: String) -> String? {
        key.lastIndex(of: "/").map { String(key[..<$0]) }
    }

    package static func number(_ key: String) -> String {
        key.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? key
    }

    package static func numeric(_ key: String) -> Int? { Int(number(key)) }

    package static func ordinal(_ key: String) -> Int { numeric(key) ?? 0 }

    package static func precedes(_ first: String, _ second: String) -> Bool {
        switch (numeric(first), numeric(second)) {
        case let (x?, y?): x < y
        case (_?, nil): true
        case (nil, _?): false
        default: first < second
        }
    }
}
