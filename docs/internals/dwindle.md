# Dwindle layout

`dwindle` is [Hyprland's default layout](https://wiki.hypr.land/Configuring/Dwindle-Layout/): each new window splits the focused window's tile, and each split keeps its own direction and ratio. Every other layout is a pure function of the window count, so dwindle is the only one with state, `ScreenState.dwindle`.

## Leaves follow `order` by position

The tree stores only structure. Its leaves are the workspace's tiled windows in `order`, matched by position, so every dispatcher and overview drag that reorders windows swaps tiles in the tree with no dwindle code. Keying leaves by window id was rejected because every reorder path would need a dwindle branch. `sync` runs before each layout: a window gone from `order` removes its leaf and its sibling takes the parent's place, and a new window splits the leaf before it. The refresh inserts a new window into `order` right after the focused one, so it splits the focused tile. The focused window is `reportedFocus` first, because by the time the refresh sees the new window, the frontmost app is usually that window's app.

## Splits

A split with automatic direction picks one from its rectangle on every layout, like Hyprland without `preserve_split`. `layoutmsg togglesplit` fixes the direction of the focused window's parent split, `layoutmsg swapsplit` flips which side its first child takes, `splitratio` sets that split's ratio, and `resizeactive DX DY` moves the nearest split on each axis. Ratios stay within 0.1 to 0.9. The tree isn't saved: a restart rebuilds it from `order` with automatic directions.

## Minimum sizes

Windows with a learned minimum size (`minSizes`, plus the gap) shape the tree instead of overlapping. An automatic split takes the other direction when its own can't hold both halves' minimums and the other can, and every split moves its divider just enough to give each half its minimum when the room allows. The stored ratio doesn't change, so the layout springs back when the window closes. Dwindle doesn't use the generic `fitMinimums` pass, because that pass only fits tiles that share an edge span, which nested splits rarely do.
