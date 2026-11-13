import AppKit
import ApplicationServices

package enum SystemShortcut {
    package struct Combo {
        package let keyCode: UInt16
        package let flags: CGEventFlags

        package init(keyCode: UInt16, flags: CGEventFlags) {
            self.keyCode = keyCode
            self.flags = flags
        }
    }

    private static func read(_ id: Int) -> (enabled: Bool, combo: Combo)? {
        guard let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
                .dictionary(forKey: "AppleSymbolicHotKeys"), // style-ok: a system preference key, not ours
              let entry = all[String(id)] as? [String: Any] else { return nil }
        let enabled = (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int).map { $0 != 0 } ?? false)
        guard let params = (entry["value"] as? [String: Any])?["parameters"] as? [Int], params.count == 3
        else { return nil }
        return (enabled, Combo(keyCode: UInt16(truncatingIfNeeded: params[1]),
                               flags: CGEventFlags(rawValue: UInt64(truncatingIfNeeded: params[2]))))
    }

    package static func desktop(_ number: Int) -> Combo? {
        guard (1...16).contains(number), let shortcut = read(117 + number), shortcut.enabled else { return nil }
        return shortcut.combo
    }

    package static func step(right: Bool) -> Combo? {
        if let shortcut = read(right ? 81 : 79) { return shortcut.enabled ? shortcut.combo : nil }
        return Combo(keyCode: right ? 124 : 123, flags: [.maskControl, .maskSecondaryFn])
    }
}
