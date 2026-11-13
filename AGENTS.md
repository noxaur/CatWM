# CatWM

CatWM is a feature-rich but simple macOS tiling window manager.

## What makes CatWM special

We can't compromise on these. They make us what we are today and tomorrow.

- Simple by default: the core works with no setup, and each advanced feature stays out of the way until the user needs it.
- Intuitive: users need to get real work done, not tinker with a tiling manager. CatWM should feel native and obvious.
- Fast and smooth: performance is a core feature, and most apps ignore it. CatWM moves every window, so a slow frame or a hang is a bug. Measure it, and do not trade it for convenience.

## General principles

- Channel your inner DRY, YAGNI, KISS and SOLID.
- Build on the shared layer each area already has, such as theme tokens, components or motion helpers. If it can't do what you need, extend it there.
- Write real fixes, not bypasses.
- Keep code in one function unless a part is reused or composable.
- Before adding complexity for a speculative or vanishingly unlikely race or security edge case, explain the concrete failure mode, likelihood and complexity cost to the user and get their buy-in.
- If a short request has two possible meanings, ask one question before you start.
- Call a bug fixed only when a test, log or recording shows it.

## How it works

CatWM is an engine with no GUI, wrapped by an app that draws. Other Mac apps can embed the same engine. The engine reaches the UI only through one surface interface, so the app, embedded mode and tests each plug in their own. Hotkeys, the CLI and the language libraries all run the same named actions through one command registry. One object owns all state. Accessibility events and window scans trigger one refresh, which reconciles the window list, asks the layout for slots and animates the windows into them through one write queue per app. Each workspace is one native macOS Desktop, and CatWM drives the Desktop slide itself. The config is a TypeScript file that runs on its own JavaScript thread, plus an overrides file that Settings writes. A save re-runs the whole config and applies only the changed fields. Saving and reopening windows has two layers. The lower layer saves and reopens app windows and knows nothing about CatWM, and the template layer adds workspaces, Desktops, layouts and frames on top.

## Docs

- Before you change an area, read its doc in `docs/`. Use the words defined in `docs/internals/vocabulary.md`.
- When a large feature adds or reshapes an area, write or update its doc in `docs/internals/` in the same change. The code shows what it does, so the doc records why: each architectural decision, the alternative you rejected and the constraint that decided it. Leave out how-to steps, code tours, test results and dated verification runs. Recipes belong in a skill.
- Keep docs tight. State each fact once, in the doc that owns it, and delete what has gone stale in the same change that made it stale.

## Checks

- Build: run `./build.sh --dev`. Run `./build.sh` only for a release build. A build stops the running CatWM only with `--replace`. Set `CATWM_INSTANCE=<id>` to build next to it.
- The build writes the schema, the clients and the config docs. Add the changed generated files to your change.
- Lint: `Tools/check-style.sh` and `Tools/swiftlint.sh` must pass. Each failure names its fix.
- Test: run `swift test`. Test the real implementation instead of copying its logic into the test.

## Branches and pull requests

- Use a short branch name of at most three hyphenated words, such as `session-recovery` or `fix-scroll-state`.
- Make a PR only when asked. Before you create one, load the `pr` skill (`.agents/skills/pr/SKILL.md`) and follow it. It is mandatory.

## Code and residue

- Agents read code well, so add comments only where the code can't speak for itself.
- Keep plans, research notes and scratch files outside the worktree.

## Rules and what enforces them

When the operator corrects you, fix the mistake and add its rule here. If the rule is already here and nothing enforces it, enforce it in the same change. Drop a rule once its mistake can't happen.

| Rule | Enforced by |
| --- | --- |
| Style with Theme tokens, motion with Motion tokens and helpers, panels with CatWMPanel | `check-style.sh` |
| Log with `Log`, never `print` or a dropped `try?` | `check-style.sh` |
| No comments, except `// style-ok: <reason>` on a line that breaks a check | `check-style.sh` |
| Post input only through `RealInput`, so tests never touch the user's input or Desktops | `check-style.sh`, `RealInput` traps in tests |
| Tests wait on an event or an injected clock, never on a sleep or a polled run loop | `check-style.sh`, partly. `ContinuousClock().sleep` and `RunLoop.run(mode:before:)` still pass |
| `docs/internals` records why, not steps. `docs/README.md` lists every `docs/user` page | `check-style.sh` |
| Commit the generated config docs | `check-style.sh` digest. The schema and clients: nothing |
| `swift test` passes | nothing in CI |
| Every layout supports what every other layout does, such as mouse resizing | nothing yet |
| Write only what the user stated. No invented user stories, models or examples | judgment |
| One concern per PR, with evidence | the `pr` skill |
