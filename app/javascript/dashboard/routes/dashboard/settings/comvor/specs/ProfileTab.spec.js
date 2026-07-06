import { flushPromises, mount } from '@vue/test-utils';
import { useRoute } from 'vue-router';
import Index from '../Index.vue';

// Same minimal-mock pattern as ConnectorTab.spec.js for this settings area:
// `t` echoes the key so assertions can check exact i18n keys/values were used.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentUser: { access_token: 'tok' } } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-router');
vi.mock('dashboard/routes/index', () => ({
  default: { push: vi.fn(), go: vi.fn() },
}));

const stubs = {
  SettingsLayout: {
    template: '<div><slot name="header" /><slot name="body" /></div>',
  },
  BaseSettingsHeader: { template: '<div />' },
  OnboardingForm: { template: '<div />' },
  DiscoveryFlowTab: { template: '<div />' },
  NotificationsTab: { template: '<div />' },
  'woot-tabs': { template: '<div><slot /></div>' },
  'woot-tabs-item': { template: '<div />' },
};

const VERTICALS = [
  {
    key: 'retail',
    display_name: 'Retail',
    policy_fields: [],
    compatible_connectors: ['none', 'ewity'],
  },
];

function jsonResponse(body) {
  return Promise.resolve({
    ok: true,
    status: 200,
    json: () => Promise.resolve(body),
    text: () => Promise.resolve(''),
  });
}

// Mocks fetchSettings' dependencies for the profile tab. `timezone`/`currency`
// on the account GET response are the values under test (legacy/invalid vs.
// valid IANA/ISO codes).
function mockFetch({ timezone, currency } = {}) {
  global.fetch = vi.fn((url, opts) => {
    if (url.endsWith('/api/verticals')) return jsonResponse(VERTICALS);
    if (url.endsWith('/knowledge-cards')) return jsonResponse([]);
    if (url.endsWith('/flow-config')) return jsonResponse({ policy: {} });
    if (url.endsWith('/connectors/ewity') && !opts) {
      return jsonResponse({ token_hint: '', permissions: [] });
    }
    if (url.endsWith('/connectors') && !opts) {
      return jsonResponse({
        enabled: [],
        providers: {},
        available: ['none', 'ewity'],
        disabled_capabilities: [],
      });
    }
    // account GET
    if (!opts && /\/api\/accounts\/\d+$/.test(url)) {
      return jsonResponse({
        business_category: 'retail',
        connector_type: 'none',
        timezone,
        currency,
      });
    }
    // account PUT (saveSettings)
    return jsonResponse({});
  });
}

function mountIndex() {
  return mount(Index, { global: { stubs } });
}

beforeEach(() => {
  useRoute.mockReturnValue({ params: { accountId: '1' } });
  window.globalConfig = { COMVOR_ENGINE_URL: 'http://engine' };
});

describe('Index.vue — Profile tab timezone/currency dropdowns', () => {
  it('renders a single Indian/Maldives timezone option with IANA value and MVT/UTC+5 label', async () => {
    mockFetch({ timezone: 'Indian/Maldives', currency: 'MVR' });
    const wrapper = mountIndex();
    await flushPromises();

    const select = wrapper.find('select[data-testid="timezone-select"]');
    expect(select.exists()).toBe(true);
    const options = select.findAll('option');
    expect(options).toHaveLength(1);
    expect(options[0].element.value).toBe('Indian/Maldives');
    expect(options[0].text()).toBe(
      'COMVOR_SETTINGS.FIELDS.TIMEZONE.OPTIONS.INDIAN_MALDIVES'
    );
  });

  it('renders a single MVR currency option with ISO value and descriptive label', async () => {
    mockFetch({ timezone: 'Indian/Maldives', currency: 'MVR' });
    const wrapper = mountIndex();
    await flushPromises();

    const select = wrapper.find('select[data-testid="currency-select"]');
    expect(select.exists()).toBe(true);
    const options = select.findAll('option');
    expect(options).toHaveLength(1);
    expect(options[0].element.value).toBe('MVR');
    expect(options[0].text()).toBe(
      'COMVOR_SETTINGS.FIELDS.CURRENCY.OPTIONS.MVR'
    );
  });

  it('stores the IANA/ISO codes on form when a valid account value is loaded', async () => {
    mockFetch({ timezone: 'Indian/Maldives', currency: 'MVR' });
    const wrapper = mountIndex();
    await flushPromises();

    expect(wrapper.vm.form.timezone).toBe('Indian/Maldives');
    expect(wrapper.vm.form.currency).toBe('MVR');
  });

  it('preselects the first timezone option when the stored value is legacy/invalid (e.g. "MVR")', async () => {
    mockFetch({ timezone: 'MVR', currency: 'MVR' });
    const wrapper = mountIndex();
    await flushPromises();

    // The bug this whole batch fixes: timezone was once saved as "MVR" (a
    // currency code), which Go's time.LoadLocation rejects. The dropdown
    // must heal this by preselecting the first valid option...
    expect(wrapper.vm.form.timezone).toBe('Indian/Maldives');
    const select = wrapper.find('select[data-testid="timezone-select"]');
    expect(select.element.value).toBe('Indian/Maldives');
  });

  it('preselects the first option for both fields when the stored values are empty', async () => {
    mockFetch({ timezone: '', currency: '' });
    const wrapper = mountIndex();
    await flushPromises();

    expect(wrapper.vm.form.timezone).toBe('Indian/Maldives');
    expect(wrapper.vm.form.currency).toBe('MVR');
  });

  it('does not auto-save the healed legacy value — no PUT fires from load alone', async () => {
    mockFetch({ timezone: 'MVR', currency: 'MVR' });
    mountIndex();
    await flushPromises();

    const accountPut = global.fetch.mock.calls.find(
      ([url, opts]) =>
        /\/api\/accounts\/\d+$/.test(url) && opts?.method === 'PUT'
    );
    expect(accountPut).toBeUndefined();
  });
});
