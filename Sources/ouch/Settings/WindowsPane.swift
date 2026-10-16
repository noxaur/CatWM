// Settings: the Windows pane (floating, focus and window behavior options).
import AppKit
import SwiftUI

// MARK: - Windows

struct WindowsPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI

    private var runningApps: [(name: String, id: String, icon: NSImage?)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.processIdentifier != getpid() }
            .map { ($0.localizedName ?? $0.bundleIdentifier!, $0.bundleIdentifier!, $0.icon) }
            .filter { app in !doc.config.floating.contains(app.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            OGroup("Focus") {
                OptionSwitch(\.focusFollowsMouse, doc: doc, ui: ui)
                OptionSwitch(\.focusFollowsMouseInModeOnly, doc: doc, ui: ui)
                    .disabled(!doc.config.focusFollowsMouse)
                OptionSwitch(\.mouseFollowsFocus, doc: doc, ui: ui)
                OptionSwitch(\.dimOtherWindows, doc: doc, ui: ui)
                OptionSlider(\.dimStrength, doc: doc, ui: ui, format: { "\(Int($0))%" })
                    .disabled(!doc.config.dimOtherWindows)
                OptionSwitch(\.blurOtherWindows, doc: doc, ui: ui)
                OptionSlider(\.blurRadius, doc: doc, ui: ui, format: { "\(Int($0)) pt" })
                    .disabled(!doc.config.blurOtherWindows)
            }

            OGroup("Mouse") {
                OptionSwitch(\.mouseSwapsWindows, doc: doc, ui: ui)
                OptionSwitch(\.mouseResizesWindows, doc: doc, ui: ui)
                OptionSwitch(\.cursorActions, doc: doc, ui: ui)
            }

            OGroup("Floating") {
                OptionRow(\Config.floatingIsBlacklist, ui: ui,
                          description: doc.config.floatingIsBlacklist ? "Float; everything else tiles" : "Are the only ones that tile") { label in
                    OSegmented(title: label, options: [(true, "Float"), (false, "Tile")], selection: $doc.config.floatingIsBlacklist)
                }
                if doc.config.floating.isEmpty {
                    ORow("No apps yet", description: "Add one that's running, or by bundle ID under Advanced") { addMenu }
                } else {
                    ForEach(doc.config.floating, id: \.self) { id in
                        HStack(spacing: 12) {
                            appIcon(id)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(appName(id) ?? id).font(Theme.body(14)).oneLine()
                                if appName(id) != nil { Text(id).font(Theme.mono(11, .regular)).foregroundStyle(Theme.inkMuted).oneLine(.middle) }
                            }
                            Spacer(minLength: 0)
                            RemoveButton(help: "Remove \(appName(id) ?? id)") {
                                withAnimation(Motion.easeOut) { doc.config.floating.removeAll { $0 == id } }
                            }
                        }
                        .frame(minHeight: 48).padding(.vertical, 6)
                    }
                    HStack { Spacer(); addMenu }.padding(.vertical, 10)
                }
            }

            OGroup("Workspaces") {
                OptionSwitch(\.virtualWorkspaces, doc: doc, ui: ui)
                OptionRow(\Config.sortStrategy, ui: ui) { label in
                    OMenuPicker(title: label, options: SortStrategy.allCases.map { ($0, $0.title) }, selection: $doc.config.sortStrategy)
                }
                .disabled(!doc.config.virtualWorkspaces)
                // One option, two rows: the switch turns the tip on at the default count, the slider sets the count.
                let nudge = ConfigOption.at(\Config.sortNudge)
                OSwitchRow(nudge.ui.label, description: nudge.ui.help,
                           isOn: Binding(get: { doc.config.sortNudge > 0 }, set: { doc.config.sortNudge = $0 ? Int(nudge.resetValue) : 0 }))
                    .disabled(!doc.config.virtualWorkspaces)
                    .setting(nudge.ui.id, ui)
                ORow("Crowded from", description: "Windows on one workspace") {
                    OSlider(value: Binding(get: { Double(doc.config.sortNudge) },
                                           set: { doc.config.sortNudge = Int($0.rounded()) }),
                            range: nudge.sliderRange(holding: Double(doc.config.sortNudge)), step: 1, ticks: [nudge.resetValue],
                            resetValue: nudge.resetValue, width: 160, label: "Crowded from", format: { "\(Int($0)) windows" })
                }
                .disabled(!doc.config.virtualWorkspaces || doc.config.sortNudge == 0)
                .setting("windows.sortCrowded", ui)
            }

            AdvancedSection(pane: .windows, ui: ui) {
                OGroup("Windows") {
                    OptionSwitch(\.newWindowsToMain, doc: doc, ui: ui)
                    OptionSwitch(\.floatSmallWindows, doc: doc, ui: ui)
                    ORow("Add app by bundle ID", description: "Wildcards like com.adobe.* work too") {
                        OTextField(placeholder: "com.example.app", text: $ui.newID, mono: true, onSubmit: add).frame(width: 190)
                        OButton("Add", size: .sm, action: add)
                            .disabled(ui.newID.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .setting("windows.bundleID", ui)
                }
                OGroup("Workspaces") {
                    OptionSwitch(\.stayOnWorkspaceAfterClose, doc: doc, ui: ui)
                        .disabled(!doc.config.virtualWorkspaces)
                    ORow("Home Desktop", description: WindowManager.shared.homeSpaceSummary.isEmpty ? "The Desktop you're on when Ouch starts"
                        : "Workspaces live on \(WindowManager.shared.homeSpaceSummary)") {
                        OButton("Use This Desktop", size: .sm) { WindowManager.shared.makeCurrentSpaceHome() }
                    }
                    .disabled(!doc.config.virtualWorkspaces)
                    .setting("windows.home", ui)
                }
            }
        }
    }

    private var addMenu: some View {
        let doc = doc, apps = runningApps
        return OMenuButton(style: OButtonStyle(variant: .secondary, size: .sm), items: {
            apps.map { app in
                MenuItem(id: app.id, label: app.name, image: app.icon.map(resized), enabled: !doc.config.floating.contains(app.id), action: {
                    if !doc.config.floating.contains(app.id) { withAnimation(Motion.easeOut) { doc.config.floating.append(app.id) } }
                })
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 11.5, weight: .medium))
                Text("Add Running App")
            }
        }
        .fixedSize()
    }

    private func add() {
        let id = ui.newID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !doc.config.floating.contains(id) else { return }
        withAnimation(Motion.easeOut) { doc.config.floating.append(id) }
        ui.newID = ""
    }

    private func resized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    private func appURL(_ id: String) -> URL? {
        id.hasSuffix("*") ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }
    private func appName(_ id: String) -> String? {
        appURL(id).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }
    @ViewBuilder private func appIcon(_ id: String) -> some View {
        if let url = appURL(id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
        } else {
            RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .frame(width: 26, height: 26).padding(1)
        }
    }
}
