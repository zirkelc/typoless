<div align="center">
  <img src="design/logo/typoless-icon.png" width="112" alt="" />
  <h1>Typoless</h1>
  <p><strong>Fixes your typos. Never rewrites your words.</strong></p>
  <p>
    <a href="https://typoless.app">Download</a> ·
    <a href="https://typoless.app/privacy">Privacy</a> ·
    <a href="app/PLAN.md">Design notes</a> ·
    <a href="https://github.com/zirkelc/typoless/issues">Issues</a>
  </p>
</div>

A Mac menu bar app that fixes the typos in whatever you are writing, wherever you
are writing it, and changes nothing else. Double-tap ⌘ in any text field and the
spelling, grammar, punctuation, capitals and spacing are corrected in place. Your
wording, your tone and your formatting stay exactly as you wrote them.

Everything runs on your Mac. There is no account, no server and no telemetry in
the app itself.

**[Download the beta](https://typoless.app)** · macOS 26 or later, Apple silicon.

## What it does, and what it refuses to do

Writing tools have learned to rewrite. Ask for a spell check and you get a new
sentence in a voice that is not quite yours. Typoless does the part you actually
wanted and stops there.

It corrects ten kinds of mistake, each of which you can switch off per language:

| | |
|---|---|
| Typos | `teh meeting` → `the meeting` |
| Grammar | `she go home` → `she goes home` |
| Sentence capitals | `hello there` → `Hello there` |
| Names and places | `i work at google` → `I work at Google` |
| Commas | `well done everyone` → `well done, everyone` |
| Sentence endings | `see you tomorrow` → `see you tomorrow.` |
| Other punctuation | `really?!` → `really?` |
| Apostrophes | `its ready` → `it's ready` |
| Umlauts and accents | `gruesse` → `grüße` |
| Spacing | `hello  world` → `hello world` |

It will not rephrase, reword, translate, shorten, expand or improve the writing,
and that is enforced rather than requested. See [The guardrail](#the-guardrail).

Seven languages: English, German, French, Spanish, Italian, Dutch and European
Portuguese. The language of each line is detected, so a message that mixes two
works.

## How it works

1. **The trigger fires.** A double tap of a modifier, or a shortcut of your own.
   Nothing is read until then: the app does not watch you type.
2. **The field is read** through the macOS Accessibility API. If you have
   selected text, only the selection is corrected. Password fields are never
   read, and terminals and password managers are excluded from the start.
3. **Spans that must not change are masked**: links, email addresses,
   `@handles`, `#channels`, inline code and emoji. Masking them before the model
   sees them is worth real accuracy, not just safety: a link in a sentence made
   one German line uncorrectable in six attempts out of six, and correctable in
   six out of six once it was hidden.
4. **The text is split into chunks** and the language of each is detected.
5. **A model on your Mac rewrites each chunk.** Apple's on-device model, or one
   you download. The model returns only the corrected text: it is never asked
   where the changes are, because a wrong offset corrupts text silently while a
   wrong word does not.
6. **The edits are derived by diffing** the answer against your text, word by
   word.
7. **The guardrail judges every edit** and drops the ones that are not
   corrections.
8. **Each surviving edit is written back as its own range replacement**, so text
   the correction did not touch is never rewritten, and the caret returns to
   where it was. Replacing the whole value would destroy mentions, links and
   formatting in a rich composer.

Steps 6 and 7 are the product. "Do not rephrase" cannot be enforced by asking a
model nicely.

## The guardrail

Every edit is classified before it is applied, and anything that is not one of
the ten rules above is refused. A few examples of what that catches, all of them
things a model really did during development:

- `we should use the exact enums here` returned **entirely in capitals**. Each
  word on its own looked like a capitalisation fix; seen across the whole reply
  it is shouting, and the chunk is dropped.
- A model that **answered the message** instead of correcting it, or translated
  it. The language of the reply is checked against the language that went in.
- `Danke` coming back as `Danke퀎4`. A typo fix stays in the alphabet it started
  in.
- A reply in **Markdown**, where `evals` became `**E**vals`. Markup is not a
  correction, whatever Unicode thinks of the characters.
- `is` → `has`, `at` → `it`, `do` → `so`. A typo rarely lands on the first
  letter, and a word swapped for a different one usually starts differently.
  `sue` → `use` is allowed, because the first two letters merely traded places,
  and `ectual` → `actual` is allowed, because a non-word turning into a real word
  of the same length has no meaning to change.
- Edits **inside a protected span**: a comma dropped into a URL, a lowercased
  `@name`.

If a chunk ends up with more edits refused than accepted, the whole chunk is
dropped: a model that strayed that far is not to be trusted about the rest.

Switching a rule off is not a suggestion either. The rules apply whether or not
anything else is on, and when one change carries two rules at once, the mark at
its edge is judged separately, so turning commas off does not throw away the
umlaut fix beside it.

## Measuring it

None of the above would mean anything without numbers, so the repository carries
a dataset and a harness that scores the app against it.

**The dataset** is 528 cases across the seven languages, in
[`app/Eval/Datasets`](app/Eval/Datasets). 112 of them are negatives: text that is
already correct and must come back untouched, which is the failure mode that
ruins a tool like this. Each case is tagged, and each language's file states its
own policy, because several calls are judgement rather than grammar.

**`./Config/verify-dataset.sh`** asks the opposite question from a model run:
given a *perfect* answer, would the guardrail apply it? A case whose expected
text the guardrail would refuse can never be passed, however good the model is,
and scoring against it silently caps the achievable score. All of them pass,
along with the alternative answers some cases allow, 534 checks in total, and
this runs in CI.

**The eval harness** (`app/Eval`) runs the real pipeline over the datasets
against any of the models, with the guardrail on and off, and reports exact
match, fixes found, changes nobody asked for, and how many already-correct texts
came back untouched. It shares its engine sources with the app by symlink, so it
cannot drift.

```sh
cd app/Eval
swift run -c release typoless-eval --help
swift run -c release typoless-eval -m appleOnDevice -l en -l de -g both
```

The measurements decide the design, not the other way round. A few that changed
the app:

- A **short prompt beats a long one.** Fourteen wordings were scored; the two
  briefest came first and second, and every long rule list did worse at the very
  rule it spelled out most carefully.
- **Naming a rule to the model does not work.** Telling it which rules the user
  switched off was ignored between 91% and 100% of the time and cost up to 12
  points of exact match.
- **Which model is best is a per-language fact.** Apple's on-device model wins
  English, German, French and Dutch; Gemma wins Spanish, Italian and Portuguese
  by 13 to 25 points of exact match. The app shows that on the Languages page.

The full record, including the measurements that failed, is in
[`app/PLAN.md`](app/PLAN.md).

## Privacy

Your text never leaves the Mac. The model runs locally, history is kept in
memory and cleared when you quit, and the local log is off unless you turn it
on. Three things touch a network, and you start all three: an update check, a
model download, and a bug report you submit yourself. The full statement is at
[typoless.app/privacy](https://typoless.app/privacy).

## Repository

| Folder | What it is |
|---|---|
| [`app/`](app) | The macOS app: Xcode project, sources, release and check scripts, and the eval harness. The design notes and every measurement are in [`app/PLAN.md`](app/PLAN.md). |
| [`www/`](www) | [typoless.app](https://typoless.app): a static Astro site with one Cloudflare Worker, which serves the downloads and counts them. |

### The app

Needs Xcode and macOS 26. Every script finds its own paths, so they run from
anywhere, but the examples assume the `app` folder.

```sh
cd app
xcodebuild -project Typoless.xcodeproj -scheme Typoless build
xcodebuild test -project Typoless.xcodeproj -scheme Typoless -destination 'platform=macOS'   # 61 tests, no model needed
./Config/verify-dataset.sh          # every eval case can reach its expected text
./Config/release.sh 0.2.0           # sign, notarize, package, upload to R2, write the appcast
swift Config/make-app-icon.swift    # app icon and the site's logo files, from design/logo
```

A debug build is a separate application: it is called "Typoless (dev)", carries
its own bundle id, and puts a dot on its menu bar icon, so it can run beside a
release build without sharing its settings.

### The website

Needs Node 22 or later and pnpm.

```sh
cd www
pnpm install
pnpm dev        # local server with reload
pnpm build      # static files in dist/
pnpm preview    # the built site, served the way Cloudflare serves it
pnpm run deploy # build and upload; the first time needs `pnpm exec wrangler login`.
                # "pnpm deploy" is pnpm's own command and never runs this script.
pnpm types      # after changing wrangler.jsonc: the Worker's binding types
pnpm run stats  # downloads and update checks; needs a Cloudflare token
```

The site is static apart from `/releases/*` and `/appcast.xml`, which a small
Worker (`worker/index.ts`) serves from the R2 bucket `typoless-releases` and
counts: the app's downloads are too large to be static files.

### Checks on GitHub

`.github/workflows` runs the app's tests, a Release build and the dataset check
on changes under `app/`, and the site's format, lint, type check and build on
changes under `www/`. Neither needs secrets: nothing is signed, released or
deployed there.

## Reporting

Bugs and wrong corrections go to
[issues](https://github.com/zirkelc/typoless/issues). The app opens a prefilled
one from the History window or from its menu, and it asks first, because a
report about a correction carries the text it was made on.

## Licence

[MIT](LICENSE).
