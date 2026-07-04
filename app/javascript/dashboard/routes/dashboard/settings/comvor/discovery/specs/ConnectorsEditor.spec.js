import { mount } from '@vue/test-utils';
import ConnectorsEditor from '../ConnectorsEditor.vue';

// Minimal i18n mock, matching the pattern used in other discovery specs.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const connectors = {
  enabled: ['ewity'],
  providers: {},
  available: ['ewity', 'shopify'],
};

function mountEditor(props = {}) {
  return mount(ConnectorsEditor, {
    props: { connectors, ...props },
  });
}

// NOTE: this component used to also render a connector ENABLE checkbox list
// (one checkbox per `connectors.available`) with its own emit path, tested
// here previously. That list moved out to the unified Connector tab in
// Index.vue (see ConnectorTab.spec.js) — enabling now happens via "connect"
// (choosing the type + saving), which also flips the account_connectors
// enabled list. ConnectorsEditor now renders only the soft-wall capability
// toggles and the provider-conflict select, so those enable-checkbox specs
// were removed rather than weakened.
describe('ConnectorsEditor.vue', () => {
  it('renders an unchecked capability box for a capability in disabled_capabilities, and re-enabling it removes it from the emitted array', async () => {
    const wrapper = mountEditor({
      connectors: {
        ...connectors,
        disabled_capabilities: ['order.draft'],
      },
    });

    const capabilityCheckboxes = wrapper.findAll(
      'input[data-testid="capability-checkbox"]'
    );
    expect(capabilityCheckboxes).toHaveLength(1);
    expect(capabilityCheckboxes[0].element.checked).toBe(false);

    await capabilityCheckboxes[0].setValue(true); // re-enable order.draft

    const emitted = wrapper.emitted('update:connectors');
    expect(emitted).toBeTruthy();
    const lastEvent = emitted[emitted.length - 1][0];
    expect(lastEvent.disabled_capabilities).not.toContain('order.draft');
  });

  it('unchecking a capability box named only in softWarnings adds it to the emitted disabled_capabilities', async () => {
    const wrapper = mountEditor({
      connectors: { ...connectors, disabled_capabilities: [] },
      softWarnings: [
        { capability: 'order.draft', message: 'no connector provides it' },
      ],
    });

    const capabilityCheckboxes = wrapper.findAll(
      'input[data-testid="capability-checkbox"]'
    );
    expect(capabilityCheckboxes).toHaveLength(1);
    expect(capabilityCheckboxes[0].element.checked).toBe(true); // not disabled yet

    await capabilityCheckboxes[0].setValue(false); // disable order.draft

    const emitted = wrapper.emitted('update:connectors');
    expect(emitted).toBeTruthy();
    const lastEvent = emitted[emitted.length - 1][0];
    expect(lastEvent.disabled_capabilities).toContain('order.draft');
  });
});
