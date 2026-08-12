# Spellbee

macOS menu bar app that fixes grammar, spelling, punctuation and casing in any text field,
triggered by a global shortcut. Corrects only. Never rephrases, never rewrites.

Bundle ID: `dev.zirkelc.spellbee`
App Group (reserved): `group.dev.zirkelc.spellbee`

## Scope decisions

| Question | Decision |
|---|---|
| Languages | English + German |
| Hardware | Apple Silicon only |
| Trigger | Double-⌘ **and** a conventional configurable hotkey, both shipped |
| Scope when nothing selected | Whole field |
| Distribution | Developer ID, notarized, direct download. The Mac App Store is not achievable; see below |
| Spellchecker pre-pass | Skipped. The target is non-obvious issues (missing commas, casing), which `NSSpellChecker` does not catch anyway |

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| Language / UI | Swift 6 (strict concurrency) + SwiftUI views inside AppKit windows, `NSStatusItem`, `LSUIElement=1` | Needs AXUIElement, global event monitoring, borderless overlay windows, low latency, small RSS. A cross-platform shell would need a native helper for all of it anyway. |
| LLM | **Foundation Models** (`@Generable` guided generation, streaming) | On-device, no model download, Apple manages lifecycle and memory, covers en + de, free, sandbox-safe, no entitlement. |
| Corrector abstraction | `Corrector` protocol | Two backends, chosen in the menu. The pipeline is indifferent to which is behind it. |
| Second backend | MLX via `ml-explore/mlx-swift-lm` (`MLXLLM`, `MLXLMCommon`, `MLXHuggingFace`) | Downloadable models for comparison against Apple's. Needs `huggingface/swift-huggingface` and `huggingface/swift-transformers` added separately: `MLXHuggingFace` is macro-only and expands into code the consumer must supply the hub client and tokenizer for. |
| Text I/O | Accessibility API (`AXUIElement`), clipboard-paste fallback | AX gives selection ranges, minimal in-place edits and preserves rich text. Paste is the universal fallback. |
| Double-⌘ trigger | `NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .leftMouseDown])` | Passive observation. Double-⌘ never needs to be consumed, so no `CGEventTap`: no Input Monitoring grant, no MAS review risk, no `kCGEventTapDisabledByTimeout` class of bugs. |
| Conventional hotkey | Carbon `RegisterEventHotKey` directly | Needs no permission, and consumes the keystroke, which passive monitoring cannot. No dependency yet; `sindresorhus/KeyboardShortcuts` wraps the same call and is worth adopting when settings need a recorder UI. |
| Language detection | `NLLanguageRecognizer`, constrained to `{en, de}` | Free, instant, on-device. Runs per paragraph because en/de code-switching within one field is expected. |
| Launch at login | `SMAppService` | Sandbox-safe. |
| Updates | Sparkle | No store to handle updates for us. |

## Core pipeline

1. Trigger fires. Capture frontmost app and `kAXFocusedUIElement`.
2. Read `kAXSelectedText`. If empty, read `kAXValue` (whole field). Record `kAXSelectedTextRange` and caret offset.
3. Bail-outs: secure text field, `IsSecureEventInputEnabled()`, denied app, empty text, over the length cap.
4. Detect language per paragraph. Mask spans that must never change: URLs, emails, `@mentions`, `#channels`, inline code, fenced code blocks, emoji.
5. Split on paragraph boundaries to fit the model context. Correct each chunk independently with a short language header.
6. Model returns **only the corrected text**. The edits are derived here by comparing it against the original, never reported by the model.
7. **Guardrail pass.** Reject any change that is not spacing, punctuation, capitalisation or an in-place spelling fix; that touches a protected span; or that would leave a chunk with more changes refused than accepted, in which case the whole chunk is dropped.
8. Apply surviving edits **back-to-front**, by selection replacement where the app honours it, then whole value, then paste. Every write is confirmed by reading the value back.
9. Restore caret to the original offset adjusted by the net delta.

Steps 6-7 are the product. The "don't rephrase" constraint cannot be enforced by prompting alone; the
deterministic guardrail is what enforces it. Step 8 is equally non-negotiable: replacing a whole
Electron composer with a plain string destroys mentions, links and formatting.

## Permissions

Two gates, neither grantable programmatically.

1. **Accessibility** (`AXIsProcessTrustedWithOptions`) — read/write text in other apps, observe modifier keys.
2. **Apple Intelligence enabled** — not TCC. Check `SystemLanguageModel.default.availability`; hard gate in v1.

An app that has never called `AXIsProcessTrustedWithOptions` with the prompt
option does not appear in the accessibility list in System Settings at all, so
the user goes looking for a row that does not exist. The setup window therefore
prompts once as soon as it appears, rather than waiting for a button press.

Onboarding window: one checklist, each row is title + one-line why + live status dot + **Grant** button
deep-linking to `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
Poll status every second so rows flip to green without a restart. Final step is a live text field inside
our own window that runs the full pipeline, so the user verifies before touching Slack. Re-shown
automatically if a permission is later revoked.

## Menu bar

Icon states: idle / working (animated) / paused / needs-attention.
Menu: **Fix Now**, **Revert Last Fix**, Pause for 1h, Language ▸ (Auto / English / German),
recent fixes as before→after, Settings…, Setup Guide, Quit.

## Settings

- **General** — launch at login, double-⌘ on/off, conventional hotkey recorder, revert shortcut, show icon.
- **Languages** — English / German toggles, auto-detect on/off.
- **Corrections** — per-kind toggles (spelling, punctuation, capitalization, whitespace), strictness slider mapping to guardrail thresholds, preserve-list (emoji, markdown, code, mentions, URLs).
- **Apps** — deny-list. Default-denied: terminals, Xcode, VS Code, password managers.
- **Privacy** — "nothing leaves your Mac", opt-in local log.

## Overlay animation

Borderless, non-activating, click-through `NSWindow` at `.screenSaver` level over the target field.
Because there is no pre-pass, every invocation pays a full model round-trip (~1-3s), so this is
load-bearing feedback, not decoration.

Three tiers, chosen per correction, best answer first:

1. Per visual line. `kAXLineForIndexParameterizedAttribute` and
   `kAXRangeForLineParameterizedAttribute` give the range of each line, clipped
   to what is being corrected and trimmed of its line break (a rect drawn over a
   line break stretches to the far edge of the field). Each line range is then
   passed to `kAXBoundsForRangeParameterizedAttribute`. Capped at 40 lines,
   since every line costs a round trip to the other app.
2. One rect for the whole range, where the per-line attributes are missing.
3. The element's own frame.

Tiers 1 and 2 are used only when every rect they produce sits inside the field's
own frame. Text scrolled out of view reports rects outside the field or clamped
to its edge, and an animation drawn there points at nothing. If the field's frame
is unknown there is no way to tell a good trace from a bad one, so tier 3 wins by
default. **Falling back to the whole field is the correct outcome, not a
degraded one.**

Measured: `com.t3tools.t3code` (Electron) implements neither the per-line
attributes nor `AXBoundsForRange`, so it always lands on tier 3. Native
`NSTextView` apps (TextEdit, Notes, Mail, Messages) implement all three.

The sweep runs on a single phase spanning the whole block rather than per line,
so wrapped text reads as one pass over the passage instead of several lines
blinking independently.

The overlay hides as soon as the user activates another app. It is drawn at a
fixed place over a specific field, and because the panel floats above everything
and joins every space, leaving it up means an amber bar sitting over unrelated
windows until the correction finishes.

The same switch also **abandons the correction**, and that part is a safety
matter rather than tidiness. Pasting is aimed at whichever app is frontmost, not
at a particular element, so a correction that finishes after the user has moved
on would select all and paste into whatever they switched to, over whatever they
had selected there. The target records the owning process and the write is
skipped unless that app is still frontmost. Slow backends widen this window from
a fraction of a second to several, so it is not a rare case.

## Risks

1. **Rich text.** Whole-field plain-string replacement destroys mentions, links, emoji. Mitigated by step 8.
2. **Whole-field scope + no pre-pass.** A stray double-⌘ in a long composer rewrites everything the user typed. Revert Last Fix is the safety net and must not slip past M3.
3. **Double-⌘ false positives** during ⌘-Tab, plus ~250-300ms of forced latency before we know it was not a triple tap. Require no other key or mouse event between taps. The conventional hotkey is the escape hatch.
4. **Secure input** blocks event monitoring system-wide. Detect and surface in the menu bar rather than appearing broken.
5. **Context window.** Foundation Models shares ~4k tokens between input and output (verify at M2). Long emails overflow. Handled by paragraph chunking plus a hard length cap with a visible notice. `SystemLanguageModel.tokenCount(for:)` would measure this exactly but requires macOS 26.4, above our 26.0 deployment target and above the current dev machine (26.3.1), so chunking must estimate from character counts. Revisit if the floor moves.
6. **Model refusals.** Foundation Models occasionally refuses ordinary text. The guardrail turns that into a no-op rather than a mangled message. Log the rate. `SystemLanguageModel(guardrails: .permissiveContentTransformations)` exists and is the right fit for a correct-don't-generate workload; try it first at M2 before assuming refusals are unavoidable.
7. **Getting the user through the accessibility grant.** The system prompt cannot be relied on: it is the system's decision whether to show anything, and in testing it showed nothing. The setup window must therefore work for a user who has to add the app by hand with the **+** button in System Settings, which means naming that button, saying where the app lives, and detecting the grant the moment it lands. Treat the prompt as a bonus, not the path.
8. **TCC identity.** Permissions key off signing identity + bundle ID. Stable bundle ID and a Developer ID cert from day one, or dev builds re-prompt endlessly.

## Why not the Mac App Store

The store was a goal until it was measured. It is not achievable, and the reason
is structural rather than a matter of getting the entitlements right.

The store requires the App Sandbox. A sandboxed app cannot use the accessibility
APIs this app is built on: no permission prompt is ever shown, the app cannot be
added by hand in System Settings, and the trust check always returns false.
Apple's forums carry the same finding from other developers, with no supported
workaround ([810677](https://developer.apple.com/forums/thread/810677),
[805780](https://developer.apple.com/forums/thread/805780)).

Magnet, Divvy and BetterSnapTool are not counter-evidence. They predate the
mandatory sandbox requirement and are grandfathered; the accessibility usage is
absent from their current binaries.

Measured locally across sandboxed and unsandboxed builds, with and without
`get-task-allow`, and with the trust check made both first and last in the
process. `tccd` answers identically every time:

```
ReqResult(Auth Right: Unknown (None), promptType: 1, DB Action:None, UpdateVerifierData)
Service kTCCServiceAccessibility does not allow prompting; returning Unknown
```

`DB Action: None` means no record is created, which is why the app never shows
up in the accessibility list at all.

So: one build, unsandboxed, hardened runtime, Developer ID, notarized, Sparkle
for updates. The same way Raycast, Alfred, Karabiner and Cotypist ship.

## Milestones

| # | Milestone |
|---|---|
| M0 | ✅ Skeleton, menu bar, dual scheme, permissions onboarding, overlay window shell |
| M1 | ✅ Double-⌘ global monitor + conventional hotkey, AX read/write, revert |
| M2 | ✅ Foundation Models correction, en/de, chunking, guardrail |
| M3 | ◐ Revert done early, in M1. **Minimal edit application still outstanding** |
| M4 | ◐ Three tiers, per-line tracing, sweep and cancel-on-focus-change all done ahead of schedule. Missing: pulse on changed ranges, cancel on Escape |
| M5 | Settings, languages, deny-list. Nothing built; there is no settings window at all |
| M6 | Developer ID signing, notarization, Sparkle. Blocked on a Developer ID certificate, which does not exist yet |

The one piece of M3 that matters is unbuilt. Edits are computed minimally and
applied minimally *to the string*, and then the whole field or selection is
written back in a single operation. In a field holding mentions, links or
formatting that flattens everything, which is the risk the whole design was
shaped around. Writing each surviving edit as its own range replacement,
back to front, is what closes it.

M0-M3 is a usable app. M4-M5 are polish and reach.

### M2 notes

**The model is never asked where its changes are.** The plan originally had it
return typed edits with ranges. It returns only the corrected sentence, and the
two versions are compared here. Small models are poor at character offsets, and
a wrong offset corrupts text silently instead of failing; comparing strings is
exact and free. It also means the guardrail never has to trust the model's own
account of what it did.

The comparison works on runs of whitespace and non-whitespace, so a change lands
on the word it belongs to. An insertion is absorbed into an adjacent change when
only spacing separates them, because a correction can split one word into two
("tim,i" to "Tim, I") and judging the halves separately accepts one and refuses
the other, silently deleting a word. Only insertions are absorbed: joining two
substantive changes because a space sits between them chains unrelated
corrections into one oversized change that is then refused as a whole.

A change is allowed when it is only spacing, only punctuation, only
capitalisation, or a spelling fix that keeps every word in place. Spelling
additionally requires the first letter to match, without which "is" to "has"
reads as a one-character fix and quietly changes the sentence.

**A chunk that had more changes refused than accepted is dropped entirely.**
Keeping the survivors of a rewrite is worse than doing nothing: dropping all but
one word of a translated sentence leaves two languages mixed together. Language
detection on the result is a second guard for the same failure, since a fluent
translation changes every word legitimately as far as spelling is concerned.

URLs, emails, handles, hashtags, code spans and emoji shortcodes are found in the
original and used to veto changes overlapping them. They are not hidden from the
model: text with holes in it reads as broken and makes its other corrections
worse.

Guardrails are set to `permissiveContentTransformations`, sampling is `.greedy`,
and a fresh session is used per chunk so the context never accumulates.

**The model is instructed in the language of the text.** Told in English to
correct German, it fixes the obvious misspellings and then leaves sentence
capitalisation, missing umlauts and missing commas alone. The same request
written in German, naming the rules that language actually has, recovers all
three. Measured on the same samples, changing only the instructions:

| Input | English instructions | German instructions |
|---|---|---|
| `das ist ein schoener tag` | `Das ist ein schoener Tag` | `Das ist ein schöner Tag` |
| `ich glaube das wir das schaffen wenn alle da sind` | unchanged | `Ich glaube, dass wir das schaffen, wenn alle da sind` |

The instruction wording is tuned by measurement, not taste. Small edits move
behaviour more than they appear to, so re-check on real text after changing it.

`permissiveContentTransformations` reduces refusals but does not end them: the
model still turns down ordinary text, consistently for a given wording, so
retrying the identical request is pointless. A declined chunk is retried once
with the English instructions, which answers often enough to be worth the second
round trip. A chunk that is declined twice is left as the user wrote it.

`./Config/verify-guardrail.sh` checks all of the above without a model or a
running app. It should become a real test target.

### Comparing backends

**Menu ▸ Correction Model** switches between Apple's on-device model and a
downloaded one. Both get the same instructions and both are judged by the same
guardrail, so the only variable is the weights.

| | Apple on-device | Downloaded |
|---|---|---|
| Size | already present | 1.6-4.8 GB |
| Guided generation | yes, via `@Generable` | no, so the reply needs unwrapping |
| Refusals | occasional, on ordinary text | none seen |
| Per-chunk latency | 0.43-0.65s | 0.58-0.78s (Gemma 4 E4B) |

Measured over five English and German samples, same instructions and same
guardrail on both:

- **Gemma 4 E4B** produced the better result on four of five. Its margin comes
  from finishing sentences with punctuation, catching `your` → `you're`, and
  capitalising a sentence-initial `Wir`. It lost the one case where its proposal
  was refused as a rewrite.
- **Qwen3.5 2B** produced the better result on one of five and left two samples
  untouched. It is also a vision-language model, which may not help it here.
- **Apple's** is the most conservative of the three and the only one that
  restored `koenntest` → `könntest`.

Latency is close enough that speed is not the deciding factor, which was not the
expectation going in.

None of the three appeared to restore an umlaut mid-word (`buero` → `Büro`,
`pruefen` → `prüfen`). That was not the models: all of them proposed the
correction and the guardrail threw it away, because `buero` → `Büro` costs three
edits once the capital, the umlaut and the dropped `e` are counted separately,
against a threshold of two. `koenntest` → `könntest` costs exactly two, which is
why that one alone ever survived. Umlaut expansion is lossless, so the guardrail
now folds both sides and compares, settling the question exactly rather than by
distance.

Worth generalising from: a weakness that appears in every backend at once is
more likely to live in the code they share than in any of them.

Five samples is thin evidence, and most of Gemma's margin is one systematic
habit rather than better judgement. Worth re-running on real text before
treating it as settled.

Nothing is fetched when a model is selected. The weights arrive on the first
correction after that, which is when the user has actually asked for the thing
that needs them. Switching away unloads them, since they are the largest thing
this app ever holds.

Without guided generation the reply arrives wrapped: a `<think>` block, a "Here
is the corrected text:" preamble, or quotation marks. Each would read as an
enormous edit and be refused, so they are stripped before comparison. Qwen models
are asked to skip the reasoning block, which for a task this small is most of the
generation time.

Two build notes. `mlx-swift` ships a build plugin, so a command-line build needs
`-skipPackagePluginValidation -skipMacroValidation`; Xcode asks once and
remembers. And the dependency is large: expect the first build to take minutes.

### M1 notes

Default conventional shortcut is ⌥⌘Space. Plain ⌥Space is the obvious choice
but launchers commonly hold it, and losing the registration is silent.

Revert arrived here rather than at M3. Whole-field scope means an accidental
trigger replaces everything the user typed, and the safety net should not be the
last thing added.

Writing back is a three-tier fallback, and every tier confirms itself by reading
the value back. A successful `AXError` means the app accepted the message, not
that it acted on it, so trusting the return code makes the app claim corrections
it never made:

1. Replace the selection. Rich text, links and mentions survive, and the edit
   lands in the host app's undo stack.
2. Set the whole value. Flattens formatting.
3. Paste. Puts the text on the clipboard and presses ⌘V, then puts the clipboard
   back.

Tier 3 exists because Electron and other Chromium-based apps report both
`AXSelectedText` and `AXValue` as settable and then ignore every write. Measured
in `com.t3tools.t3code`: `selectedTextSettable=true valueSettable=true`, both
writes accepted, neither changed anything. Those apps do handle paste, because
it arrives as a real keystroke rather than an accessibility message.

Which tier an app needs is worth caching per bundle ID rather than rediscovering
on every correction, since tiers 1 and 2 each cost a confirmation timeout before
failing. Not done yet.

`kAXSecureTextFieldSubrole` is a C macro that does not reach Swift, and it is a
subrole rather than a role. Password fields are detected by comparing
`kAXSubroleAttribute` against the literal `"AXSecureTextField"`.

The menu bar item is an `NSStatusItem` built directly on AppKit, not a SwiftUI
`MenuBarExtra`. The SwiftUI version drew and updated its icon correctly but its
menu would not open, and the icon it draws cannot be animated, which the
progress indicator needs. The setup window is an AppKit window for the same
reason: opening it from the menu is then a direct call rather than a round trip
through an environment action that only exists inside a view hierarchy.

Not yet true: writing back still replaces the whole selected range in one go, so
the rich-text risk stands until M3 lands minimal edits. Safe to try in plain
text fields, not in a composer holding mentions or links.

### M0 notes

One scheme, `Spellbee`, with `Debug` and `Release`. The project briefly carried a
sandboxed pair alongside an unsandboxed one, on the assumption that the store was
reachable; measuring that assumption removed the reason for the split.

The Xcode project uses a synchronized folder group, so new files under `Spellbee/`
are picked up without touching `project.pbxproj`.

`kAXTrustedCheckOptionPrompt` is imported into Swift as a mutable global that
Swift 6 will not let concurrent code read. `@preconcurrency import
ApplicationServices` makes it reachable via `takeUnretainedValue()`.

The trust check with the prompt option runs as the process's first accessibility
call, in `PermissionsModel.init`. It bought nothing observable in testing, but the
offer is tied to a process's first request, so spending that request on a plain
`AXIsProcessTrusted()` can only lose.

`Config/make-app-icon.swift` generates the placeholder icon. It draws into an
explicitly sized `NSBitmapImageRep`: rendering through `NSImage.lockFocus` picks
up the display's backing scale and silently produces everything at 2x, which
`actool` rejects by dropping `CFBundleIconName` from the built `Info.plist`
while still reporting a successful build.

Verified: the scheme builds clean; the built app is unsandboxed and keeps bundle
ID `dev.zirkelc.spellbee`; `CFBundleIconName` is present; a first launch presents
the setup window; a later launch stays silent in the menu bar.

## Deferred out of v1

| Item | Why deferred | Revisit when |
|---|---|---|
| ~~**MLX Swift backend**~~ | No longer deferred. Built once Apple's model proved uneven on German, so the two can be compared directly. See below. | — |
| **Intel Mac support** | Explicitly out of scope. Foundation Models requires Apple Silicon regardless. | Never, unless the MLX backend lands. |
| **`NSSpellChecker` pre-pass** | Would not catch the non-obvious issues this app targets. Its only value was skipping the model on clean text. | If per-invocation latency proves intolerable and a cheap "is anything wrong at all" gate is worth the false negatives. |
| **`CGEventTap`-based trigger** | Passive `NSEvent` monitoring covers double-⌘ without consuming events, so the tap's Input Monitoring grant and MAS review risk buy nothing. | Only if a trigger that must swallow its keystroke is ever wanted. |
| **Languages beyond en/de** | Scope. | After v1 ships; cheap for any language Apple Intelligence already supports. |
| **Selection-only / paragraph-only scope modes** | Whole field chosen for v1. Selection-first still works when the user selects text. | If whole-field proves too blunt on long fields in real use. |
| **Licensing / paywall scaffolding** | Monetization undecided. | Before any public release. |
| **Mac App Store** | Not achievable: the sandbox it requires makes the accessibility APIs unusable. Not a deferral so much as a closed door. | Only if Apple ships a sandbox-compatible way to read and write text in other apps. |
| **Per-app correction profiles** | Deny-list covers the v1 need. | If per-app tone or strictness turns out to matter. |

## Open questions

- Monetization: free, paid, or personal tool. Blocks nothing until M6.
- A Developer ID certificate does not exist yet; only an Apple Development one.
  Needed for notarization at M6, for nothing before it.
