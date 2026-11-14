# Dwindle layout

`dwindle` is [Hyprland's default layout](https://wiki.hypr.land/Configuring/Dwindle-Layout/): each new window splits the focused window's tile, and each split keeps its own direction and ratio. Every other layout is a pure function of the window count, so dwindle is the only one with state, the trees in `ScreenState.dwindles`.

`ScreenState` keeps a tree per display uuid. With shared Spaces one workspace shows on every display, and each display tiles its own windows. A single tree would be synced to each display's windows in turn on every refresh, which wipes its ratios and split choices. A display with no tree for the workspace takes over the tree of a display that isn't showing it, and trees of displays that are gone are dropped first. So a workspace keeps its tree when it moves to another display with separate Spaces. Keying by display only while Spaces are shared was rejected, because shared Spaces turn on and off as a second display connects, and the live tree would be left under the old key.

## Leaves follow `order` by position

The tree stores only structure. Its leaves are the workspace's tiled windows in `order`, matched by position, so every dispatcher and overview drag that reorders windows swaps tiles in the tree with no dwindle code. Keying leaves by window id was rejected because every reorder path would need a dwindle branch. `sync` runs before each layout: a window gone from `order` removes its leaf and its sibling takes the parent's place, and a new window splits the leaf before it. When the focused window is tiled, the refresh inserts a new window on its workspace and display into `order` right after it, so the new window splits the focused tile. Other new windows go to the end, as in every other layout. A floating focused window has no tile to split. The focused window is `reportedFocus` first, because by the time the refresh sees the new window, the frontmost app is usually that window's app.

## Splits

A split with automatic direction picks one from its rectangle on every layout, like Hyprland without `preserve_split`. `layoutmsg togglesplit` fixes the direction of the focused window's parent split, `layoutmsg swapsplit` flips which side its first child takes, `splitratio` sets that split's ratio, and `resizeactive DX DY` moves the nearest split on each axis. Ratios stay within 0.1 to 0.9. The tree isn't saved: a restart rebuilds it from `order` with automatic directions.

## Minimum sizes

Windows with a learned minimum size (`minSizes`, plus the gap) shape the tree instead of overlapping. An automatic split takes the other direction when its own can't hold both halves' minimums and the other can, and every split moves its divider just enough to give each half its minimum when the room allows. The stored ratio doesn't change, so the layout springs back when the window closes. `sync` stores the minimums with the windows, so `togglesplit`, `resizeactive` and the mouse all walk the directions the layout shows. `togglesplit` refuses a direction that can't hold both halves' minimums instead of overlapping them. Dwindle doesn't use the generic `fitMinimums` pass, because that pass only fits tiles that share an edge span, which nested splits rarely do.

## Mouse resize and the split handle

A tiled window's edge drag maps to the split that edge belongs to, not to one layout ratio. On release, `applyMouseResize` compares the window's frame with its slot. Each edge that moved more than a point moves the deepest split on that axis where the tile sits on that edge's side. A tile's right edge belongs to the nearest split where it's the left half, and its left edge to the nearest one where it's the right half. So dragging an inner tile's left edge moves an ancestor split, and every tile on both sides follows. Using `resize(at:by:)` here was rejected, because it always picks the nearest split on the axis, which is the wrong one for half the edges.

A drag starts from the ratio the split shows, not the one it stores, and stops at the bounds that the 0.1 to 0.9 limits and both halves' minimums allow. If a drag started from the stored ratio, a split held off its ratio by a minimum would ignore the first part of a drag back. Each placement computes that shown ratio and those bounds in one place, so the layout, the edge lookup and the drag can't disagree.

The split handle is the root split's divider, which is what bsp's handle moves too. Dragging it sets the root ratio within the same bounds, and the handle's swap flips the root split's sides. A handle on every split was rejected, because `SplitHandle` draws one divider per screen, and many handles over nested tiles would crowd the screen. Edge drags already reach the inner splits.

The mouse-up path reads the primary button through `WindowBackend.primaryButtonDown()`, like `pointerLocation()`, so FakeBackend tests don't depend on the real mouse.
