import { mount } from '@vue/test-utils';
import FlowEditor from '../FlowEditor.vue';

// Minimal i18n mock, matching the pattern used in DiscoveryFlowTab.spec.js.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const flow = {
  flow_key: 'sales',
  mode: 'ordered',
  stages: [
    {
      stage_key: 'discovery',
      guidance: 'greet',
      action_tool: '',
      on_complete: 'continue',
      in_scope: true,
    },
    {
      stage_key: 'order_drafting',
      guidance: 'collect',
      action_tool: 'create_order',
      on_complete: 'resolve',
      in_scope: false,
    },
  ],
};

const walls = [
  {
    flow_key: 'sales',
    stage_key: 'order_drafting',
    capability: 'order.draft',
    kind: 'hard',
    message: 'no connector provides order.draft',
  },
];

function mountEditor(props = {}) {
  return mount(FlowEditor, {
    props: { flow, walls, ...props },
  });
}

describe('FlowEditor.vue', () => {
  it('emits update:stage with the new value when the on_complete select changes', async () => {
    const wrapper = mountEditor();
    const selects = wrapper.findAll('select[data-testid="on-complete-select"]');
    // discovery stage is the first, not walled
    const discoverySelect = selects[0];
    await discoverySelect.setValue('handoff');

    const emitted = wrapper.emitted('update:stage');
    expect(emitted).toBeTruthy();
    const lastEvent = emitted[emitted.length - 1][0];
    expect(lastEvent).toMatchObject({
      flow_key: 'sales',
      stage_key: 'discovery',
      on_complete: 'handoff',
    });
  });

  it('disables all controls for a walled stage and shows the wall message', () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="stage-row"]');
    const walledRow = rows[1]; // order_drafting is walled
    expect(walledRow.text()).toContain('no connector provides order.draft');

    const controls = walledRow.findAll('select, textarea, input');
    expect(controls.length).toBeGreaterThan(0);
    controls.forEach(control => {
      expect(control.attributes('disabled')).toBeDefined();
    });
  });

  it('only renders the action-mode select when the stage has an action_tool or an action wall', () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="stage-row"]');
    // discovery has no action_tool and is not walled -> no action-mode select
    expect(
      rows[0].find('select[data-testid="action-mode-select"]').exists()
    ).toBe(false);
    // order_drafting has action_tool set -> action-mode select present
    expect(
      rows[1].find('select[data-testid="action-mode-select"]').exists()
    ).toBe(true);
  });
});
