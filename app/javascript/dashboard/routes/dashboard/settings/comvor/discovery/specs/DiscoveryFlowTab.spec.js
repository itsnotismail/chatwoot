import { flushPromises, mount } from '@vue/test-utils';
import DiscoveryFlowTab from '../DiscoveryFlowTab.vue';

// Minimal i18n + store + alert mocks (components use these composables).
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentUser: { access_token: 'tok' } } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const flowConfig = {
  status: 'defaults',
  flows: [
    {
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
          action_tool: '',
          on_complete: 'resolve',
          in_scope: false,
        },
      ],
    },
  ],
  policy: {
    debounce_ms: 3000,
    follow_up_after: 900,
    follow_up_count: 1,
    resolve_after: 86400,
    idle_terminal: 'resolve',
  },
  hard_errors: [
    {
      flow_key: 'sales',
      stage_key: 'order_drafting',
      capability: 'order.draft',
      kind: 'hard',
      message: 'no connector provides order.draft',
    },
  ],
  soft_warnings: [],
};

function mockFetch() {
  global.fetch = vi.fn(url => {
    let body = {};
    if (url.endsWith('/flow-config')) body = flowConfig;
    else if (url.endsWith('/connectors'))
      body = { enabled: [], providers: {}, available: ['ewity'] };
    else if (url.endsWith('/notifications'))
      body = { channels: [], subscriptions: [] };
    return Promise.resolve({
      ok: true,
      status: 200,
      json: () => Promise.resolve(body),
      text: () => Promise.resolve(''),
    });
  });
}

describe('DiscoveryFlowTab.vue', () => {
  beforeEach(mockFetch);

  it('loads and renders a FlowEditor per flow with scope + wall info', async () => {
    const wrapper = mount(DiscoveryFlowTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();
    const text = wrapper.text();
    expect(text).toContain('discovery');
    expect(text).toContain('order_drafting');
    // the walled stage surfaces its hard-error message somewhere
    expect(text).toContain('order.draft');
    // fetched all three endpoints
    expect(global.fetch).toHaveBeenCalledTimes(3);
  });

  it('accumulates edits from FlowEditor and PUTs only the changed stages on save', async () => {
    const wrapper = mount(DiscoveryFlowTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    // Simulate an edit coming from FlowEditor (real child component, not stubbed).
    const select = wrapper.find('select[data-testid="on-complete-select"]');
    await select.setValue('handoff');

    expect(wrapper.text()).toContain('UNSAVED_CHANGES');

    await wrapper.vm.saveDraft();
    await flushPromises();

    const putCall = global.fetch.mock.calls.find(
      call => call[1]?.method === 'PUT'
    );
    expect(putCall).toBeTruthy();
    expect(putCall[0]).toBe('http://engine/api/accounts/7/flow-config');
    const body = JSON.parse(putCall[1].body);
    expect(body.stages).toHaveLength(1);
    expect(body.stages[0]).toMatchObject({
      flow_key: 'sales',
      stage_key: 'discovery',
      on_complete: 'handoff',
      enabled_reads: [],
    });
    expect(body.policy).toMatchObject(flowConfig.policy);
    // fetched all three endpoints on mount, plus the PUT and the reload-all after save
    expect(global.fetch).toHaveBeenCalledTimes(7);
  });
});
