# typoless.app

The landing page for Typoless. A static [Astro](https://astro.build) site: every
page is rendered at build time, and Cloudflare serves the files from `dist/` as
static assets, with no server code.

| Command        | What it does                                                          |
| -------------- | --------------------------------------------------------------------- |
| `pnpm dev`     | Local server with reload at `localhost:4321`                          |
| `pnpm build`   | Static files in `dist/`                                               |
| `pnpm check`   | Type-check the pages                                                  |
| `pnpm preview` | Builds, then serves the result with Wrangler, the way Cloudflare will |
| `pnpm deploy`  | Builds and uploads to Cloudflare                                      |

The first deploy needs `pnpm exec wrangler login`. The custom domain in
`wrangler.jsonc` needs `typoless.app` to be a zone in the same Cloudflare
account.

The logo comes from `design/logo/typoless-icon.svg` in the repository, which
the app icon is made from too. `public/favicon.svg`, `src/assets/logo.svg`,
`public/favicon.png` and `public/apple-touch-icon.png` are written from it by
`swift app/Config/make-app-icon.swift`; run that after changing the logo rather
than editing the copies.
