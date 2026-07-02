import { flushPromises, mount } from '@vue/test-utils';
import OnboardingForm from '../OnboardingForm.vue';

// Minimal i18n mock (component uses this composable).
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

// The backend (comvor-engine) only accepts these three bot_reach values —
// anything else 422s. Table-driven so each radio option is checked against
// the exact backend-known string it must send.
const BOT_REACH_CASES = [
  { radioValue: 'answers_only', expectedBotReach: 'answers_only' },
  { radioValue: 'prepare_orders', expectedBotReach: 'prepare_orders' },
  {
    radioValue: 'payment_instructions',
    expectedBotReach: 'payment_instructions',
  },
];

function mockFetch() {
  global.fetch = vi.fn((url, opts) => {
    if (url.endsWith('/api/verticals')) {
      return Promise.resolve({
        ok: true,
        status: 200,
        json: () =>
          Promise.resolve([{ key: 'retail', display_name: 'Retail' }]),
      });
    }
    if (opts?.method === 'POST') {
      return Promise.resolve({
        ok: true,
        status: 200,
        json: () => Promise.resolve({ id: 'acc-1' }),
      });
    }
    return Promise.resolve({
      ok: true,
      status: 200,
      json: () => Promise.resolve({}),
    });
  });
}

async function fillRequiredFields(wrapper) {
  const select = wrapper.find('select');
  await select.setValue('retail');
  await wrapper.find('input[type="text"]').setValue('Acme Goods');
  await wrapper.find('textarea').setValue('We sell soap online.');
}

describe('OnboardingForm.vue', () => {
  beforeEach(mockFetch);

  it.each(BOT_REACH_CASES)(
    'sends bot_reach "$expectedBotReach" when the "$radioValue" radio is selected',
    async ({ radioValue, expectedBotReach }) => {
      const wrapper = mount(OnboardingForm, {
        props: {
          accountId: '7',
          engineUrl: 'http://engine',
          authHeaders: () => ({ Authorization: 'Bearer tok' }),
        },
      });
      await flushPromises();
      await fillRequiredFields(wrapper);

      const radios = wrapper.findAll('input[type="radio"]');
      const radio = radios.find(r => r.element.value === radioValue);
      expect(radio, `radio for value "${radioValue}" must exist`).toBeTruthy();
      await radio.setValue();

      await wrapper.find('button').trigger('click');
      await flushPromises();

      const postCall = global.fetch.mock.calls.find(
        call => call[1]?.method === 'POST'
      );
      expect(postCall).toBeTruthy();
      const body = JSON.parse(postCall[1].body);

      // The submitted value must be exactly one of the three backend-known
      // strings, and specifically the one implied by the radio picked.
      expect([
        'answers_only',
        'prepare_orders',
        'payment_instructions',
      ]).toContain(body.bot_reach);
      expect(body.bot_reach).toBe(expectedBotReach);
    }
  );

  it('defaults bot_reach to "prepare_orders" when no radio is explicitly picked', async () => {
    const wrapper = mount(OnboardingForm, {
      props: {
        accountId: '7',
        engineUrl: 'http://engine',
        authHeaders: () => ({ Authorization: 'Bearer tok' }),
      },
    });
    await flushPromises();
    await fillRequiredFields(wrapper);

    await wrapper.find('button').trigger('click');
    await flushPromises();

    const postCall = global.fetch.mock.calls.find(
      call => call[1]?.method === 'POST'
    );
    expect(postCall).toBeTruthy();
    const body = JSON.parse(postCall[1].body);
    expect(body.bot_reach).toBe('prepare_orders');
  });
});
