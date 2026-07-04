import { flushPromises, mount } from '@vue/test-utils';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Index from '../Index.vue';

// Minimal i18n + store + alert + router mocks, matching the pattern used in
// DiscoveryFlowTab.spec.js / NotificationsTab.spec.js for this same settings
// area. `t` echoes the key so assertions can check exact i18n keys were used
// (e.g. proving the type <option>s are label-mapped, not hard-coded text).
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentUser: { access_token: 'tok' } } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-router');
// BaseSettingsHeader -> BackButton -> dashboard/routes/index eagerly builds
// the entire app route tree (every settings sub-route). We stub
// BaseSettingsHeader below, but static ESM imports still execute before
// stubbing kicks in, so the underlying router module must be mocked too.
vi.mock('dashboard/routes/index', () => ({
  default: { push: vi.fn(), go: vi.fn() },
}));

// Index.vue pulls in several heavy sibling components/layout chrome that
// aren't relevant to the connector tab itself (router links, help-center
// lookups, global woot-tabs/woot-loading-state components not registered in
// the vitest environment). We stub those so we can mount the *real* Index.vue
// script (real `saveConnector`, real `compatibleConnectors` computed, real
// connector-tab template) without dragging in unrelated infrastructure.
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

function mockFetch({ connectorType = 'none' } = {}) {
  global.fetch = vi.fn((url, opts) => {
    if (url.endsWith('/api/verticals')) return jsonResponse(VERTICALS);
    if (url.endsWith('/knowledge-cards')) return jsonResponse([]);
    if (url.endsWith('/flow-config')) return jsonResponse({ policy: {} });
    if (url.endsWith('/connectors/ewity') && !opts) {
      return jsonResponse({ token_hint: '', permissions: [] });
    }
    if (url.endsWith('/connectors') && !opts) {
      return jsonResponse({
        enabled: connectorType === 'ewity' ? ['ewity'] : [],
        providers: {},
        available: ['none', 'ewity'],
        disabled_capabilities: [],
      });
    }
    // account GET
    if (!opts && /\/api\/accounts\/\d+$/.test(url)) {
      return jsonResponse({
        business_category: 'retail',
        connector_type: connectorType,
      });
    }
    // PUTs (account save, ewity creds save, connectors save) and any other
    // GET refresh calls issued during saveConnector.
    return jsonResponse({ token_hint: '', permissions: [] });
  });
}

// Mocks the initial /connectors GET (fired from fetchSettings -> loadConnectors
// on mount) to fail every time, so `connectors.value` stays null throughout —
// reproducing the state where the connector tab loaded but its /connectors
// fetch silently failed (loadConnectors catches + alerts, doesn't rethrow).
function mockFetchConnectorsGetAlwaysFails({ connectorType = 'none' } = {}) {
  global.fetch = vi.fn((url, opts) => {
    const isGet = !opts?.method;
    if (url.endsWith('/api/verticals')) return jsonResponse(VERTICALS);
    if (url.endsWith('/knowledge-cards')) return jsonResponse([]);
    if (url.endsWith('/flow-config')) return jsonResponse({ policy: {} });
    if (url.endsWith('/connectors/ewity') && isGet) {
      return jsonResponse({ token_hint: '', permissions: [] });
    }
    if (url.endsWith('/connectors') && isGet) {
      return Promise.reject(new Error('network down'));
    }
    // account GET
    if (isGet && /\/api\/accounts\/\d+$/.test(url)) {
      return jsonResponse({
        business_category: 'retail',
        connector_type: connectorType,
      });
    }
    // PUTs (account save, ewity creds save) and any other GET refresh calls
    // issued during saveConnector. The /connectors PUT is intentionally NOT
    // special-cased here — if it's ever issued, its body is inspected below.
    return jsonResponse({ token_hint: '', permissions: [] });
  });
}

function mountIndex() {
  return mount(Index, { global: { stubs } });
}

beforeEach(() => {
  useRoute.mockReturnValue({ params: { accountId: '1' } });
  window.globalConfig = { COMVOR_ENGINE_URL: 'http://engine' };
});

describe('Index.vue — Connector tab (unified panel)', () => {
  it('renders exactly one <option> per GA-gated compatible connector, and never a shopify option', async () => {
    mockFetch();
    const wrapper = mountIndex();
    await flushPromises();
    wrapper.vm.selectedTab = 4;
    await flushPromises();

    const select = wrapper.find('select[data-testid="connector-type-select"]');
    expect(select.exists()).toBe(true);
    const options = select.findAll('option');
    const values = options.map(o => o.element.value);

    expect(values).toEqual(['none', 'ewity']);
    expect(values).not.toContain('shopify');
  });

  it('PUTs /connectors with enabled including "ewity" after choosing type ewity, entering a token, and saving', async () => {
    mockFetch({ connectorType: 'none' });
    const wrapper = mountIndex();
    await flushPromises();
    wrapper.vm.selectedTab = 4;
    await flushPromises();

    await wrapper
      .find('select[data-testid="connector-type-select"]')
      .setValue('ewity');
    await wrapper.find('input[type="password"]').setValue('uat_sometoken');

    await wrapper.vm.saveConnector();
    await flushPromises();

    const connectorsPut = global.fetch.mock.calls.find(
      ([url, opts]) => url.endsWith('/connectors') && opts?.method === 'PUT'
    );
    expect(connectorsPut).toBeTruthy();
    const body = JSON.parse(connectorsPut[1].body);
    expect(body.enabled).toContain('ewity');
  });

  it('PUTs /connectors with enabled NOT including "ewity" after choosing type none and saving', async () => {
    mockFetch({ connectorType: 'ewity' });
    const wrapper = mountIndex();
    await flushPromises();
    wrapper.vm.selectedTab = 4;
    await flushPromises();

    await wrapper
      .find('select[data-testid="connector-type-select"]')
      .setValue('none');

    await wrapper.vm.saveConnector();
    await flushPromises();

    const connectorsPut = global.fetch.mock.calls.find(
      ([url, opts]) => url.endsWith('/connectors') && opts?.method === 'PUT'
    );
    expect(connectorsPut).toBeTruthy();
    const body = JSON.parse(connectorsPut[1].body);
    expect(body.enabled).not.toContain('ewity');
  });

  it('never PUTs disabled_capabilities: [] to /connectors when the initial connectors GET failed (connectors.value stayed null)', async () => {
    mockFetchConnectorsGetAlwaysFails({ connectorType: 'none' });
    const wrapper = mountIndex();
    await flushPromises();
    wrapper.vm.selectedTab = 4;
    await flushPromises();

    // Sanity check: the load failure really did leave connectors.value null,
    // reproducing the bug precondition (loadConnectors catches + alerts but
    // doesn't rethrow, and isLoading still clears so the tab is usable).
    expect(wrapper.vm.connectors).toBeNull();

    await wrapper
      .find('select[data-testid="connector-type-select"]')
      .setValue('ewity');
    await wrapper.find('input[type="password"]').setValue('uat_sometoken');

    await wrapper.vm.saveConnector();
    await flushPromises();

    const wipingPut = global.fetch.mock.calls.find(([url, opts]) => {
      if (!(url.endsWith('/connectors') && opts?.method === 'PUT')) {
        return false;
      }
      const body = JSON.parse(opts.body);
      return (
        Array.isArray(body.disabled_capabilities) &&
        body.disabled_capabilities.length === 0
      );
    });
    expect(wipingPut).toBeUndefined();

    // The failure must be surfaced, not silently swallowed as a success.
    expect(useAlert).toHaveBeenCalledWith(
      'COMVOR_SETTINGS.CONNECTOR.EWITY.SAVE_ERROR'
    );
  });
});
