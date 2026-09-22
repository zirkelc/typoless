import { parseSample, type SamplePart } from './hero-sample';

/** An app the showcase draws, with the message corrected in it. */
export interface AppSample {
  id: 'mail' | 'slack' | 'notes' | 'messages' | 'safari' | 'notion';
  name: string;
  /** The app's own colour, for its tab and its icon in the title bar. */
  color: string;
  sample: Array<SamplePart>;
}

export const appSamples: Array<AppSample> = [
  {
    id: 'mail',
    name: 'Mail',
    color: '#1e90ff',
    sample: parseSample(
      'Hi Anna,\n\n{teh|The} slides are attached. Let me know if {your|you’re} happy with them, or if anything {need|needs|grammar} changing{|.}',
    ),
  },
  {
    id: 'slack',
    name: 'Slack',
    color: '#611f69',
    sample: parseSample(
      '{yes|Yes}, the build is {redy|ready}{|.} I’ll post the release notes in the {mornign|morning}.',
    ),
  },
  {
    id: 'notes',
    name: 'Notes',
    color: '#e5b000',
    sample: parseSample(
      'Am {samstag|Samstag} zum Markt, danach {kafee|Kaffee} mit Lena{|.}\nNicht {vergesen|vergessen}: Geschenk für Oma.',
    ),
  },
  {
    id: 'messages',
    name: 'Messages',
    color: '#34c759',
    sample: parseSample('{ill|I’ll} be there around {eigth|eight}{|.} {see|See} you soon!'),
  },
  {
    id: 'safari',
    name: 'Safari',
    color: '#0a84ff',
    sample: parseSample(
      '{the|The} ending surprised me{|,} but the middle drags a {litle|little}. Still worth {reding|reading}.',
    ),
  },
  {
    id: 'notion',
    name: 'Notion',
    color: '#787774',
    sample: parseSample('Book the {ofsite|offsite} for {thursday|Thursday}{|.}'),
  },
];
