# Dispatchers

Used as `bind = MODS, key, <dispatcher>, <args>` or `catwm dispatch <dispatcher> <args>`.

| Dispatcher | Args | Effect |
|---|---|---|
| `movefocus` | `l r u d` | focus the neighbouring window |
| `movewindow` / `swapwindow` | `l r u d`, or `mon:l`, `mon:+1`, `mon:0` | move/swap a window in a direction, or to another display |
| `movewindowtomonitor` | monitor spec | move the window to a display |
| `cyclenext` / `swapnext` | none or `prev` | cycle focus / swap with the next window |
| `layoutmsg` | `swapwithmaster`, `swapsides`, `focusmaster`, `addmaster`, `removemaster`, `cyclenext`, `cycleprev`, `swapnext`, `swapprev`, `mfact ±0.05`, `orientationnext`, `orientationprev` | layout-specific actions (main pane) |
| `splitratio` | `+0.05`, `-0.05`, `exact 0.6` | resize the main split |
| `balance` | | give every tiled window the same area, as far as the layout allows (sets the main split to `main windows / windows`; two-pane layouts split 50/50). Layouts with no uneven split, such as Column, do nothing |
| `togglesplit` | | flip the split direction: Tall and Wide swap, and so do Column and Row. Other layouts do nothing |
| `togglefloating` | | float/tile the focused window |
| `setfloating` / `settiled` | | float or tile the focused window and keep the choice |
| `resizeactive` | `exact W H`, `50% 100%`, `+50 -20`, `+5% 0` | resize the focused window: points, a percentage of its display's visible area, or a change. A floating window keeps its top-left corner. A tiled window moves the split it borders, so it takes only a change along the layout's split axis (`+10% 0` on Tall grows the main pane by 10%) and ignores the rest |
| `moveactive` | `exact X Y`, `10% 0%`, `+50 -20` | move the focused floating window: its top-left corner in points or a percentage from the top-left of its display's visible area, or a change. Kept on that display. A tiled window is ignored |
| `centerwindow` | | center the focused floating window on its display's visible area. A tiled window is ignored |
| `fullscreen` | | zoom the focused window |
| `nativefullscreen` | | macOS Full Screen (the green button) for the focused window: it gets a Space of its own and leaves the tiling until it comes back |
| `moveintogroup` | `l r u d` | add the focused window to the tabs of the window in that direction. The tabs share one tile, with a tab bar above it. You can also drag a window by its title bar onto the top of another window |
| `moveoutofgroup` | | take the focused window out of its tabs and give it its own tile. You can also drag its tab down out of the tab bar |
| `changegroupactive` | `f` / `b`, or a tab number from 1 | show the next or previous tab, or tab N |
| `movegroupwindow` | `f` / `b` | move the focused tab one place right or left in its tab bar |
| `killactive` | | close the focused window |
| `exec` | shell command | run via `sh -c`. Keybinds only; refused from the CLI |
| `launch` | app name, bundle ID, `.app` path, file path or URL, then optional `workspace=N`, `display=SPEC` (same as `focusmonitor`), `frame=x,y,w,h` (fractions or `%` of the display) | open an app, file or URL (deep links such as `vscode://…` work). With options, CatWM moves the new window to that workspace or display. `frame` floats it at that part of the display. Keybinds only; refused from the CLI |
| `unminimize` | | bring back the minimized window of the current workspace that was used last |
| `moveworkspacetomonitor` | monitor spec | move every window of the current workspace to the workspace another display shows. A Desktop stays with its display |
| `swapworkspaces` | two monitor specs, e.g. `0 1` or `left right` | swap what two displays show, resolved from the focused display |
| `sendshortcut` | `<mods> <key> [bundle id]`, e.g. `cmd+shift t` | press a key in the focused window's app, or in the app with that bundle ID, without CatWM or the system seeing it. Keybinds only; refused from the CLI |
| `focusmonitor` | `l r u d`, `+1`, `-1`, index | focus another display |
| `workspace` | `N`, `name:foo`, `previous`, `+1`, `-1`, `e+1`, `e-1` | switch workspace (`e±1`: next one that has windows) |
| `movetoworkspace` | same as `workspace` | move the window and follow it |
| `movetoworkspacesilent` | same | move without following |
| `cyclelayout` | `next` / `prev` | step through the `layouts` list |
| `layout` / `setlayout` | a layout name, e.g. `bsp` | set the layout of the focused display |
| `toggletiling` | | pause/resume tiling |
| `toggledim` | | dim other windows on/off until the setting changes |
| `toggleblur` | | blur other windows on/off until the setting changes |
| `retile` / `reevaluate` | | recompute and reapply frames |
| `reload` | | re-read the config |
| `submap` | mode name, or `reset` | enter or leave a keybind mode |
| `switcher` | none or `prev` | window switcher: tap for the last window, hold the modifier to browse every window on every workspace (macOS Desktop) and full-screen Space, type to search. In the list: Tab / Shift+Tab move, Return opens, Esc cancels, `` ` `` shows one app, Cmd+W closes, Cmd+Q quits, Cmd+H hides, Cmd+1…9 opens a row |
| `sethomespace` | | no effect: each macOS Desktop is a workspace. Old configs can keep it |
| `exit` | | quit CatWM (parked windows are restored first) |

In a key bind, unknown dispatchers and bad args are ignored silently; check the log with `catwm dump` or `--verbose`. Over the socket, `catwm dispatch` refuses an unknown dispatcher.
With `virtual-workspaces = false`, `workspace`/`movetoworkspace` use macOS Spaces and need "Switch to Desktop N" enabled on Ctrl+N in System Settings → Keyboard → Shortcuts → Mission Control.
