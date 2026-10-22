import { useFetcher } from "react-router";

import { addSignup } from "../signup.server";
import { TilingField } from "../tiling-field";
import type { Route } from "./+types/home";

const SITE = "https://ouch.perwko.com";

export function meta() {
  const description = "Ouch for macOS. Public release soon.";
  return [
    { title: "Ouch" },
    { name: "description", content: description },
    { name: "theme-color", content: "#0a74ff" },

    { property: "og:type", content: "video.other" },
    { property: "og:site_name", content: "Ouch" },
    { property: "og:title", content: "Ouch" },
    { property: "og:description", content: description },
    { property: "og:url", content: SITE },
    { property: "og:image", content: `${SITE}/og.png` },
    { property: "og:image:type", content: "image/png" },
    { property: "og:image:width", content: "1200" },
    { property: "og:image:height", content: "630" },
    { property: "og:image:alt", content: "Ouch app icon next to a demo of Ouch on macOS." },
    { property: "og:video", content: `${SITE}/og.mp4` },
    { property: "og:video:secure_url", content: `${SITE}/og.mp4` },
    { property: "og:video:type", content: "video/mp4" },
    { property: "og:video:width", content: "1200" },
    { property: "og:video:height", content: "630" },

    { name: "twitter:card", content: "summary_large_image" },
    { name: "twitter:title", content: "Ouch" },
    { name: "twitter:description", content: description },
    { name: "twitter:image", content: `${SITE}/og.png` },
  ];
}

export async function action({ request }: Route.ActionArgs) {
  const form = await request.formData();
  return addSignup(form.get("email"));
}

export default function Home() {
  const fetcher = useFetcher<typeof action>();
  const busy = fetcher.state !== "idle";
  const done = fetcher.data?.ok === true;
  const error = fetcher.data?.ok === false ? fetcher.data.error : null;

  return (
    <div className="flex min-h-svh flex-col px-4 sm:px-8">
      <header className="py-5">
        <a href="/" className="inline-flex items-center gap-3">
          <img src="/icon.svg" alt="" width={40} height={40} className="size-10" />
          <span className="font-display text-xl">ouch</span>
        </a>
      </header>

      <main className="mx-auto flex w-full max-w-5xl flex-1 flex-col items-center justify-center gap-10 pb-16 sm:gap-12">
        <div className="hero-frame">
          <TilingField />
        </div>

        <div className="flex w-full flex-col items-center gap-7 text-center">
          <div className="flex flex-col items-center gap-3">
            <h1 className="text-4xl tracking-tight text-balance sm:text-5xl">
              Public release soon.
            </h1>
            <p className="max-w-[34ch] text-lg text-balance text-muted">
              A keyboard-driven tiling window manager for macOS.
            </p>
          </div>

          {done ? (
            <p className="text-muted">Thanks. We will email you at release.</p>
          ) : (
            <fetcher.Form method="post" className="flex w-full max-w-sm flex-col gap-2">
              <div className="flex rounded-full bg-field p-1 ring-1 ring-line transition-shadow focus-within:ring-2 focus-within:ring-accent">
                <input
                  type="email"
                  name="email"
                  required
                  autoComplete="email"
                  placeholder="you@example.com"
                  aria-label="Email"
                  className="min-w-0 flex-1 bg-transparent px-4 outline-none placeholder:text-muted"
                />
                <button
                  type="submit"
                  disabled={busy}
                  className="rounded-full bg-accent px-5 py-2 font-medium whitespace-nowrap text-white transition-opacity outline-none hover:opacity-90 focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2 focus-visible:ring-offset-field disabled:opacity-60"
                >
                  {busy ? "Sending…" : "Notify me"}
                </button>
              </div>
              {error && <p className="text-sm text-red-400">{error}</p>}
            </fetcher.Form>
          )}
        </div>
      </main>
    </div>
  );
}
