import { mount } from '@vue/test-utils';
import LifecyclePolicyEditor from '../LifecyclePolicyEditor.vue';

// Minimal i18n mock, matching the pattern used in other discovery specs.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const policy = {
  debounce_ms: 3000,
  follow_up_after: 900,
  follow_up_count: 1,
  resolve_after: 86400,
  idle_terminal: 'resolve',
};

function mountEditor(props = {}) {
  return mount(LifecyclePolicyEditor, {
    props: { policy, ...props },
  });
}

describe('LifecyclePolicyEditor.vue', () => {
  it('emits update:policy with the full updated object when the idle_terminal select changes', async () => {
    const wrapper = mountEditor();
    const select = wrapper.find('select[data-testid="idle-terminal-select"]');
    await select.setValue('handoff');

    const emitted = wrapper.emitted('update:policy');
    expect(emitted).toBeTruthy();
    const lastEvent = emitted[emitted.length - 1][0];
    expect(lastEvent).toMatchObject({
      debounce_ms: 3000,
      follow_up_after: 900,
      follow_up_count: 1,
      resolve_after: 86400,
      idle_terminal: 'handoff',
    });
  });

  it('emits update:policy with the full updated object when a number field changes', async () => {
    const wrapper = mountEditor();
    const input = wrapper.find('input[data-testid="debounce-ms-input"]');
    await input.setValue(5000);

    const emitted = wrapper.emitted('update:policy');
    expect(emitted).toBeTruthy();
    const lastEvent = emitted[emitted.length - 1][0];
    expect(lastEvent).toMatchObject({
      debounce_ms: 5000,
      follow_up_after: 900,
      follow_up_count: 1,
      resolve_after: 86400,
      idle_terminal: 'resolve',
    });
  });
});
