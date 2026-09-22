# Typoless

A Mac menu bar app that corrects spelling, punctuation, capitals and spacing in
any text field, on the Mac, without rewriting anything. This repository holds
the app and its website.

| Folder | What it is |
|---|---|
| [`app/`](app) | The macOS app: Xcode project, sources, release and check scripts, and the eval harness. The design notes are in [`app/PLAN.md`](app/PLAN.md). |
| [`www/`](www) | The landing page at [typoless.app](https://typoless.app): a static Astro site, served by Cloudflare. |

## App

Needs Xcode and macOS 26. Every script finds its own paths, so they run from
anywhere, but the examples assume the `app` folder.

```sh
cd app
xcodebuild -project Typoless.xcodeproj -scheme Typoless build
xcodebuild test -project Typoless.xcodeproj -scheme Typoless -destination 'platform=macOS'   # correction rules, no model needed
./Config/verify-dataset.sh     # every eval case can reach its expected text
./Config/release.sh 0.2.0      # sign, notarize, package and write the appcast
swift Config/make-app-icon.swift   # app icon and the site's logo files, from design/logo
```

## Website

Needs Node 22 or later and pnpm.

```sh
cd www
pnpm install
pnpm dev        # local server with reload
pnpm build      # static files in dist/
pnpm preview    # the built site, served the way Cloudflare serves it
pnpm deploy     # build and upload; the first time needs `pnpm exec wrangler login`
```
