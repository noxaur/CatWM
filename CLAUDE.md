# Ouch: agent guide

Ouch is a macOS tiling window manager (Swift, SwiftPM, one target `ouch`). All code is in `Sources/ouch/`.

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

## When you finish

1. Run `./build.sh`.
2. Send the user this command in a `bash` code block:

```bash
open build/ouch.app
```

## Pull requests

Make all pull requests with the `pr` skill (`.agents/skills/pr`).
