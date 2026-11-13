# Configure CatWM

CatWM works with no setup. You can change it in two places:

- **The Settings window.** Open it from the CatWM menu bar icon → **Settings…**. It covers the common options, keys and motion styles.
- **The config file**, `~/.config/catwm/catwm.config.ts`. It's a TypeScript file that can do everything Settings can, plus rules, functions and loops. CatWM applies it as soon as you save, with no restart or reload command.

Use whichever you like, or both. The rest of this guide is about the config file. [Settings and your file](#settings-and-your-file) explains how the two work together.

CatWM writes `catwm.d.ts` and `tsconfig.json` next to the file. Open the folder in an editor that knows TypeScript, such as VS Code or Zed. The editor then completes every option, key and action, shows each option's default, and underlines a typo before you save.

## A first config

Every config starts by importing `catwm`. You change options by assigning to it:

```ts
import { catwm } from "./catwm"

catwm.layouts = ["tall", "bsp", "fullscreen"]

catwm.gaps = {
  size: 8,
  smart: true,
}

catwm.motion = {
  style: "snappy",
  bounce: 0.6,
}

catwm.bind(["alt"], "return", ["exec", "open -na Terminal"])
```

The first time CatWM runs, it writes a config with every default spelled out. That file is a good place to start: change a value, save, and watch the windows move.

## Setting options

Options come in groups, such as `gaps`, `motion`, `focus` and `workspaces`. You can set a whole group at once, or one field at a time:

```ts
// The whole group as one object:
catwm.focus = {
  followsMouse: true,
  mouseFollowsFocus: false,
}

// One field:
catwm.focus.followsMouse = true
```

Both lines do the same thing. An object changes only the fields you list. Every other field keeps its value, so `catwm.gaps = { size: 4 }` changes the gap size and leaves smart gaps as they were. This works at any depth:

```ts
catwm.features = {
  input: { gestures: false },
  windows: { tabGroups: false },
}
```

Assigning `undefined` puts the default back, so `catwm.motion = undefined` resets all of motion.

Everything else is ordinary TypeScript. You can read an option (`catwm.gaps.size + 2`), push to a list, use variables, loops and functions, and the last write to a field wins. Your editor shows every option with its description and default.

## Motion

`catwm.motion.style` picks one of the tiles in Settings → Motion: `"none"`, `"snappy"` or `"relaxed"`. A style sets the duration, curve and bounce together. A field you list after the style overrides just that field:

```ts
catwm.motion = {
  style: "relaxed",
  curve: "spring",     // keeps the relaxed duration, but springs
  panels: "pop",       // how Overview and keyboard help appear
  modeEffect: "none",  // nothing at the screen edges in window mode
}
```

## Keys

A key is a `catwm.bind(mods, key, action)` call:

```ts
catwm.bind(["alt"], "o", "sort")
catwm.bind(["alt", "shift"], "tab", ["switcher", "prev"])
catwm.bind(["alt"], "l", ["splitratio", "+0.05"], { repeat: true })
```

The modifiers are `"cmd"`, `"alt"`, `"ctrl"` and `"shift"`. An action is a name, or a name and its arguments in a list. `{ repeat: true }` runs the action again while you hold the key. Your editor completes the key names and the actions.

The config is ordinary TypeScript, so a loop saves you from writing ten nearly identical lines:

```ts
const mod = "alt"

for (const n of [1, 2, 3, 4, 5, 6, 7, 8, 9]) {
  catwm.bind([mod], String(n), ["workspace", String(n)])
  catwm.bind([mod, "shift"], String(n), ["movetoworkspace", String(n)])
}
```

A key can also run a function. The function acts on the window that had focus when you pressed the key:

```ts
catwm.bind(["alt"], "c", () => {
  catwm.window.focused.float()
  catwm.window.focused.center()
})
```

### Window mode

Window mode is a separate set of keys that don't need modifiers. In the default config, ⌘ Caps Lock turns it on. Put a key in the mode with `{ submap: "window" }`:

```ts
catwm.bind(["cmd"], "capslock", ["submap", "window"])
catwm.bind([], "h", ["movefocus", "l"], { submap: "window" })
catwm.bind([], "escape", ["submap", "reset"], { submap: "window" })
```

Always give the mode a key that leaves it, like Escape above. Otherwise you can't get out of it with the keyboard. A click anywhere also leaves the mode.

## Rules for apps and windows

`catwm.windows(match, win => …)` changes windows that match. It runs when a matching window opens, and when a window's title changes so that it starts to match:

```ts
catwm.windows({ app: "com.apple.calculator" }, (win) => {
  win.float()
  win.position = "center"
})

catwm.windows({ title: /Picture in Picture/ }, (win) => {
  win.float()
  win.size = { width: 480, height: 270 }
})
```

You can match on `app` (a bundle ID, and wildcards like `com.adobe.*` work), `title` (text or a regular expression), `workspace`, `display`, `floating`, `minimized` and `fullscreen`. A rule applies once each time a window starts to match, so it won't pull a window back after you move it yourself. When two rules match the same window, the one lower in the file wins.

## Rules for workspaces

`catwm.workspaces(match, () => …)` changes options on the workspaces that match. For example, this drops the gaps when a workspace has only one window:

```ts
catwm.workspaces({ windows: 1 }, () => {
  catwm.gaps = { size: 0 }
  catwm.padding = 0
})
```

You can match on `windows` and `sameApp` (a number, or `{ atLeast, atMost }`), `app`, `layout`, `name`, `display` and `focused`. A workspace rule can set gaps, padding, layouts, `newWindowsToMain`, motion and focus dimming. `catwm.d.ts` marks these options as scoped. CatWM shows an error for anything else, or for a `catwm.bind` inside a workspace rule.

## Reacting to events

`catwm.on(event, handler)` runs a function each time something happens, such as a new window or a display that you unplug. The handler gets the event's data. `catwm.dispatch(action, ...args)` runs an action, like a key does, and acts on the event's window when the event has one:

```ts
catwm.on("window.added", (e) => {
  if (e.app === "com.apple.Notes") catwm.dispatch("movetoworkspacesilent", "3")
})

catwm.on("display.removed", () => {
  catwm.dispatch("workspace", "1")
})
```

The events are `focus.changed`, `window.added`, `window.changed`, `window.removed`, `workspace.created`, `workspace.removed`, `workspace.changed`, `display.added`, `display.removed`, `layout.changed`, `tiling.changed`, `mode.changed`, `permissions.changed` and `config.reloaded`. `catwm.d.ts` lists the data of each. They are the same events that `catwm subscribe` sends.

A handler runs after the event, so a window has already appeared when `window.added` fires. To decide where a window goes or whether it floats, use a rule from [Rules for apps and windows](#rules-for-apps-and-windows): a rule applies as the window arrives. If a handler changes what its own event reports, such as floating a window on `window.changed`, make sure that it settles, or it will run again.

Inside a handler or a key function, `catwm.state` shows what CatWM knows at that moment, read-only: `focused`, `windows` (`id`, `app`, `title`, `floating`, `workspace`), `workspaces` (`name`, `label`, `shown`) and `displays` (`id`, `name`, `workspace`, `layout`).

CatWM looks at events only while your config has a handler, so a config without `catwm.on` costs nothing.

## Splitting the config into files

A long config reads better in parts. Import other files with a relative path, and each file can set options itself:

```ts
// catwm.config.ts
import { catwm } from "./catwm"
import "./keys"
import "./rules"

catwm.gaps = { size: 8 }
```

```ts
// keys.ts
import { catwm } from "./catwm"

catwm.bind(["alt"], "o", "sort")
```

CatWM watches every file you import, so saving any of them applies the change.

## When a save goes wrong

If a save has an error, CatWM keeps running with the last config that worked. The menu bar menu shows the error with its file and line, for example:

```
catwm.config.ts:12: `gaps.sise` is not a CatWM option (gaps has enabled, size, smart)
```

Fix the line and save again, and the error goes away. A config that never finishes, such as an endless loop, is stopped after about a second and counts as an error too.

Options must be set while the config loads. Writing an option from a timer or a promise doesn't work, and CatWM reports it as an error.

## Settings and your file

The Settings window never edits `catwm.config.ts`. A change in Settings goes to `catwm.overrides.json` in the same folder and applies on top of your file. So if you change the gap size in Settings, your file's value no longer applies until you remove that override. Settings → General lists each override, and **Use File Value** removes it.

The order is: CatWM's defaults, then your config file, then the Settings overrides.

