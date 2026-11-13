# Control: the CLI, the socket and the libraries

One registry feeds every way to control CatWM from outside the app. Key binds, the `catwm` CLI, the socket and the language libraries all run the same commands. `WindowActions.all` (`Sources/CatWMKit/Actions/`) is the only list of dispatchers. The registry, `WindowManager.dispatch`, the bind picker, `Clients/schema.json` and the generated clients all read it, so a new dispatcher is one `WindowAction` and a build. Queries and config commands are `Command`s in `Control/`.

`ControlServer` reads on a background queue and runs each command on the main queue, in order. It refuses a socket path longer than `sun_path` (104 bytes) instead of cutting it. A client that falls 1 MB behind is dropped. A command made with `Command.later` waits for something (an app, the window server) and replies from a task on the main actor instead of blocking the queue. When a connection closes, `ControlServer` tells the manager on the main queue after every line it had already read, and `EventBus` and the agent display sessions drop it (`agent-display.md`). `EventBus` diffs a state snapshot against the last one only while someone subscribes, so events cost nothing with no subscriber. A config with `catwm.on` handlers is one such subscriber, and only while it has a handler (`config.md`, "Event handlers").

## Window targets

A window dispatcher acts on the focused window, unless its argument starts with `@field:value`. `WindowTarget` (`Actions/`) is the one parser. It builds a `Condition` over the same facts as a window rule (`ruleFacts`), so a target and a rule match alike, and `id` is one more fact. `WindowManager.dispatch` resolves the target before it runs the action and passes the window as `ActionContext.target`, the way a rule does. So no dispatcher parses a target, and a dispatcher takes one by reading `context.window` instead of `focusedWindow()`. `WindowActions.targetable` lists those that do, and any other dispatcher refuses a target, because it would otherwise act on the focus that the caller meant to avoid. A target that matches nothing does nothing and never falls back to the focused window. Of several matches the focused window wins, then the most recently focused (`WorkspaceModel.focusOrder`), then the lowest ID, so the result is stable.

`focuswindow` takes the target without the `@`, and shows a window's workspace first when it isn't shown. `focuslast` reads the second entry of `focusOrder`, the same history that the focus stamps keep, so there is no second history to drift.

## Plugins

Another app adds its own dispatcher with the `register` command, or in embedded mode with `CatWMEngine.register`. `PluginDispatchers` (`Control/`) owns the names, one table for each `WindowManager`. `WindowManager.dispatch` and the rule actions look a name up there only after `WindowActions` has no match, so binds, `dispatch`, the CLI and rule actions all reach a plugin like a built-in.

- **Fire and forget.** CatWM writes `{"invoke": name, "data": {"arg", "window"}}` to the owning connection and never waits. The main queue moves every window, so a plugin that hangs, crashes or reads slowly must not stall a frame. The cost is that a plugin can't veto or answer a bind. A plugin that wants to change something calls a command back. `window` is the rule's target, or the focused window, as `{id, app, title}` or `null`.
- **Namespaces.** A name needs a dot (`myapp.toggle-notes`), in lowercase `a-z`, `0-9`, `-` and `_`. Built-in dispatchers have no dot, so the dot keeps plugin names apart from future built-ins, and two apps differ by their prefix. Commands such as `config.get` do have a dot, so registration also refuses any built-in dispatcher or command name. A name belongs to one connection. The same connection can register it again, and another connection is refused. This keeps a second process from stealing a bind.
- **Lifetime.** Names exist only while the connection is open: `connectionClosed` removes them. No config or file stores a plugin, so a crashed plugin leaves no stale entry. A bind to an unregistered name is a valid config and does nothing except log one line, because the app may start after CatWM.
- **Config.** `ConfigScript` accepts any namespaced name as an action, because the config runs before any plugin connects. `catwm.d.ts` types it as `PluginAction`.
- **Access.** `register` is public. A plugin name never reaches the `keybindOnly` set, because `dispatch` checks the built-in name first and a plugin can't take one. The commands are allowed in a scoped instance: they act on no window.
- **Embedded.** The engine owns the table, so a handler registered before `start` survives the new manager.

## Access

- `public`: in the CLI, the schema and the libraries.
- `dev`: works over the socket but stays out of the schema.
- `keybindOnly`: refused over the socket (`exec`, `launch`, `sendshortcut`). Any process of the user can connect, so a command that runs code or types into another app must not be public. A scoped instance refuses `sendshortcut` too, because it posts to any app, not just scoped pids.

## Instances

`CATWM_INSTANCE=<id>` starts a separate CatWM with its own config folder, log, support folders and defaults suite. `Instance` (`Sources/CatWMKit/App/Instance.swift`) owns every path, and `Tools/check-style.sh` rejects `UserDefaults.standard`. A bad id stops CatWM with exit code 2 instead of falling back to the default instance, because the default instance quits the user's CatWM.

Each instance writes `catwm.pid`. At start, the default instance stops every other `local.catwm` process except the pids in `instances/*/catwm.pid`, and `build.sh` does the same. A named instance skips everything that would touch the user's setup: the login item, the `catwm` link, the updater, reports, onboarding, tips, What's New and migrations. It keeps the bundle ID and signature, so the app's macOS permissions still apply.

## Window scope

`CATWM_SCOPE=pids:<pid>,…[;display:<UUID>]` limits a named instance to those pids, and to that display if given. A bad or empty value stops CatWM with exit code 2, and so does a named instance with no scope unless you pass `--unscoped`. A bad value must never mean "all windows".

A scoped instance must not change anything outside its scope. `WindowScanner` filters other pids before the manager sees them. Desktops are off, templates refuse to open, and `GlobalInput` starts no event taps, Caps Lock change, pointer moves or focus window. `CATWM_KEYS=on` brings back the key tap. `WindowScope.refusedCommands` blocks commands that reach outside the scope: they change Desktops, move the pointer, show panels over every app, or run commands. Every command must be in `allowedCommands` or `refusedCommands`, and a test fails otherwise. Add a new restriction in `WindowScope.restrict`, `GlobalInput` or those lists, never at the call site. A focus command can still activate the target's app, which can raise that app's other windows.

The user's CatWM must also stay off the scoped windows. A scoped instance writes `scope` (owner pid, then scope) in its folder, and an unscoped instance reads `instances/*/scope` and skips the claimed pids. It re-reads only when the `instances` folder's modification time changes. A write inside `instances/<id>/` doesn't touch that time, so `writeClaim` writes in `instances` and renames into place, and `removeClaim` moves the file back out before deleting it. `ScopeClaims.watch` watches the folder and each owner pid with `DispatchSource`s, so a claim left by a killed owner (even `kill -9`) triggers a scan at once. When a pid becomes claimed, the user's CatWM drops its windows, its observer and its queued writes. One AX write that has already started can still land. The claimed display isn't excluded, so the user's CatWM still tiles its own windows there. An agent display is the exception: `Screen.all()` drops it (`agent-display.md`).

## Libraries

`Tools/generate-clients.py` writes the Python, TypeScript and Swift clients from `Clients/schema.json`. `Clients/python/catwm/testing.py` is hand-written. The wire protocol is in `Resources/AgentDocs/cli.md`.
