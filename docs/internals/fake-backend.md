# Fake backend

`WindowBackend` (`Tiling/Access/WindowBackend.swift`) is the boundary between the tiling engine and macOS. `AXBackend.shared` sends each call to AX, the window server and `NSWorkspace`. `FakeBackend` (`Tests/Fakes/FakeBackend.swift`) runs the real engine on in-memory windows and screens, so tests need no permissions, GUI or real apps. Change the fake, run the engine and examine the result. Don't copy engine logic into a test.

Fake pids are negative, so no AX call can reach a real app. `fake.makeManager()` uses the default config text with animation, gaps, warps and Desktops off. `Config.load()` would read and can write the user's config.

Tests wait on the engine, never on time. A full `swift test` runs about 950 tests at once on one main thread, often next to other builds, so a `@MainActor` test can wait seconds for its turn, and any wall-clock bound in a test eventually expires early. `Tools/check-style.sh` rejects sleeps, fixed run-loop waits, timed gates and `Task.yield` polls against a deadline in tests.

`settle` repeats scan, refresh and AX writes until a round writes nothing, and it returns `false` after 8 rounds. Its 60 s limit, like the one on `wait(_:until:)`, only guards against a scan that never finishes, since no event reports one. A 10 s limit ran out in a 100 s suite run at load 59. No event reports the animator's own timers: the placement check 0.12 s after a landing, and the 0.4 s hold after a write when reconciliation ignores the window's frame. `makeManager()` runs both on the backend's `FakeClock`, and `settle` steps it past each one before it calls a round final. A real 0.4 s hold was rejected: the last refresh could start inside it and `settle` could check after it, so `settle` passed with `displayOf` still naming the old display, and the next display move snapped back as if the user had dragged it. `wait(_:until:)` re-checks on each `onChange` for steps that an event ends.

A test that blocks a writer, scanner or capture uses `Gate` (`Tests/CatWMTests/Gate.swift`), which stays shut until the test opens it. A semaphore with a short timeout was rejected because it opens itself under load, and the test then checks a state it never set up. A gate with no limit was rejected too, because a regression that never opens it hangs the whole run without an issue. So a wait gives up after 120 s, far past the longest stall measured at load 59, and records an `Issue`. `check-style` refuses a `style-ok` on a test sleep, timed gate or deadline poll, except in `AgentDisplayLiveTests`, which samples a real window server.

## Input and Desktops go through the backend

Switching a Desktop posts a real Ctrl+arrow keystroke, and moving a window to one presses and drags it with the real pointer. An engine on a fake once did both to the user's own screen: `CatWMPerf engine-actions` ran `workspace 2` and the keystrokes switched the user's Desktops. `WindowBackend` therefore also owns every read and write of the pointer, the keyboard and the Desktop list: `pointerLocation`, `warpPointer`, `post`, `postMouse`, `serverFrame`, `spaceList` and the two system shortcuts. `FakeBackend` keeps a pointer, a Desktop count and a current Desktop, records each call in `inputs`, plays a step as a Desktop switch and carries a held window with it, so a test checks the recorded switch instead of the screen.

The alternative was an `isFake` check at each call site. It was rejected because the next call site would miss it, which is how the first leak happened. `RealInput` is the second layer for a path that skips the backend. It guards the lowest posting functions (`Hotkeys.post`, `DesktopSwipe.post`, the Desktop bridge, `Spaces.move`, `AXBackend`'s pointer calls). `FakeBackend.init` blocks it for the process, and so does any process that loads XCTest unless a `CATWM_TEST_*` flag is 1. A blocked call does nothing, counts in `RealInput.refusals` and traps in a debug build. The cursor refresh passes `traps: false`: it re-posts the pointer where it already is, and tests that build a manager on `AXBackend.shared` reach it. A backend that leaves the seam out gets defaults that read nothing and trap on a post.

## Limits

These parts aren't behind `WindowBackend`, so a fake test can't drive them:

- Native Desktop machinery (`NativeDesktopController`, `Spaces.move`, the Desktop bridge). Use `virtualWorkspaces = false`. It still posts nothing in a blocked process, but it does nothing.
- AX observers. `AXObserverCreate` fails for a negative pid, so send a notification with `manager.handle(_:_:)`.
- The focus sink window, which `parkFocus` shows when focus moves to an empty display or workspace.
- Some direct window-server reads, such as `CGWindowInfo.onScreen()` in `focus(on:)` and the Overview.
- Template capture and restore.

On an Apple M4 debug build, 200 windows on 20 apps settle in about 0.07 s, and a relayout of them takes about 2 ms of main thread. `twoHundredWindowsRetileInLessThan50Milliseconds` holds the relayout call to 50 ms of main-thread CPU time, because at load 90 wall time also counts the time the thread waits to be scheduled. CPU time alone would pass a main thread that blocks on a lock, a `sync` or the window server, so wall time gets its own 1 s bound.
