# Ouch: agent guide

Ouch is a macOS tiling window manager (Swift, SwiftPM, one target `ouch`). Old names: Hyprthyst, then mxtiler. Paths with those names are stale. All code is in `Sources/ouch/`.

## Find code

Use the map below first. Each file name is unique, so `find Sources -name <File>.swift` gives its path.

1. Find the file for the feature in the map.
2. Run `grep -n 'MARK\|func \|class \|struct ' <file>` to get a table of contents.
3. Read only the line ranges you need (`Read` with offset/limit, or `sed -n A,Bp`).
4. Do not read or `cat` a whole file over 300 lines.
5. Scope searches to `Sources/`. Do not run `grep -r` from the repo root (it scans `design/`, `.build/` and `build/`).
6. Use `| tail -25` or `grep -E 'error|warning:'` on build output.

## Feature map

| Feature | Files |
|---|---|
| Tiling, focus, commands, workspaces, Spaces | `WindowManager.swift` (2.5k lines; use its `// MARK:` sections: Lifecycle, Observing apps, Refresh & tiling, Geometry helpers, Focus & mouse, Status & IPC, Commands, Ouch workspaces, Sort, Spaces) |
| Layout math (tall, wide, BSP, …) | `Layouts.swift` |
| Window movement animation | `Animator.swift`, `PanelMotion.swift` (Sort panel and Keyboard Help entrance) |
| Accessibility API, private symbols, `Window`, `Screen` | `AX.swift` |
| Native Space moves and Dock imports | `NativeSpaceMove.swift`, `DockWindowPull.swift`, `WindowServerUpdates.swift` |
| Focus dim/blur, mode screen-edge effect, layout HUD | `FocusDim.swift`, `ModeFX.swift`, `HUD.swift` |
| Global keybinds (CGEventTap) | `Hotkeys.swift` |
| Config file parse (Hyprland syntax), binds | `Config.swift` |
| Config editing model, human-readable actions | `ConfigDocument.swift` |
| Saved configs, import/export, config picker UI | `Configs.swift`, `ConfigsUI.swift` |
| Settings window, search, pane list | `SettingsWindow.swift` |
| Settings panes (General, Layout, …) | `SettingsPanes.swift` |
| Keyboard shortcut map (full window) | `ShortcutMap.swift` |
| Drawn Mac keyboard | `KeyHintKeyboard.swift` (view), `MacKeyboard.swift` (model, finish, layout) |
| On-screen keyboard help, trackpad gestures | `KeyHelp.swift`, `GesturePad.swift` |
| Menu bar menu and icon | `StatusMenu.swift`, `MenuBarIcon.swift`, `MenuBarTip.swift` |
| Popups, popovers, tooltips | `Popups.swift` |
| Design system: colours, type, motion, controls | `Theme.swift`, `Components.swift` |
| Onboarding: intro, welcome card, overlays | `Onboarding.swift`, `OnboardingViews.swift`, `IntroScore.swift` (music), `IntroLab.swift` (dev tool) |
| Tour and tutorial | `Coach.swift` (runner), `Lessons.swift` (scripts), `PracticeDesk.swift` (practice windows) |
| Accessibility permission guide | `PermissionGuide.swift` |
| Tips after onboarding | `Tips.swift` |
| Sort Windows | `Sort.swift` (data), `SortModel.swift` (state), `SortViews.swift`, `SortPanel.swift`, `SortEntry.swift` (nudges) |
| Bug reports, crash watch | `BugReport.swift`, `BugReportViews.swift` |
| App start, CLI subcommands | `main.swift` |
| Updates, login item, log, drag-anywhere | `Updater.swift`, `LoginItem.swift`, `Log.swift`, `DragAnywhere.swift` |

Other folders: `design/` (specs and prototypes), `Tools/` (probe scripts), `report-relay/` (Cloudflare Worker for bug reports), `Resources/` (fonts, icon).

## Build

- `swift build 2>&1 | tail -25` to check that it compiles.
- `./build.sh` makes `build/ouch.app`. `open build/ouch.app` runs it.

## Sessions

- Keep one task per session. Long sessions carry all earlier tool output into each turn.
- Keep this file short. Agents load it on each turn. When you move or add a feature file, update the map.
