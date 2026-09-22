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

/** How many parts the correction changes, for the status line. */
export const heroFixCount = heroSample.filter((part) => part.typed !== part.fixed).length;
