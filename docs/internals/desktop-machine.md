# Desktop machine

`DesktopMachine` decides when CatWM may touch macOS Desktops. Before it existed, each caller kept its own flags: a request and a running flag in `NativeDesktopController`, a creation lock, a sweep flag, a switch generation and a 5 s switch-target hold in `WindowManager`. Each caller checked a different subset of them, so a gesture or a maximised-window switch could start a slide while CatWM was creating a Desktop, and a gesture interruption could cancel a switch that a key had started.

## One reducer, one runner

The machine is a pure value type: `send(event)` returns effects, and it has no clock, tasks or system calls. `NativeDesktopController` is its only runner. It turns each effect into a slide task or a resumed waiter, and it feeds completions back as events. Every gate (refresh, scans, the empty-Desktop sweep, gestures, the overview) reads the machine instead of a flag.

A pure reducer is what makes the checks possible. The alternative was an actor or a lock object, which keeps the state together but leaves its behaviour spread over async code that no model checker can enumerate.

## What it holds

- **wanted**: the switch the user asked for most recently. The running slide reads it every frame, so a newer request on the same display retargets the slide instead of queueing behind it.
- **slide**: the slide in progress and, for a swipe, its direction, its progress and whether the fingers are still down. A gesture is tracked only inside a slide that it started, so ending or interrupting a gesture can't touch a switch that a key started. A new swipe ends a gesture whose end event was lost, so a lost event can no longer hold the slide, and with it every refresh, for the 180 s swipe limit. The event tap still decides on its own whether a swipe is CatWM's, because it must answer synchronously at the first event, before the direction is known.
- **held** and **queue**: Desktop jobs, which create or remove a Desktop. One runs at a time, and never during a slide. A job waits its turn in a queue instead of polling with a timeout, so it can no longer give up after 5 s while a removal sweep with retries is still running.

A slide comes before queued jobs, because the user is watching it. A request for a workspace that has no Desktop yet becomes a job that creates the Desktop and then switches to it. While a job holds the lock, a request is resolved by name after that job finishes, because a removal renumbers the workspaces when each display numbers its own.

Each new switch replaces the previous one, whether it is wanted, queued or already creating its Desktop. A replaced creation still finishes, because SkyLight can't stop halfway. It just doesn't switch afterwards, and the sweep removes the Desktop if it stays empty. Callers reserve their job before they await anything, so jobs run in the order the user asked for them, even when the job runs from a later task. The machine names every pending switch target, so the sweep keeps those workspaces. That replaced the 5 s switch-target hold.

## Verification

`Tools/Spec/DesktopMachine.tla` models the reducer with abstract requests and jobs. TLC checks every reachable state against these invariants:

- no slide while a job holds the lock
- idle means nothing is wanted or queued
- a tracked gesture always follows the wanted switch
- at most one switch is pending
- every job is answered once

It also checks, under fairness for completions, that the machine always returns to idle and answers every job. CI runs it with `Tools/check-desktop-spec.sh`.

TLA+ checks the design but not the Swift code, so `DesktopMachineTests` searches every state that the real reducer can reach within a bounded number of inputs, against the same invariants and the effect accounting. Change the reducer, the spec and the test together.

Only the arbitration is verified. The slide's own phases (guard, covers, motion, activation) and Desktop creation run inside effects, and their timeouts bound how long the machine stays busy.
