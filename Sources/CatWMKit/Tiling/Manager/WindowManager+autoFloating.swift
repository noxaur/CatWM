import AppKit

extension WindowManager {
    private static let alwaysFloatingApps: Set<String> = [
        "com.apple.installer",
        "com.apple.PackageKit.Install-Progress",
        "com.apple.DiskImageMounter",
        "com.apple.archiveutility",
        "com.apple.MigrateAssistant",
        "com.apple.SoftwareUpdate",
        "com.apple.Stickies",
        "com.apple.PhotoBooth",
        "com.apple.Chess",
        "com.apple.DigitalColorMeter",
        "com.apple.printcenter",
        "com.apple.BluetoothFileExchange",
        "com.apple.ColorSyncUtility",
        "com.apple.Magnifier",
        "com.yourcompany.installerbase",
        "io.balena.etcher",
        "com.wireguard.macos",
        "io.tailscale.ipn.macsys",
        "io.tailscale.ipn.macos",
        "com.jetbrains.toolbox",
        "com.lujjjh.LinearMouse",
        "com.amethyst.Amethyst",
        "org.sparkle-project.Sparkle.Autoupdate",
        "com.microsoft.autoupdate2"
    ]

    package static func isSignInTitle(_ title: String) -> Bool {
        var rest = Substring(title.lowercased())
        guard rest.removePrefix("sign") || rest.removePrefix("log") else { return false }
        if let separator = rest.first, separator == " " || separator == "-" { rest.removeFirst() }
        guard rest.removePrefix("in") else { return false }
        guard let next = rest.first else { return true }
        return next.isWhitespace || "-–—|:,".contains(next)
    }

    private func isUtilityWindow(_ window: Window, title: String?) -> Bool {
        guard let title, !title.isEmpty else { return false }
        if title == "Picture in Picture" || title == "Picture-in-Picture" { return true }
        if window.bundleID == "com.apple.finder" { return title.hasSuffix(" Info") }
        if Self.isSignInTitle(title) { return true }
        let settings = ["Settings", "Preferences", "Settings…", "Preferences…"]
        if settings.contains(title) { return true }
        guard settings.contains(where: { title.hasSuffix(" \($0)") }),
              let app = NSRunningApplication(processIdentifier: window.pid)?.localizedName else { return false }
        return settings.contains { title == "\(app) \($0)" }
    }

    private func isMountedImageWindow(title: String?) -> Bool {
        guard let title, !title.isEmpty else { return false }
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsEjectableKey, .volumeIsInternalKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                            options: [.skipHiddenVolumes]) ?? []
        return volumes.contains { url in
            guard url.path != "/", let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            return values.volumeName == title && (values.volumeIsEjectable == true || values.volumeIsInternal == false)
        }
    }

    package func shouldFloat(_ window: Window) -> Bool {
        shouldFloat(window, title: window.title, resizable: window.resizable)
    }

    package func shouldFloat(_ window: Window, title: String?, resizable: Bool) -> Bool {
        if let practice, window.pid == practice.pid { return false }
        if let bundle = window.bundleID,
           bundle == Bundle.main.bundleIdentifier || bundle.hasPrefix("local.catwm")
            || Legacy.isBundle(bundle) {
            return true
        }
        if let bundle = window.bundleID, Self.alwaysFloatingApps.contains(bundle) { return true }
        if window.bundleID == "com.apple.finder", isMountedImageWindow(title: title) { return true }
        if isUtilityWindow(window, title: title) { return true }
        if let bundle = window.bundleID {
            let listed = Config.lists(bundle, in: config.floating)
            if config.floatingIsDenylist ? listed : !listed { return true }
        } else if !config.floatingIsDenylist {
            return true
        }
        if !resizable { return true }
        let frame = window.naturalFrame
        if config.floatSmallWindows, !frame.isNull, frame.width < 500, frame.height < 500 { return true }
        return false
    }
}

private extension Substring {
    mutating func removePrefix(_ prefix: String) -> Bool {
        guard hasPrefix(prefix) else { return false }
        removeFirst(prefix.count)
        return true
    }
}
