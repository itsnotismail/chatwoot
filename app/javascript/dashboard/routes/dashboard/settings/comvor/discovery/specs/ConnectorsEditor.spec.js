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
});
