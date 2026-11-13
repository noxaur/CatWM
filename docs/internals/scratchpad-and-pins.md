# Scratchpads and pinned windows

Each workspace is one macOS Desktop, so a window that "stays" somewhere is a window that CatWM keeps on the right Desktop. Both features come from that fact.

## Scratchpad: park, don't hide

`movetoscratchpad` parks the window in the corner with one write (`cornerPark`, the parking the workspaces used before they were Desktops) and drops it from `present`. A minimised window leaves the layout, the focus order and the switcher the same way, so no other code needs to know. `togglescratchpad` writes the centred frame, moves the window to the shown workspace if it lives on another Desktop, and focuses it.

Rejected:

- **Minimise.** The genie animation takes hundreds of milliseconds, the window lands in the Dock, and AX can't un-minimise it in the same frame it is placed.
- **Hide the app.** It hides every window of the app, and a terminal with a scratchpad window also has normal ones.
- **A Desktop that holds scratchpad windows.** Creating and removing a Desktop is the slowest thing CatWM does, `releaseEmptyWorkspaces` would fight it, and it shows up in Mission Control.
- **Alpha 0 or ordering the window out.** SkyLight lets only the owner of a window change these (`native-space-import.md` lists what other apps' windows refuse).

A hidden window stays on its Desktop, and a switch to that Desktop doesn't show it, because it is parked. `restoreHiddenWindows` already finds parked windows at exit and puts them back, so a quit leaves nothing off-screen. A crash does, as it does for any parked window.

A scratchpad name can hold several windows. `togglescratchpad` hides every shown window of that name on the workspace, and otherwise shows the window hidden last. A shown scratchpad window is a normal floating window that keeps its name. A window that isn't on the shown workspace comes to it through `moveNativeWindow`, the same move as **Bring Window Here**, and the centred frame is written first so it arrives in place.

`scratchpad.size` is a percentage of the display's visible area, 80 by default. A window that can't resize keeps its size, and a window's minimum size wins over the percentage.

## Pin: the window follows the Desktop

macOS has a per-window "all Desktops" tag, but another app's window refuses every SkyLight call that would set it (`SLSAddWindowsToSpaces` and the tag calls leave membership unchanged, see `native-space-import.md`), and CatWM excludes sticky windows from its Desktop bookkeeping. So a pinned window lives on one Desktop at a time, and CatWM moves it:

- **A switch that CatWM starts** (`showNativeWorkspace`) registers a follow move for each pinned window of the target's display. `prepareNativeLayout` runs these moves before the slide, so the window arrives with the new Desktop and never shows a gap. It slides with the new Desktop, not still. macOS has no way to leave one window out of the slide.
- **A switch CatWM didn't start** (a swipe, Mission Control) is caught in `refresh`: the window moves to the shown workspace after the switch. It appears a moment late. `PinnedWindows.claimFollow` stops a refused move from retrying on every refresh.

A pin floats the window and unpinning leaves it floating, because the window may have been floating before. A window is either pinned or in a scratchpad: either command removes the other.

## Scope

A scoped instance turns Desktops off, so there both commands work on one Desktop and move nothing between Desktops. That is why `movetoscratchpad`, `togglescratchpad` and `pin` are in `WindowScope.allowedCommands`.
