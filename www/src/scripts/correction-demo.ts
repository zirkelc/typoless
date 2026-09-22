import type { SamplePart } from '../data/hero-sample';

/**
 * The correction animation the page's demos share: typing with squiggles, an
 * optional selection, the double tap, the overlay's scan, and a green pulse on
 * each fix. The elements around it (the key badge, a status line) belong to
 * each demo, which follows along through the phase callback.
 *
 * Every wait takes an abort signal, so a demo can be cut short when the
 * visitor picks another one, without a stale round writing into the page.
 */

export type DemoPhase = 'typing' | 'selecting' | 'tapping' | 'correcting' | 'done';

export interface DemoElements {
  /** Positioned; the overlay's marks are placed relative to it. */
  body: HTMLElement;
  /** Holds the text, and is emptied and refilled on every round. */
  text: HTMLElement;
  /** Absolutely positioned over the body, for the scan and the pulses. */
  overlay: HTMLElement;
  /** Pressed twice for the trigger, if the demo shows a key. */
  key?: HTMLElement;
}

export interface DemoOptions {
  sample: Array<SamplePart>;
  /** With `selection`, only the selected parts are scanned and fixed. */
  scope?: 'field' | 'selection';
  signal?: AbortSignal;
  onPhase?: (phase: DemoPhase) => void;
}

export function sleep(milliseconds: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(signal.reason);

    const timer = setTimeout(resolve, milliseconds);
    signal?.addEventListener(
      'abort',
      () => {
        clearTimeout(timer);
        reject(signal.reason);
      },
      { once: true },
    );
  });
}

/** Waits while the tab is in the background, so a loop does not race ahead unseen. */
export async function whenVisible(signal?: AbortSignal) {
  while (document.hidden) {
    await sleep(300, signal);
  }
}

/** Whether the visitor asked for less motion, in which case the demos stay still. */
export const reducesMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/**
 * One rect per visual line of the spans, relative to the body, which is what
 * the app's overlay draws too: a wrapped paragraph gets a band per line rather
 * than one box around everything.
 */
function lineRects(spans: Array<HTMLElement>, body: HTMLElement): Array<DOMRect> {
  const range = document.createRange();
  range.setStartBefore(spans[0]);
  range.setEndAfter(spans.at(-1)!);
  const origin = body.getBoundingClientRect();
  const lines = new Map<number, DOMRect>();

  for (const rect of range.getClientRects()) {
    if (rect.width < 1) continue;

    const key = Math.round(rect.top);
    const known = lines.get(key);
    const left = Math.min(rect.left, known?.left ?? rect.left);
    const right = Math.max(rect.right, known?.right ?? rect.right);

    lines.set(key, new DOMRect(left, rect.top, right - left, rect.height));
  }

  return [...lines.values()].map(
    (rect) => new DOMRect(rect.left - origin.left - 3, rect.top - origin.top, rect.width + 6, rect.height),
  );
}

function place(element: HTMLElement, rect: DOMRect) {
  element.style.left = `${rect.left}px`;
  element.style.top = `${rect.top}px`;
  element.style.width = `${rect.width}px`;
  element.style.height = `${rect.height}px`;
}

/**
 * The finished state, as the markup renders it: every fix applied, and a
 * squiggle only on a mistake the correction left alone.
 */
export function showFinished({ text, overlay }: DemoElements, sample: Array<SamplePart>) {
  overlay.replaceChildren();
  text.replaceChildren(
    ...sample.map((part) => {
      const span = document.createElement('span');
      span.textContent = part.fixed;
      if (part.misspelled && part.typed === part.fixed) span.classList.add('demo-squiggle');
      return span;
    }),
  );
  text.style.opacity = '1';
}

/** Plays one round, from an empty field to the corrected text. */
export async function playCorrection(elements: DemoElements, options: DemoOptions) {
  const { body, text, overlay, key } = elements;
  const { sample, scope = 'field', signal, onPhase } = options;
  const selectsFirst = scope === 'selection';

  const caret = document.createElement('span');
  caret.className = 'demo-caret';

  /** Type the text, one character at a time, mistakes and all. */
  onPhase?.('typing');
  overlay.replaceChildren();
  const spans = sample.map(() => document.createElement('span'));
  text.replaceChildren(...spans, caret);
  text.style.opacity = '1';

  for (const [index, part] of sample.entries()) {
    const span = spans[index];
    span.after(caret);

    for (const character of part.typed) {
      span.textContent += character;
      await sleep(character === ' ' ? 70 : 38 + Math.random() * 45, signal);
    }

    /** The spell checker marks a word once it is finished, as it does on the Mac. */
    if (part.misspelled) span.classList.add('demo-squiggle');
  }

  await sleep(900, signal);

  /** Select the part to fix, left to right, the way a drag would. */
  if (selectsFirst) {
    onPhase?.('selecting');
    caret.remove();

    for (const [index, part] of sample.entries()) {
      if (!part.selected) continue;

      spans[index].classList.add('demo-selected');
      await sleep(55, signal);
    }

    await sleep(700, signal);
  }

  /** Tap ⌘ twice. */
  onPhase?.('tapping');
  await sleep(350, signal);

  for (let tap = 0; tap < 2; tap++) {
    key?.setAttribute('data-pressed', '');
    await sleep(110, signal);
    key?.removeAttribute('data-pressed');
    await sleep(140, signal);
  }

  await sleep(250, signal);
  caret.remove();

  /** Read: the amber band with a highlight crossing the whole block. */
  onPhase?.('correcting');
  const scoped = sample.flatMap((part, index) => (selectsFirst && !part.selected ? [] : [spans[index]]));
  const bands = lineRects(scoped, body).map((rect) => {
    const band = document.createElement('div');
    band.className = 'demo-scan';
    place(band, rect);

    const sweep = document.createElement('div');
    sweep.className = 'demo-sweep';
    band.append(sweep);
    overlay.append(band);

    return { rect, sweep };
  });

  const blockLeft = Math.min(...bands.map(({ rect }) => rect.left));
  const blockWidth = Math.max(...bands.map(({ rect }) => rect.right)) - blockLeft;
  const sweepWidth = Math.max(blockWidth * 0.28, 48);
  const scanDuration = 1400;
  const from = blockLeft - sweepWidth;
  const to = blockLeft + blockWidth;

  /**
   * One phase for the whole block, offset per band, so on wrapped text the
   * highlight reads as a single pass over the passage rather than every line
   * lighting up at once. Animated by the browser rather than frame by frame,
   * so the timing survives a tab that is throttled or in the back.
   */
  for (const { rect, sweep } of bands) {
    sweep.style.width = `${sweepWidth}px`;
    sweep.animate([{ left: `${from - rect.left}px` }, { left: `${to - rect.left}px` }], {
      duration: scanDuration,
      easing: 'linear',
      fill: 'forwards',
    });
  }

  await sleep(scanDuration, signal);

  overlay.replaceChildren();

  /** The app replaces the selection and leaves the caret at its end. */
  if (selectsFirst) {
    for (const span of spans) span.classList.remove('demo-selected');
    scoped.at(-1)?.after(caret);
  }

  /** Fix each mistake in turn, with a green flash on what changed. */
  for (const [index, part] of sample.entries()) {
    if (part.typed === part.fixed) continue;

    const span = spans[index];
    span.textContent = part.fixed;
    span.classList.remove('demo-squiggle');

    if (part.fixed.trim()) {
      const origin = body.getBoundingClientRect();

      for (const rect of span.getClientRects()) {
        const pulse = document.createElement('div');
        pulse.className = 'demo-pulse';
        place(
          pulse,
          new DOMRect(
            rect.left - origin.left - 2,
            rect.top - origin.top - 1,
            rect.width + 4,
            rect.height + 2,
          ),
        );
        overlay.append(pulse);

        /** The app's timing: in over 0.12 s, held 0.24 s, out over 0.32 s. */
        pulse
          .animate(
            [{ opacity: 0 }, { opacity: 1, offset: 0.18 }, { opacity: 1, offset: 0.53 }, { opacity: 0 }],
            {
              duration: 680,
              easing: 'ease-in-out',
            },
          )
          .finished.then(() => pulse.remove());
      }
    }

    await sleep(170, signal);
  }

  caret.remove();
  onPhase?.('done');
}

/** Fades the text out, so the next round can start on an empty field. */
export async function fadeOut({ text }: DemoElements, signal?: AbortSignal) {
  text.style.transition = 'opacity 300ms';
  text.style.opacity = '0';
  await sleep(350, signal);
  text.style.transition = '';
}
