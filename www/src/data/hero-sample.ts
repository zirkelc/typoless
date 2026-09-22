/**
 * The sentence the hero shows being corrected, split where the correction
 * changes it.
 *
 * Each part is either left alone or fixed, so a visual can mark exactly what
 * moved and show that everything else stayed. `misspelled` marks the parts a
 * spell checker would underline while typing: words, not spaces or commas.
 */
export interface SamplePart {
  typed: string;
  fixed: string;
  misspelled?: boolean;
  /** Inside the text the user selected, for a sample that corrects only the selection. */
  selected?: boolean;
}

export const heroSample: Array<SamplePart> = [
  { typed: 'i', fixed: 'I', misspelled: true },
  { typed: '  ', fixed: ' ' },
  { typed: 'think ', fixed: 'think ' },
  { typed: 'teh', fixed: 'the', misspelled: true },
  { typed: ' demo is ready', fixed: ' demo is ready' },
  { typed: ' ,', fixed: ',' },
  { typed: ' can we ship it ', fixed: ' can we ship it ' },
  { typed: 'thursday', fixed: 'Thursday', misspelled: true },
  { typed: '', fixed: '?' },
];

/**
 * A second sentence, where only the second half is selected.
 *
 * The mistake before the selection keeps its squiggle after the correction,
 * which is the point of the sample: a selection limits the fix to exactly what
 * was selected.
 */
export const selectionSample: Array<SamplePart> = [
  { typed: 'teh', fixed: 'teh', misspelled: true },
  { typed: ' slides are done. ', fixed: ' slides are done. ' },
  { typed: 'can', fixed: 'Can', selected: true },
  { typed: ' you ', fixed: ' you ', selected: true },
  { typed: 'chek', fixed: 'check', misspelled: true, selected: true },
  { typed: ' them by ', fixed: ' them by ', selected: true },
  { typed: 'friday', fixed: 'Friday', misspelled: true, selected: true },
  { typed: '?', fixed: '?', selected: true },
];

/** How many parts a correction changes, for the status line. */
export function fixCount(sample: Array<SamplePart>): number {
  return sample.filter((part) => part.typed !== part.fixed).length;
}

export const heroFixCount = fixCount(heroSample);

/**
 * Reads a sample from a compact notation: `{typed|fixed}` marks a change, and
 * everything else is typed as it stays. A change that is more than a capital
 * letter or punctuation counts as a misspelling, which the spell checker
 * underlines while typing. `{typed|fixed|grammar}` marks a grammar fix, which
 * starts from a real word, so the spell checker has nothing to underline.
 */
export function parseSample(notation: string): Array<SamplePart> {
  return notation
    .split(/(\{[^}]*\})/)
    .filter(Boolean)
    .map((part) => {
      if (!part.startsWith('{')) return { typed: part, fixed: part };

      const [typed, fixed, kind] = part.slice(1, -1).split('|');
      const misspelled =
        kind !== 'grammar' && /\p{L}/u.test(typed) && typed.toLowerCase() !== fixed.toLowerCase();

      return { typed, fixed, misspelled };
    });
}
