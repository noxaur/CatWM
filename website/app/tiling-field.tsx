import { type CSSProperties, useEffect, useLayoutEffect, useRef, useState } from "react";

// An abstract Ouch session: windows open, take their slot, follow the focus and close.
// Same layout maths as Ouch's `tall` layout, same key names as the default binds.

const W = 160;
const H = 100;
const PAD = 2.4;
const GAP = 2.4;
const RATIO = 0.5;

type Rect = { x: number; y: number; w: number; h: number };

type Scene = {
  order: string[];
  focus: string;
  fullscreen: boolean;
  mode: boolean;
};

type Step = { label?: string; hold?: number; next: (s: Scene) => Scene };

const START: Scene = { order: ["a"], focus: "a", fullscreen: false, mode: false };
const STILL: Scene = { order: ["a", "b", "c"], focus: "a", fullscreen: false, mode: false };

const STEPS: Step[] = [
  { label: "⌘N", next: (s) => ({ ...s, order: [...s.order, "b"], focus: "b" }) },
  { label: "⌘N", next: (s) => ({ ...s, order: [...s.order, "c"], focus: "c" }) },
  { label: "⌘⇪", hold: 900, next: (s) => ({ ...s, mode: true }) },
  { label: "h", next: (s) => ({ ...s, focus: "a" }) },
  { label: "f", hold: 2200, next: (s) => ({ ...s, fullscreen: true }) },
  { label: "f", next: (s) => ({ ...s, fullscreen: false }) },
  { label: "l", next: (s) => ({ ...s, focus: "b" }) },
  { label: "m", next: (s) => ({ ...s, order: ["b", "a", "c"] }) },
  { label: "esc", hold: 900, next: (s) => ({ ...s, mode: false }) },
  { label: "⌘W", next: (s) => ({ ...s, order: ["a", "c"], focus: "a" }) },
  { label: "⌘W", hold: 2600, next: () => START },
];

// A rounded rect as a path: Chromium gets `pathLength` wrong on a <rect> with corners.
const MODE_LINE = roundedRect(1, 1, W - 2, H - 2, 3.4);

const STEP_MS = 1500;
const FIRST_MS = 900;
const KEY_LEAD_MS = 260;
const KEY_SHOW_MS = 900;

function roundedRect(x: number, y: number, w: number, h: number, r: number): string {
  const a = `a${r} ${r} 0 0 1`;
  return `M${x + r} ${y}h${w - 2 * r}${a} ${r} ${r}v${h - 2 * r}${a} -${r} ${r}h-${w - 2 * r}${a} -${r} -${r}v-${h - 2 * r}${a} ${r} -${r}z`;
}

function rows(r: Rect, n: number): Rect[] {
  const h = r.h / n;
  return Array.from({ length: n }, (_, i) => ({ x: r.x, y: r.y + i * h, w: r.w, h }));
}

function tall(screen: Rect, n: number): Rect[] {
  if (n <= 1) return rows(screen, n);
  const main = { ...screen, w: screen.w * RATIO };
  const rest = { ...screen, x: screen.x + main.w, w: screen.w - main.w };
  return [...rows(main, 1), ...rows(rest, n - 1)];
}

function inset(r: Rect, by: number): Rect {
  return { x: r.x + by, y: r.y + by, w: r.w - 2 * by, h: r.h - 2 * by };
}

function slots(scene: Scene): Map<string, Rect> {
  const screen = { x: PAD, y: PAD, w: W - 2 * PAD, h: H - 2 * PAD };
  const ids = scene.fullscreen ? [scene.focus] : scene.order;
  const frames = tall(screen, ids.length).map((r) => inset(r, GAP / 2));
  return new Map(ids.map((id, i) => [id, frames[i]]));
}

type TileProps = { rect: Rect; shown: boolean; focused: boolean; enter: boolean };

function Tile({ rect, shown, focused, enter }: TileProps) {
  const [ready, setReady] = useState(!enter);
  useLayoutEffect(() => {
    if (ready) return;
    let frame = requestAnimationFrame(() => {
      frame = requestAnimationFrame(() => setReady(true));
    });
    return () => cancelAnimationFrame(frame);
  }, [ready]);

  const visible = ready && shown;
  const r = visible ? rect : inset(rect, Math.min(rect.w, rect.h) * 0.04);
  const style = {
    x: `${r.x}px`,
    y: `${r.y}px`,
    width: `${r.w}px`,
    height: `${r.h}px`,
    opacity: visible ? 1 : 0,
  } as CSSProperties;
  return <rect className="tile" data-focused={focused || undefined} rx={2.6} style={style} />;
}

type Placed = { id: string; key: string; rect: Rect; shown: boolean; enter: boolean };

export function TilingField() {
  const [scene, setScene] = useState<Scene>(START);
  const [label, setLabel] = useState<string | null>(null);
  const [still, setStill] = useState(false);
  const hostRef = useRef<HTMLDivElement>(null);
  // Closed tiles keep their last slot to fade out in place. A reopened tile gets a new
  // generation, so it mounts again and grows into its new slot instead of flying there.
  const placed = useRef(new Map<string, Placed>());

  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setStill(true);
      setScene(STILL);
      return;
    }
    const host = hostRef.current;
    if (!host) return;

    let step = 0;
    let onScreen = true;
    let timers: number[] = [];
    const clear = () => {
      for (const t of timers) window.clearTimeout(t);
      timers = [];
    };
    const run = () => {
      timers = [];
      if (!onScreen || document.hidden) return;
      const { label, hold, next } = STEPS[step];
      if (label) {
        setLabel(label);
        timers.push(window.setTimeout(() => setLabel(null), KEY_SHOW_MS));
      }
      timers.push(window.setTimeout(() => setScene(next), KEY_LEAD_MS));
      timers.push(window.setTimeout(run, hold ?? STEP_MS));
      step = (step + 1) % STEPS.length;
    };
    const resume = () => {
      if (onScreen && !document.hidden && timers.length === 0) {
        timers.push(window.setTimeout(run, STEP_MS));
      }
    };
    const onVisibility = () => (document.hidden ? clear() : resume());
    const io = new IntersectionObserver(([entry]) => {
      onScreen = entry.isIntersecting;
      if (onScreen) resume();
      else clear();
    });

    io.observe(host);
    document.addEventListener("visibilitychange", onVisibility);
    timers.push(window.setTimeout(run, FIRST_MS));
    return () => {
      clear();
      io.disconnect();
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, []);

  const current = slots(scene);
  for (const [id, rect] of current) {
    const was = placed.current.get(id);
    if (was?.shown) {
      placed.current.set(id, { ...was, rect });
    } else {
      const generation = was ? Number(was.key.split("-")[1]) + 1 : 1;
      const enter = was !== undefined || !START.order.includes(id);
      placed.current.set(id, { id, key: `${id}-${generation}`, rect, shown: true, enter });
    }
  }
  for (const [id, tile] of placed.current) {
    if (!current.has(id) && tile.shown) placed.current.set(id, { ...tile, shown: false });
  }
  const tiles = [...placed.current.values()].sort((a, b) =>
    a.id === scene.focus ? 1 : b.id === scene.focus ? -1 : 0,
  );

  return (
    <div
      ref={hostRef}
      className="field relative w-full overflow-hidden rounded-[20px] bg-screen"
      data-mode={scene.mode || undefined}
      data-still={still || undefined}
      aria-hidden="true"
    >
      <svg viewBox={`0 0 ${W} ${H}`} className="block h-full w-full">
        {tiles.map((tile) => (
          <Tile
            key={tile.key}
            rect={tile.rect}
            shown={tile.shown}
            focused={tile.shown && scene.focus === tile.id}
            enter={tile.enter}
          />
        ))}
        <path className="mode-line" d={MODE_LINE} pathLength={1} />
      </svg>
      <div className="keycap" data-shown={label !== null || undefined}>
        {label}
      </div>
    </div>
  );
}
