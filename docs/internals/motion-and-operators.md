# Motions and operators

A directional bind has two parts, as in Vim. The key is the motion (`h j k l` name a direction), and the modifier is the operator (none focuses, `Shift` moves). `Tiling/Navigation/Motion/` turns a direction into a target and changes no state. `Operator/` acts on a target and never searches for a neighbor.

## One resolver

`moveFocus` and `moveWindow` used to find their own neighbors, and they drifted apart: focus wrapped at the layout edge and move didn't. Now `WindowManager.resolve` is the only place with motion rules, so a new operator needs no direction logic and a rule change applies to every operator.

CatWM copies Vim's split between motion and operator, not its key sequence (`d` then `w`). The modifier is held with the key, so `Hotkeys.match` stays a stateless table lookup. A pending-operator state would add counts, timeouts and a stuck-state risk to the event tap that sees every key press.

## Resolver rules

`resolve` stops at the first match:

1. **CatWM fullscreen.** A fullscreen window has no spatial neighbor, so the resolver cycles through the tiled windows on its screen.
2. **Own screen.** The nearest window in that direction on the window's own screen. Windows that overlap on the other axis rank first, then the most recently focused.
3. **Adjacent display.** The display that starts at or past the edge and overlaps on the other axis. The nearest window there wins, and an empty display is the target itself.
4. **Any screen.** The nearest window in that direction on any screen, for a layout with no adjacent display.
5. **Wrap.** The far end of the row or column. A stack cycles.

Wrap comes last so that a window at the bottom of the upper monitor can reach the monitor below instead of wrapping in place.

The adjacent-display rule doesn't use `screen(from:spec:in:)`. That compares only screen centers, so a side monitor at a different height counted as "below" and broke vertical wrap on a laptop with an external display. The new rule needs the monitor to start at or past the edge and to overlap on the other axis. `focusmonitor`, `movewindowtomonitor` and the window context menu still use the center comparison, because they take a monitor spec (a direction, an offset or an index) and no window motion.

Move uses `swapOrder`, so at an edge the moved window and the far window swap places instead of rotating.

## Focus echo after a swap

Some apps make themselves frontmost when CatWM moves their window. tldraw did this about 10 ms after a swap. CatWM read it as a user switch, dropped the pending focus, and the next press moved the wrong window. After a swap with another app's window, `move` stores a `FocusEcho` for 0.4 s. If that app activates within the window, CatWM focuses the moved window again and skips normal activation handling.
