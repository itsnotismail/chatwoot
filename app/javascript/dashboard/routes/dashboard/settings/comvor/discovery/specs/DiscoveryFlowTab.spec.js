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
  version_id: 3,
  flows: [
    {
      flow_key: 'sales',
      mode: 'ordered',
      display_name: 'Sales',
      description: '',
      stages: [
        {
          stage_key: 'discovery',
          display_name: 'Discovery',
          description: 'Greets and answers questions',
          guidance: 'greet',
          action_tool: '',
          has_action: false,
          notifiable: false,
          notify_enabled: false,
          notify_guidance: '',
          on_complete: 'continue',
          in_scope: true,
        },
        {
          stage_key: 'order_drafting',
          display_name: 'Order drafting',
          description: 'Collects order details',
          guidance: 'collect',
          action_tool: '',
          has_action: false,
          notifiable: true,
          notify_enabled: false,
          notify_guidance: '',
          on_complete: 'resolve',
          in_scope: false,
        },
      ],
    },
    {
      flow_key: 'support',
      mode: 'unordered',
      display_name: 'Support',
      description: '',
      stages: [
        {
          stage_key: 'refund_request',
          display_name: 'Refund request',
          description: 'Handles refund requests',
          guidance: 'be polite',
          action_tool: '',
          has_action: false,
          notifiable: false,
          notify_enabled: false,
          notify_guidance: '',
          on_complete: 'continue',
          in_scope: true,
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

function mockFetch({ publishResponse, putResponse } = {}) {
  let currentStatus = 'defaults';
  global.fetch = vi.fn((url, opts) => {
    if (putResponse && url.endsWith('/flow-config') && opts?.method === 'PUT') {
      return Promise.resolve(putResponse);
    }
    if (url.endsWith('/flow-config/publish') && opts?.method === 'POST') {
      if (publishResponse) return Promise.resolve(publishResponse);
      currentStatus = 'published';
      return Promise.resolve({
        ok: true,
        status: 200,
        json: () => Promise.resolve({ ...flowConfig, status: currentStatus }),
        text: () => Promise.resolve(''),
      });
    }
    let body = {};
    if (url.endsWith('/flow-config'))
      body = { ...flowConfig, status: currentStatus };
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

  it('defaults to the sales sub-tab, rendering the SalesFlowEditor with scope + wall info', async () => {
    const wrapper = mount(DiscoveryFlowTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();
    const text = wrapper.text();
    expect(text).toContain('Discovery');
    expect(text).toContain('Order drafting');
    // the walled stage surfaces its hard-error message somewhere
    expect(text).toContain('order.draft');
    // support flow is not rendered on the sales sub-tab
    expect(text).not.toContain('Refund request');
    // fetched only flow-config (connectors/notifications moved to their own tabs)
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  it('switching to the support sub-tab renders SupportIntentsEditor for the unordered flow', async () => {
    const wrapper = mount(DiscoveryFlowTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    await wrapper.find('[data-testid="sub-tab-support"]').trigger('click');
    await flushPromises();

    const text = wrapper.text();
    expect(text).toContain('Refund request');
    expect(text).not.toContain('Discovery');
  });

  it('toggling a support intent off PUTs a minimal body: only flow_key/stage_key/skipped', async () => {
    const wrapper = mount(DiscoveryFlowTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    await wrapper.find('[data-testid="sub-tab-support"]').trigger('click');
    await flushPromises();

    const toggle = wrapper.find('[data-testid="enable-toggle"]');
    await toggle.setValue(false);

    await wrapper.vm.saveDraft();
    await flushPromises();

    const putCall = global.fetch.mock.calls.find(
      call => call[1]?.method === 'PUT'
    );
    expect(putCall).toBeTruthy();
    const body = JSON.parse(putCall[1].body);
    expect(body.stages).toHaveLength(1);
    expect(body.stages[0]).toMatchObject({
      flow_key: 'support',
      stage_key: 'refund_request',
      skipped: true,
    });
    expect(Object.keys(body.stages[0]).sort()).toEqual(
      ['flow_key', 'skipped', 'stage_key'].sort()
    );
  });

  it('accumulates edits from SalesFlowEditor and PUTs only the changed stages on save', async () => {
    const wrapper = mount(DiscoveryFlowTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    // Simulate an edit coming from SalesFlowEditor (real child component, not
    // stubbed): flip the cutoff stage's finish choice via its radio.
    const radio = wrapper.find('input[data-testid="finish-handoff-radio"]');
    await radio.setValue(true);

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
      stage_key: 'order_drafting',
      on_complete: 'handoff',
    });
    expect(body.policy).toMatchObject(flowConfig.policy);
    // fetched flow-config on mount, plus the PUT and a reload after save.
    expect(global.fetch).toHaveBeenCalledTimes(3);
  });

  it('moving the cutoff sends a minimal PUT body: only flow_key/stage_key/on_complete per stage', async () => {
    const wrapper = mount(DiscoveryFlowTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    // Move the cutoff from order_drafting to discovery via the journey strip.
    const discoveryStep = wrapper.find(
      '[data-testid="journey-step"][data-stage-key="discovery"]'
    );
    await discoveryStep.trigger('click');

    await wrapper.vm.saveDraft();
    await flushPromises();

    const putCall = global.fetch.mock.calls.find(
      call => call[1]?.method === 'PUT'
    );
    const body = JSON.parse(putCall[1].body);
    expect(body.stages).toHaveLength(2);
    body.stages.forEach(stage => {
      expect(Object.keys(stage).sort()).toEqual(
        ['flow_key', 'on_complete', 'stage_key'].sort()
      );
    });
    const newCutoff = body.stages.find(s => s.stage_key === 'discovery');
    const oldCutoff = body.stages.find(s => s.stage_key === 'order_drafting');
    expect(newCutoff.on_complete).toBe('resolve'); // carries over previous finish choice
    expect(oldCutoff.on_complete).toBe('continue');
  });

  it('publish 422 renders hard-error messages inline and does not flip status', async () => {
    mockFetch({
      publishResponse: {
        ok: false,
        status: 422,
        json: () =>
          Promise.resolve({
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
          }),
        text: () => Promise.resolve(''),
      },
    });
    const wrapper = mount(DiscoveryFlowTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    await wrapper.vm.publish();
    await flushPromises();

    expect(wrapper.text()).toContain('no connector provides order.draft');
    expect(wrapper.vm.flowConfig.status).toBe('defaults');

    const publishCall = global.fetch.mock.calls.find(call =>
      call[0].endsWith('/flow-config/publish')
    );
    expect(publishCall[1].method).toBe('POST');
  });

  it('publish 200 flips status to published and clears prior errors', async () => {
    mockFetch();
    const wrapper = mount(DiscoveryFlowTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    // seed a prior hard-error panel (distinct message from the fixture's
    // per-stage wall) to verify the container-level panel gets cleared.
    wrapper.vm.hardErrors = [
      {
        flow_key: 'sales',
        stage_key: 'order_drafting',
        capability: 'order.draft',
        kind: 'hard',
        message: 'PRIOR_PUBLISH_HARD_ERROR',
      },
    ];
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toContain('PRIOR_PUBLISH_HARD_ERROR');

    await wrapper.vm.publish();
    await flushPromises();

    expect(wrapper.vm.flowConfig.status).toBe('published');
    expect(wrapper.text()).toContain('published');
    expect(wrapper.text()).not.toContain('PRIOR_PUBLISH_HARD_ERROR');
  });

  it('sends expected_version_id from the loaded config on save', async () => {
    const wrapper = mount(DiscoveryFlowTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    await wrapper.vm.saveDraft();
    await flushPromises();

    const putCall = global.fetch.mock.calls.find(
      call => call[1]?.method === 'PUT'
    );
    const body = JSON.parse(putCall[1].body);
    expect(body.expected_version_id).toBe(3);
  });

  it('shows the save wall panel when the refreshed draft has hard errors', async () => {
    // The fixture's flow-config carries a hard error; a successful save must
    // surface it in the container panel with the save-specific heading.
    const wrapper = mount(DiscoveryFlowTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    // Panel hidden on plain load (only per-stage wall text is shown).
    expect(wrapper.text()).not.toContain('SAVE_HARD_ERRORS_TITLE');

    await wrapper.vm.saveDraft();
    await flushPromises();

    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.SAVE_HARD_ERRORS_TITLE'
    );
    expect(wrapper.vm.hardErrors).toHaveLength(1);
  });

  it('reloads and clears dirty state when the save hits a version conflict (409)', async () => {
    mockFetch({
      putResponse: {
        ok: false,
        status: 409,
        json: () =>
          Promise.resolve({
            error: 'version_conflict',
            current_version_id: 9,
          }),
        text: () => Promise.resolve('version conflict'),
      },
    });
    const wrapper = mount(DiscoveryFlowTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    // Make a local edit so the dirty pill shows.
    const radio = wrapper.find('input[data-testid="finish-handoff-radio"]');
    await radio.setValue(true);
    expect(wrapper.text()).toContain('UNSAVED_CHANGES');

    global.fetch.mockClear();
    await wrapper.vm.saveDraft();
    await flushPromises();

    const { useAlert } = await import('dashboard/composables');
    expect(useAlert).toHaveBeenCalledWith(
      'COMVOR_SETTINGS.DISCOVERY.VERSION_CONFLICT_RELOADED'
    );
    // Server wins: flow-config re-fetched, local edits discarded, pill gone.
    const calledUrls = global.fetch.mock.calls.map(call => call[0]);
    expect(
      calledUrls.filter(
        u => u.endsWith('/flow-config') && !u.endsWith('/publish')
      ).length
    ).toBeGreaterThanOrEqual(2); // the PUT + the reload GET
    expect(wrapper.text()).not.toContain('UNSAVED_CHANGES');
  });
});
