# CatWM website

Landing page for CatWM, one screen: four windows left in a pile, the brand lockup on them, the
install command and an email signup. The keys below (N, Shift H J K L, F, Shift T) run the real
window manager behaviour on the pile: tile it, cycle the layouts, move a window, fill the screen.
Until the visitor presses a key, the page presses them itself.

`app/catwm/layout.ts` is a port of the Swift layout and neighbour code. `app/catwm/script.ts` holds the
state, the dispatcher reducers behind each key and the attract sequence. `app/catwm/Stage.tsx` moves the
windows with GSAP at the animator's real timing (0.18 s, cubic ease-out). Change the Swift code and the
port together.

- React Router 8 (framework mode, SSR)
- Vite+ (`vp`) for dev, build, format, lint, and type checks
- Void for deployment to Cloudflare Workers. Signups go to Void KV under the `signups:` prefix.

## Develop

```sh
vp install
vp dev
```

## Check and build

```sh
vp check
vp build
```

## Deploy

```sh
vp exec void connect --platform cloudflare
vp exec void deploy
```

`public/demo.mp4` is a 1920 px H.264 re-encode of the source demo. Workers static assets must be 25 MiB or smaller per file.
