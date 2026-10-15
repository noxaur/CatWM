# Ouch: agent guide

Ouch is a macOS tiling window manager (Swift, SwiftPM, one target `ouch`). All code is in `Sources/ouch/`.

## Feature map

Paths are relative to `Sources/ouch/`. Each file starts with a one-line comment that names its feature.

| Feature | Files |
|---|---|
| Window manager core state, lifecycle | `Tiling/WindowManager.swift` |
| Watch apps and windows, float rules | `Tiling/WindowManager+Observing.swift` |
| Tile refresh loop, layout slots, screen geometry | `Tiling/WindowManager+Layout.swift` |
| Focus, focus-follows-mouse, mouse drag/resize | `Tiling/WindowManager+Focus.swift` |
| Keyboard command dispatch, status, IPC | `Tiling/WindowManager+Commands.swift` |
| Ouch workspaces: names, lookup, displays | `Tiling/WindowManager+Workspaces.swift` |
| Switch workspaces, move windows between them | `Tiling/WindowManager+WorkspaceSwitching.swift` |
| Park hidden windows off screen, slides | `Tiling/WindowManager+Parking.swift` |
| macOS Spaces, move windows between Spaces | `Tiling/WindowManager+Spaces.swift`, `Tiling/NativeSpaceMove.swift`, `Tiling/WindowServerUpdates.swift` |
| Dock click imports | `Tiling/DockWindowPull.swift` |
| Layout math (tall, wide, bsp, …) | `Tiling/Layouts.swift` |
| Window movement animation | `Tiling/Animator.swift` |
| Accessibility API, `Window`, `Screen`, private symbols | `Tiling/AX.swift` |
| Focus dim/blur, drag-anywhere setting | `Tiling/FocusDim.swift`, `Tiling/DragAnywhere.swift` |
| Mode screen-edge effect, layout HUD | `Overlays/ModeFX.swift`, `Overlays/HUD.swift` |
| Global keybinds (CGEventTap) | `Keys/Hotkeys.swift` |
| Keyboard shortcut map (full window) | `Keys/ShortcutMap.swift` |
| Drawn Mac keyboard | `Keys/KeyHintKeyboard.swift` (view), `Keys/MacKeyboard.swift` (model) |
| On-screen keyboard help, trackpad gestures | `Keys/KeyHelp.swift`, `Keys/GesturePad.swift` |
| Config file parse (Hyprland syntax) | `Config/Config.swift` |
| Config editing model, human-readable actions | `Config/ConfigDocument.swift` |
| Saved configs, import/export | `Config/Configs.swift`, `Settings/ConfigsUI.swift` (UI) |
| Settings window, root view, sidebar | `Settings/SettingsWindow.swift`, `Settings/SettingsView.swift` |
| Settings search | `Settings/SettingsSearch.swift` |
| Settings panes | `Settings/GeneralPane.swift`, `LayoutPane.swift`, `WindowsPane.swift`, `MotionPane.swift`, `ShortcutsPane.swift` |
| Menu bar menu, icon, tip | `MenuBar/StatusMenu.swift`, `MenuBar/MenuBarIcon.swift`, `MenuBar/MenuBarTip.swift` |
| Design system: colours, type, motion, controls | `UI/Theme.swift`, `UI/Components.swift`, `UI/AmoreCredit.swift` ("shipped with" credit) |
| Popups, popovers, tooltips | `UI/Popups.swift` |
| Panel entrance animation (Sort, Keyboard Help) | `UI/PanelMotion.swift` |
| Onboarding: intro, welcome card, overlays | `Onboarding/Onboarding.swift`, `Onboarding/OnboardingViews.swift`, `Onboarding/IntroScore.swift` (music), `Onboarding/IntroLab.swift` (dev tool) |
| Tour and tutorial | `Onboarding/Coach.swift` (runner), `Onboarding/Lessons.swift` (scripts), `Onboarding/PracticeDesk.swift` (practice windows) |
| Accessibility permission guide panel | `Onboarding/PermissionGuide.swift` |
| Tips after onboarding | `Onboarding/Tips.swift` |
| Permission checks and requests | `App/Permissions.swift` |
| Sort Windows | `Sort/Sort.swift` (data), `Sort/SortModel.swift` (state), `Sort/SortViews.swift`, `Sort/SortPanel.swift`, `Sort/SortEntry.swift` (nudges), `Sort/WindowManager+Sort.swift` (apply, undo) |
| Bug reports, crash watch | `BugReport/BugReport.swift`, `BugReport/BugReportViews.swift` |
| App start, CLI subcommands | `main.swift` |
| Updates, login item, log | `App/Updater.swift`, `App/LoginItem.swift`, `App/Log.swift` |

Other folders: `design/` (specs and prototypes), `Tools/` (probe scripts), `report-relay/` (Cloudflare Worker for bug reports), `Resources/` (fonts, icon).

## When you finish

1. Run `./build.sh`.
2. Send the user this command in a `bash` code block:

```bash
open build/ouch.app
```

## Pull requests

Make all pull requests with the `pr` skill (`.agents/skills/pr`).
