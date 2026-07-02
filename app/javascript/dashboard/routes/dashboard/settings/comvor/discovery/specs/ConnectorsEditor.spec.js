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

describe('ConnectorsEditor.vue', () => {
  it('renders a checkbox per available connector, checked if enabled', () => {
    const wrapper = mountEditor();
    const checkboxes = wrapper.findAll(
      'input[data-testid="connector-checkbox"]'
    );
    expect(checkboxes).toHaveLength(2);
    expect(checkboxes[0].element.checked).toBe(true); // ewity is enabled
    expect(checkboxes[1].element.checked).toBe(false); // shopify is not enabled
  });

  it('emits update:connectors with the updated enabled array when toggling an available connector', async () => {
    const wrapper = mountEditor();
    const checkboxes = wrapper.findAll(
      'input[data-testid="connector-checkbox"]'
    );
    await checkboxes[1].setValue(true); // enable shopify

    const emitted = wrapper.emitted('update:connectors');
    expect(emitted).toBeTruthy();
    const lastEvent = emitted[emitted.length - 1][0];
    expect(lastEvent.enabled).toEqual(
      expect.arrayContaining(['ewity', 'shopify'])
    );
    expect(lastEvent.enabled).toHaveLength(2);
  });

  it('emits update:connectors with a shrunk enabled array when disabling an enabled connector', async () => {
    const wrapper = mountEditor();
    const checkboxes = wrapper.findAll(
      'input[data-testid="connector-checkbox"]'
    );
    await checkboxes[0].setValue(false); // disable ewity

    const emitted = wrapper.emitted('update:connectors');
    expect(emitted).toBeTruthy();
    const lastEvent = emitted[emitted.length - 1][0];
    expect(lastEvent.enabled).toEqual([]);
  });

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
