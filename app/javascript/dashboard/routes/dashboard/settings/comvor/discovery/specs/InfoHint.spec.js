import { mount } from '@vue/test-utils';
import InfoHint from '../InfoHint.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

function mountHarness(props = {}) {
  return mount(
    {
      components: { InfoHint },
      props: ['text'],
      template: `
        <label>
          <input type="checkbox" />
          <InfoHint :text="text" />
        </label>
      `,
    },
    {
      props: { text: 'Explains the thing', ...props },
    }
  );
}

describe('InfoHint.vue', () => {
  it('does not show the help text initially', () => {
    const wrapper = mountHarness();
    expect(wrapper.find('[data-testid="info-hint-text"]').exists()).toBe(false);
  });

  it('clicking the toggle reveals the help text without toggling the sibling checkbox', async () => {
    const wrapper = mountHarness();
    const checkbox = wrapper.find('input[type="checkbox"]');
    expect(checkbox.element.checked).toBe(false);

    await wrapper.find('[data-testid="info-hint-toggle"]').trigger('click');

    expect(checkbox.element.checked).toBe(false);
    const helpText = wrapper.find('[data-testid="info-hint-text"]');
    expect(helpText.exists()).toBe(true);
    expect(helpText.text()).toContain('Explains the thing');
  });

  it('clicking the toggle again hides the help text', async () => {
    const wrapper = mountHarness();
    await wrapper.find('[data-testid="info-hint-toggle"]').trigger('click');
    expect(wrapper.find('[data-testid="info-hint-text"]').exists()).toBe(true);

    await wrapper.find('[data-testid="info-hint-toggle"]').trigger('click');
    expect(wrapper.find('[data-testid="info-hint-text"]').exists()).toBe(false);
  });
});
