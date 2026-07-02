import { flowSummary } from '../summary.js';

// Minimal fake translator: resolves the small set of keys summary.js uses,
// applying {var} interpolation the same way vue-i18n does, so specs assert
// on real interpolated sentences without mounting a component.
const STRINGS = {
  'COMVOR_SETTINGS.DISCOVERY.SUMMARY.AND': 'and',
  'COMVOR_SETTINGS.DISCOVERY.SUMMARY.FINISH_HANDOFF': 'hands over to your team',
  'COMVOR_SETTINGS.DISCOVERY.SUMMARY.FINISH_RESOLVE':
    'resolves the conversation',
  'COMVOR_SETTINGS.DISCOVERY.SUMMARY.NO_STAGES':
    'Your bot has no active steps yet.',
  'COMVOR_SETTINGS.DISCOVERY.SUMMARY.TEMPLATE':
    'Your bot {actions} — then {finish}.',
};

function fakeT(key, vars) {
  const str = STRINGS[key] ?? key;
  if (!vars) return str;
  return Object.entries(vars).reduce(
    (acc, [k, v]) => acc.replaceAll(`{${k}}`, v),
    str
  );
}

function stage(overrides) {
  return {
    stage_key: 'stage',
    display_name: 'does a thing',
    on_complete: 'continue',
    ...overrides,
  };
}

describe('flowSummary', () => {
  const cases = [
    {
      name: 'single bot stage then handoff',
      stages: [
        stage({
          display_name: 'answers product questions',
          on_complete: 'handoff',
        }),
      ],
      expected:
        'Your bot answers product questions — then hands over to your team.',
    },
    {
      name: 'two bot stages joined with and',
      stages: [
        stage({
          display_name: 'answers product questions',
          on_complete: 'continue',
        }),
        stage({ display_name: 'checks stock', on_complete: 'handoff' }),
      ],
      expected:
        'Your bot answers product questions and checks stock — then hands over to your team.',
    },
    {
      name: 'three+ bot stages use oxford comma list',
      stages: [
        stage({
          display_name: 'answers product questions',
          on_complete: 'continue',
        }),
        stage({ display_name: 'checks stock', on_complete: 'continue' }),
        stage({ display_name: 'prepares orders', on_complete: 'handoff' }),
      ],
      expected:
        'Your bot answers product questions, checks stock, and prepares orders — then hands over to your team.',
    },
    {
      name: 'resolve finish uses the resolve phrase',
      stages: [
        stage({
          display_name: 'answers product questions',
          on_complete: 'resolve',
        }),
      ],
      expected:
        'Your bot answers product questions — then resolves the conversation.',
    },
    {
      name: 'stages after the cutoff are excluded from the sentence',
      stages: [
        stage({
          display_name: 'answers product questions',
          on_complete: 'handoff',
        }),
        stage({ display_name: 'prepares orders', on_complete: 'continue' }),
      ],
      expected:
        'Your bot answers product questions — then hands over to your team.',
    },
    {
      name: 'falls back to stage_key when display_name is empty',
      stages: [
        stage({
          stage_key: 'discovery',
          display_name: '',
          on_complete: 'handoff',
        }),
      ],
      expected: 'Your bot discovery — then hands over to your team.',
    },
    {
      name: 'no stages at all renders the empty-state sentence',
      stages: [],
      expected: 'Your bot has no active steps yet.',
    },
    {
      name: 'no cutoff (all continue) still lists every stage, defaults to handoff phrasing',
      stages: [
        stage({
          display_name: 'answers product questions',
          on_complete: 'continue',
        }),
        stage({ display_name: 'checks stock', on_complete: 'continue' }),
      ],
      expected:
        'Your bot answers product questions and checks stock — then hands over to your team.',
    },
  ];

  cases.forEach(({ name, stages, expected }) => {
    it(name, () => {
      expect(flowSummary({ stages }, fakeT)).toBe(expected);
    });
  });
});
