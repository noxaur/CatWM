<p align="center">
  <img src="website/public/icon.png" width="96" alt="CatWM app icon">
</p>

<h1 align="center">CatWM</h1>

<p align="center">A simple, modern, and fast tiling window manager for macOS.</p>

<p align="center">
  <a href="https://catwm.perwko.com"><img src="website/public/demo-poster.jpg" width="760" alt="CatWM tiles a Finder window and two terminal windows side by side"></a>
</p>

## Install

```sh
curl -fsSL https://catwm.perwko.com/install.sh | sh -s -- --beta
```

## How to use CatWM

The central concept of CatWM is "Window mode", think of it as Vim's visual mode, the build mode in a game, or the tool keys in a drawing app. You enter it with `⌘ + tab`. This is where you can move windows, displays, change layouts and more.

Here is a overview of what key binds are available within window mode. (This is openable by pressing `?` within window mode)

<p align="center">
  <img src="docs/assets/readme/window-mode-keys.png" width="760" alt="The keys available in window mode">
  <img src="docs/assets/readme/window-mode-keys-shift.png" width="760" alt="The keys available in window mode while shift is held">
</p>
<sub>↑Help wanted with this ui!↑</sub>

### Workspaces

Unlike all the other macOS tilers I've ever seen, CatWM uses native spaces. This works well because CatWM uses SkyLight, the private macOS interface that Mission Control uses. It lets CatWM create and switch Desktops and move windows between them.

<p align="center">
  <img src="docs/assets/readme/workspaces.webp" width="760" alt="Switching macOS Desktops with CatWM workspaces">
</p>

### Layouts

Every workspace has its own layout. Press `p` or `n` in window mode to cycle through them: tall, wide, columns, two pane, binary space partitioning, floating and more.

<p align="center">
  <img src="docs/assets/readme/layouts.webp" width="760" alt="Cycling through layouts in window mode">
</p>

### Save workspaces

Quickly save and open workspaces, including some of the apps state.

<p align="center">
  <img src="docs/assets/readme/templates.webp" width="760" alt="Saving and opening a workspace template">
</p>
<sub>We are currently working on adding adapters to save more app states, in this example you can see that we restore the active tab in helium. And that is the limit with chromium browsers for now.</sub>

### Overview

Reorder your windows without dealing with the native macOS fuss.

<p align="center">
  <img src="docs/assets/readme/overview.webp" width="760" alt="Reordering windows in the overview">
</p>

### Callable via cli

Agents (and humans) can call CatWM via cli. Every bind is a dispatcher, and the cli runs the same ones. Python, TypeScript and Swift libraries (see [Clients](Clients/README.md)) use the same commands and can listen for events.

```sh
catwm workspace 2
catwm movefocus left
catwm windows
catwm events focus.changed
```

## Configure CatWM

CatWM works with no setup. To change it, edit `~/.config/catwm/catwm.config.ts`. CatWM writes a `catwm.d.ts` next to it, so your editor completes every option, key, dispatcher and event. A save applies at once. The Settings window writes into the same file, so the file and Settings always agree.

```ts
import { catwm } from "./catwm"

catwm.gaps = { size: 8 }
catwm.layouts = ["tall", "bsp", "floating"]

// A key runs a dispatcher, or a function.
catwm.bind(["alt"], "h", ["movefocus", "l"])
catwm.bind(["alt"], "c", () => {
  catwm.window.focused.float()
  catwm.window.focused.center()
})

// A rule applies as a window appears. Text fields take a string, a trailing *, or a RegExp.
catwm.windows({ app: "com.apple.calculator" }, (win) => win.float())
catwm.windows({ title: /^Picture-in-Picture$/i }, (win) => win.pin())

// A handler runs after something happens.
catwm.on("display.removed", () => catwm.dispatch("workspace", "1"))
```

[docs/user/configuration.md](docs/user/configuration.md) explains every part: options, keys, window mode, rules, workspace rules, events and splitting the config into files.

### Dispatchers

A dispatcher is a named action. Keys, rules, `catwm.dispatch`, the CLI (`catwm <dispatcher> <args>`) and the libraries all run the same ones. [Resources/AgentDocs/dispatchers.md](Resources/AgentDocs/dispatchers.md) has the full arguments of each.

| Group | Dispatchers |
|---|---|
| Focus | `movefocus` `l r u d` · `cyclenext` `[prev]` · `focuswindow` *target* · `focuslast` · `focusmonitor` *display* · `switcher` `[prev]` |
| Move | `movewindow` / `swapwindow` `l r u d` or `mon:<display>` · `swapnext` `[prev]` · `movewindowtomonitor` *display* · `movetoworkspace` / `movetoworkspacesilent` *workspace* |
| Size and place | `resizeactive` / `moveactive` `exact W H`, `50% 100%` or `+50 -20` · `centerwindow` · `splitratio` `±0.05` or `exact 0.6` · `balance` · `togglesplit` |
| Window state | `togglefloating` · `setfloating` · `settiled` · `fullscreen` · `nativefullscreen` · `minimize` · `unminimize` · `killactive` · `pin` `[on off toggle]` |
| Scratchpads | `movetoscratchpad` `[name]` · `togglescratchpad` `[name]` |
| Tabs | `moveintogroup` `l r u d` · `moveoutofgroup` · `changegroupactive` `f b N` · `movegroupwindow` `f b` |
| Layouts | `layout` *name* · `cyclelayout` `next prev` · `layoutmsg` *message* · `toggletiling` · `retile` · `toggledim` · `toggleblur` |
| Workspaces and displays | `workspace` `N`, `name:foo`, `previous`, `+1`, `e+1` · `moveworkspacetomonitor` *display* · `swapworkspaces` *display display* · `sethomespace` |
| Overview | `sort` · `sort-undo` |
| App | `submap` *mode* or `reset` · `reload` · `exit` · `exec` *command* · `launch` *app, file or URL* · `sendshortcut` *mods key [bundle id]* |

`exec`, `launch` and `sendshortcut` run only from your own keys and config, never over the socket.

**Window targets.** A window dispatcher acts on the focused window. Start its argument with `@` and a target to act on another window: `catwm setfloating "@app:com.apple.Safari"` or `catwm movetoworkspacesilent "@title:/^Inbox/i 3"`. A target is `app:`, `title:`, `workspace:`, `display:`, `id:` or `pid:`, then a value. A value is exact text, ends with `*`, or is a regex in `/source/flags` form. `catwm windows` lists the window IDs.

### Events

`catwm.on(event, handler)` in the config, `catwm events` in a shell, and `events()` in the libraries all get the same events: `focus.changed`, `window.added`, `window.changed`, `window.removed`, `workspace.changed`, `workspace.created`, `workspace.removed`, `display.added`, `display.removed`, `layout.changed`, `tiling.changed`, `mode.changed`, `window.notifications`, `permissions.changed` and `config.reloaded`.

### Plugins

Another app can add its own dispatchers. It registers a namespaced name over the socket, and CatWM sends it each call, with the target window. Your config can bind the name like any built-in:

```python
from catwm import CatWM

with CatWM() as catwm:
    catwm.register("notes.toggle", lambda call: print("toggle", call["window"]))
    catwm.serve()
```

```ts
catwm.bind(["alt"], "n", "notes.toggle")
```

The name goes away when the app disconnects, and a press does nothing until it comes back. A plugin can't replace a built-in dispatcher. See [Clients](Clients/README.md) for Python, TypeScript and Swift.

### For agents

The app ships an agent guide: run `catwm docs` for its folder, or read [Resources/AgentDocs/README.md](Resources/AgentDocs/README.md). It covers the CLI, every option, keys, dispatchers and troubleshooting, so an agent can change a user's config without reading the source.


## Contributing

Thank you for being interested in my project!
Please read [CONTRIBUTING.md](CONTRIBUTING.md).
