# Animation

All animation code lives in `Sources/CatWMKit/Motion/` (window, Desktop and curve engine) and `Sources/CatWM/Motion/` (SwiftUI and layer helpers), and nothing else may start an animation. `Tools/check-style.sh` enforces this, and a `// style-ok` escape on such a line is itself an error. `App/Perf/FrameRun.swift` may use a display link because it measures frames, and the mode cursor and the Sort drag may run fast timers. The user's animation settings reach every kind of motion through one value, `MotionSpec`, so a setting change moves windows, Desktops and panels alike.

## Window frames

CatWM animates real windows by writing AX frames, so the app's resize and redraw latency still shows in the motion. A display link can pace the writes, but it can't remove that cost. A compositor such as [Hyprland](https://github.com/hyprwm/Hyprland/blob/main/src/render/pass/SurfacePassElement.cpp) fits the client's current buffer to the animated geometry instead. macOS gives a window manager no such hook.

`Animator` steps on an `NSScreen` display link for the fastest display that holds an active destination. Each app writer samples at the link's `targetTimestamp`, or at its estimated write-completion time when it has fallen behind. Pending writes coalesce, so a slow app skips obsolete frames instead of replaying them. The estimate learns only from successful writes: samples are capped at 50 ms, it follows rising costs at 80% weight and falling costs at 40%, and it expires after one second idle. These are tuning heuristics. A successful AX write doesn't prove the app has drawn fresh pixels.

## Landing

A window that `Animator` writes stays busy for `MotionTiming.quietAfterWrite` after its last write, so the AX echo of CatWM's own move doesn't read as a user move. An app that ignores a write sends no event, so `LandingCheck` reads each landed window back after `MotionTiming.landingCheckDelay` and writes the target once more. A window that stays larger teaches the layout its minimum size, and one whose top edge stays lower teaches it the menu bar. One epoch per window says whether a landing callback or a check is still current, and a cancel bumps it.

Focus writes don't belong to motion, so `FocusWriter` in `Tiling/Focus` owns them. They run on a queue per app apart from the frame writer's, so focus never waits behind a slow app's frame writes.

## One motion per screen

A refresh animates each screen's moves with the motion of that screen's workspace (a workspace rule can change it), so `applyTileMoves` hands the animator one batch per screen, and `maxAnimatedMoves` counts per batch. Moves that must not animate go first in a batch of their own and land at once.

## Lab: resize animation

`lab.resizeAnimation` picks `live` (the default) or `color-fill`, which tries to hide the app's redraw latency. A third mode, `snapshot`, scaled captured windows in a panel. It was removed because capture added tens of milliseconds before every resize and had to fall back to live motion whenever another window overlapped. A config that still names it gets the default, so an old setting can't block a config load.

**`color-fill`** keeps the real window live and paints sampled edge colors over the gap between its native frame and the animated outline. Appearances are prepared on a background queue while windows are idle. A cache miss uses normal AX motion, so capture never delays the start of an animation. Shrinking goes through predicted intermediate native sizes, slightly ahead of the outline. Growing keeps native frames inside the viewport, because a fill can cover a gap but can't crop excess content. Within a tick, writes that release space go first, and position and size go in whichever order keeps the intermediate rectangle closest to the source and target union. Without that, a right-aligned tile briefly extends off its display.

The fill samples narrow side bands, a bottom row and the border and alpha outline, and takes the most common color per band to reduce streaks from text. Bottom growth stretches the longest flat color run, which is a guess at which region grows, such as a sidebar. There's no app whitelist. It supports opaque rectangular and rounded windows with a fixed top edge on one display. True transparency would need a different method. `Tools/window-fill-probe.sh` checks the pixels (seams, borders, corners, everything outside the target), not the latency.

## Motion quality

A successful AX write doesn't show when the app draws, so `MotionRun` measures the window-server frame instead. The app reads it with `SLSGetScreenRectForWindow` on main. At each display-link callback it compares that frame with the trajectory at the callback's `timestamp`, the vsync on screen now. The `targetTimestamp` would be wrong here. The writes from this callback can't show yet, so it would charge every app a frame, even one that draws at once. The first callback of a run still shows an error, because the trajectory starts at `animate` and the first write lands a frame or so later. That's real: the motion skips the start of its curve.

`MotionQuality` keeps four numbers per window and tick. Error, spill and gap are the largest edge distance in points, not an area, because the eye catches the one edge that's off. Spill is how far the native window reaches outside the desired frame, and gap is how far it falls short. They stay apart because a fill can hide a gap but nothing hides a spill, and gap counts only while no fill shows. Lag inverts the trajectory along its fastest edge. Dividing the error by the speed would be simpler, but the curve isn't linear, and the fastest edge gives the finest time step. An edge slower than 100 px/s gives no lag sample, because a point there spans 10 ms or more. The meter runs only in verbose mode or when a caller sets `measures`. Each tick it reads one frame per moving window and searches about 100 trajectory times.

`MotionBench` (`Tests/Fakes`) runs the real `Animator` and `AXWriter` on a virtual clock. Each writer queue is held between frames, so coalescing is real and every run gives the same numbers. The fake applies an AX write at once, and the window-server frame shows it after the app's latency. Position and size have their own latency, because some apps move a window long before they redraw it at a new size. Panels and captures need a screen, so the bench's color fill is a stand-in that engages on the real guards (`canFill`, `WindowResizeFill.fits` and `needed`). Its tick cost leaves out the SkyLight reads, which are most of the color-fill tick on a real screen.

## Trajectory inherits velocity

Restarting a curve from rest when a target changes mid-flight makes the item stop and start again. `Trajectory(…, velocity:)` uses inertialization instead. It adds `carry * u * (1 - u)^2`, where `carry = velocity * duration - (to - from) * slope0` and `u` is normalized time. The term is 0 at both ends, so the motion still starts at `from` and lands on `to`. Its slope is `carry` at the start and 0 at the end, so the speed starts at the carried velocity and the curve's own landing is untouched.

`DesktopMotion` uses this for reversals. It remembers its last value, time and speed, builds the new trajectory from there and shortens the spec in proportion to the remaining distance. A swipe feeds `follow(until:update:)`, so the slide that follows starts at the finger's speed.
