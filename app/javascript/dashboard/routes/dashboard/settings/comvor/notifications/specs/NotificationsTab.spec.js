import { flushPromises, mount } from '@vue/test-utils';
import NotificationsTab from '../NotificationsTab.vue';
import { useAlert } from 'dashboard/composables';

// Minimal i18n + store + alert mocks (components use these composables).
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentUser: { access_token: 'tok' } } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

function flowConfigResponse() {
  return {
    ok: true,
    status: 200,
    json: () =>
      Promise.resolve({
        version_id: 42,
        flows: [
          {
            flow_key: 'sales',
            stages: [
              {
                stage_key: 'order_drafting',
                display_name: 'Order taking',
                notifiable: true,
                notify_enabled: true,
                notify_guidance: '',
              },
              {
                stage_key: 'discovery',
                display_name: 'Discovery',
                notifiable: false,
                notify_enabled: false,
                notify_guidance: '',
              },
            ],
          },
        ],
      }),
    text: () => Promise.resolve(''),
  };
}

function mockFetch({ putResponse, flowConfigPutResponse } = {}) {
  global.fetch = vi.fn((url, opts) => {
    if (url.endsWith('/notifications') && opts?.method === 'PUT') {
      if (putResponse) return Promise.resolve(putResponse);
      return Promise.resolve({
        ok: true,
        status: 200,
        json: () =>
          Promise.resolve({
            channels: [],
            subscriptions: [],
            muted_events: [],
          }),
        text: () => Promise.resolve(''),
      });
    }
    if (url.endsWith('/flow-config') && opts?.method === 'PUT') {
      if (flowConfigPutResponse) return Promise.resolve(flowConfigPutResponse);
      return Promise.resolve(flowConfigResponse());
    }
    if (url.endsWith('/flow-config')) {
      return Promise.resolve(flowConfigResponse());
    }
    return Promise.resolve({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({ channels: [], subscriptions: [], muted_events: [] }),
      text: () => Promise.resolve(''),
    });
  });
}

describe('NotificationsTab.vue', () => {
  beforeEach(mockFetch);

  it('loads notifications on mount and renders the editor', async () => {
    const wrapper = mount(NotificationsTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    expect(global.fetch).toHaveBeenCalledWith(
      'http://engine/api/accounts/7/notifications',
      expect.any(Object)
    );
    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.TITLE'
    );
  });

  it('fetches flow-config and derives notifiable stages (with notify fields + flow_key) for the routing table', async () => {
    const wrapper = mount(NotificationsTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    expect(global.fetch).toHaveBeenCalledWith(
      'http://engine/api/accounts/7/flow-config',
      expect.any(Object)
    );
    // Only the notifiable stage is kept; the non-notifiable one is dropped.
    expect(wrapper.vm.notifiableStages).toEqual([
      {
        stage_key: 'order_drafting',
        display_name: 'Order taking',
        flow_key: 'sales',
        notify_enabled: true,
        notify_guidance: '',
      },
    ]);
    // flow-config is not PUT from this tab unless there are pending
    // stage-notify edits (covered in a dedicated test below).
    expect(
      global.fetch.mock.calls.some(
        call => call[0].endsWith('/flow-config') && call[1]?.method === 'PUT'
      )
    ).toBe(false);
  });

  it('editing notifications marks the tab dirty', async () => {
    const wrapper = mount(NotificationsTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    expect(wrapper.text()).not.toContain('UNSAVED_CHANGES');

    wrapper.vm.onNotificationsUpdate({
      channels: ['email'],
      subscriptions: [],
    });
    await wrapper.vm.$nextTick();

    expect(wrapper.text()).toContain('UNSAVED_CHANGES');
  });

  it('blocks saving when a new channel has no bot token, with an inline hint', async () => {
    const wrapper = mount(NotificationsTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    wrapper.vm.onNotificationsUpdate({
      channels: [
        {
          id: 0,
          kind: 'telegram',
          config: { bot_token: '', chat_id: '' },
          enabled: true,
        },
      ],
      subscriptions: [],
    });
    await wrapper.vm.$nextTick();

    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.NEW_CHANNEL_TOKEN_REQUIRED_HINT'
    );
    const saveNotifBtn = wrapper.find(
      '[data-testid="save-notifications-button"]'
    );
    expect(saveNotifBtn.attributes('disabled')).toBe('');
  });

  it('allows saving once the new channel has a bot token', async () => {
    const wrapper = mount(NotificationsTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    wrapper.vm.onNotificationsUpdate({
      channels: [
        {
          id: 0,
          kind: 'telegram',
          config: { bot_token: 'brand-new-token', chat_id: '' },
          enabled: true,
        },
      ],
      subscriptions: [],
    });
    await wrapper.vm.$nextTick();

    const saveNotifBtn = wrapper.find(
      '[data-testid="save-notifications-button"]'
    );
    expect(saveNotifBtn.attributes('disabled')).toBeUndefined();
  });

  it('saves via PUT and clears the dirty flag on success', async () => {
    const wrapper = mount(NotificationsTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    wrapper.vm.onNotificationsUpdate({
      channels: [],
      subscriptions: [],
      muted_events: ['resolved'],
    });
    await wrapper.vm.$nextTick();
    expect(wrapper.vm.notificationsDirty).toBe(true);

    await wrapper.vm.saveNotifications();
    await flushPromises();

    const putCall = global.fetch.mock.calls.find(
      call => call[0].endsWith('/notifications') && call[1]?.method === 'PUT'
    );
    expect(putCall).toBeTruthy();
    const body = JSON.parse(putCall[1].body);
    expect(body.muted_events).toEqual(['resolved']);
    expect(wrapper.vm.notificationsDirty).toBe(false);
  });

  it('clicking a placeholder chip on a Default-routed row inserts the token instead of resetting the template field', async () => {
    // Regression: NotificationsTab.onNotificationsUpdate replaces
    // `notifications.value` with a brand-new object on every
    // update:notifications emit. NotificationsEditor's seedRoutes runs off a
    // deep watcher on that prop, so a chip click (which itself calls
    // emitUpdate()) triggers a re-seed of every route row via this parent
    // round-trip. If the inserted token isn't preserved across that re-seed,
    // the click appears to clear the field — this only reproduces through
    // the real parent/child prop cycle, not against an isolated
    // NotificationsEditor mount with a stable prop reference.
    const wrapper = mount(NotificationsTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    const rows = wrapper.findAll('[data-testid="routing-row"]');
    // First row is `new_order`, seeded to Default with an empty template.
    const templateInput = rows[0].find(
      'textarea[data-testid="route-template-input"]'
    );
    expect(templateInput.element.value).toBe('');

    const chips = rows[0].findAll('[data-testid="template-chip"]');
    const itemsChip = chips.find(c => c.text().includes('CHIP_ITEMS'));
    await itemsChip.trigger('click');
    await wrapper.vm.$nextTick();

    const updatedRows = wrapper.findAll('[data-testid="routing-row"]');
    const updatedTemplateInput = updatedRows[0].find(
      'textarea[data-testid="route-template-input"]'
    );
    expect(updatedTemplateInput.element.value).toBe('{items}');

    expect(wrapper.vm.notifications.subscriptions).toEqual([
      { event: 'new_order', channel_index: null, template: '{items}' },
    ]);
  });

  it('still renders the new_order/handoff/resolved routing rows when the flow-config fetch fails', async () => {
    global.fetch = vi.fn((url, opts) => {
      if (url.endsWith('/flow-config')) {
        return Promise.resolve({
          ok: false,
          status: 500,
          json: () => Promise.resolve({}),
          text: () => Promise.resolve('server error'),
        });
      }
      if (url.endsWith('/notifications') && opts?.method === 'PUT') {
        return Promise.resolve({
          ok: true,
          status: 200,
          json: () =>
            Promise.resolve({
              channels: [],
              subscriptions: [],
              muted_events: [],
            }),
          text: () => Promise.resolve(''),
        });
      }
      return Promise.resolve({
        ok: true,
        status: 200,
        json: () =>
          Promise.resolve({
            channels: [],
            subscriptions: [],
            muted_events: [],
          }),
        text: () => Promise.resolve(''),
      });
    });

    const wrapper = mount(NotificationsTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    // The fixed events (new_order/handoff/resolved) don't depend on
    // flow-config, so the routing table still renders them even though the
    // notifiable-stages fetch failed.
    expect(wrapper.vm.notifiableStages).toEqual([]);
    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.EVENT_NEW_ORDER'
    );
    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.EVENT_HANDOFF'
    );
    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.EVENT_RESOLVED'
    );
    const routingRows = wrapper.findAll('[data-testid="routing-row"]');
    expect(routingRows).toHaveLength(3);
  });

  it('notificationsDirty is a computed comparison against the loaded baseline: true after an edit, false again once reverted by hand', async () => {
    const wrapper = mount(NotificationsTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    expect(wrapper.vm.notificationsDirty).toBe(false);

    wrapper.vm.onNotificationsUpdate({
      channels: [],
      subscriptions: [],
      muted_events: ['resolved'],
    });
    await wrapper.vm.$nextTick();

    expect(wrapper.vm.notificationsDirty).toBe(true);

    // Revert by hand back to the loaded value (empty muted_events). Because
    // the flag is a computed diff against the baseline (not a one-way
    // latch), it must clear again instead of staying stuck.
    wrapper.vm.onNotificationsUpdate({
      channels: [],
      subscriptions: [],
      muted_events: [],
    });
    await wrapper.vm.$nextTick();

    expect(wrapper.vm.notificationsDirty).toBe(false);
  });

  // ── Stage-notify dual save ──
  it('a stageNotify edit marks the tab dirty even with no other notification changes', async () => {
    const wrapper = mount(NotificationsTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    expect(wrapper.vm.notificationsDirty).toBe(false);

    wrapper.vm.onStageNotify({
      stage_key: 'order_drafting',
      notify_enabled: false,
    });
    await wrapper.vm.$nextTick();

    expect(wrapper.vm.notificationsDirty).toBe(true);
  });

  it('saveNotifications also PUTs /flow-config with the pending stage-notify edits and expected_version_id', async () => {
    const wrapper = mount(NotificationsTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    wrapper.vm.onStageNotify({
      stage_key: 'order_drafting',
      notify_enabled: false,
      notify_guidance: 'quiet please',
    });
    await wrapper.vm.$nextTick();

    await wrapper.vm.saveNotifications();
    await flushPromises();

    const notifPutCall = global.fetch.mock.calls.find(
      call => call[0].endsWith('/notifications') && call[1]?.method === 'PUT'
    );
    expect(notifPutCall).toBeTruthy();

    const flowPutCall = global.fetch.mock.calls.find(
      call => call[0].endsWith('/flow-config') && call[1]?.method === 'PUT'
    );
    expect(flowPutCall).toBeTruthy();
    const body = JSON.parse(flowPutCall[1].body);
    expect(body.expected_version_id).toBe(42);
    expect(body.stages).toEqual([
      {
        flow_key: 'sales',
        stage_key: 'order_drafting',
        notify_enabled: false,
        notify_guidance: 'quiet please',
      },
    ]);
  });

  it('does not PUT /flow-config when there are no pending stage-notify edits', async () => {
    const wrapper = mount(NotificationsTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    wrapper.vm.onNotificationsUpdate({
      channels: [],
      subscriptions: [],
      muted_events: ['resolved'],
    });
    await wrapper.vm.$nextTick();

    await wrapper.vm.saveNotifications();
    await flushPromises();

    expect(
      global.fetch.mock.calls.some(
        call => call[0].endsWith('/flow-config') && call[1]?.method === 'PUT'
      )
    ).toBe(false);
  });

  it('clears stageNotifyDraft and reloads after a successful dual save', async () => {
    const wrapper = mount(NotificationsTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    wrapper.vm.onStageNotify({
      stage_key: 'order_drafting',
      notify_enabled: false,
    });
    await wrapper.vm.$nextTick();
    expect(wrapper.vm.notificationsDirty).toBe(true);

    await wrapper.vm.saveNotifications();
    await flushPromises();

    expect(wrapper.vm.notificationsDirty).toBe(false);
  });

  it('handles a 409 on the flow-config PUT like DiscoveryFlowTab: alerts, reloads, and drops the local stage-notify edits', async () => {
    mockFetch({
      flowConfigPutResponse: {
        ok: false,
        status: 409,
        json: () => Promise.resolve({}),
        text: () => Promise.resolve('conflict'),
      },
    });

    const wrapper = mount(NotificationsTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    wrapper.vm.onStageNotify({
      stage_key: 'order_drafting',
      notify_enabled: false,
    });
    await wrapper.vm.$nextTick();

    useAlert.mockClear();
    await wrapper.vm.saveNotifications();
    await flushPromises();

    // Local stage-notify edits are dropped after the reload triggered by 409.
    expect(wrapper.vm.notificationsDirty).toBe(false);

    // The 409 handler already alerted about the conflict; saveNotifications
    // must not additionally (and falsely) report success.
    expect(useAlert).toHaveBeenCalledWith(
      'COMVOR_SETTINGS.DISCOVERY.VERSION_CONFLICT_RELOADED'
    );
    expect(useAlert).not.toHaveBeenCalledWith(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.SAVE_SUCCESS'
    );
  });

  it('a non-409 flow-config failure retains the stage draft and reports a stage-specific error, not a notifications-save error', async () => {
    mockFetch({
      flowConfigPutResponse: {
        ok: false,
        status: 500,
        json: () => Promise.resolve({}),
        text: () => Promise.resolve('server error'),
      },
    });

    const wrapper = mount(NotificationsTab, {
      props: { accountId: '7', engineUrl: 'http://engine' },
      global: { stubs: { 'woot-button': true, 'fluent-icon': true } },
    });
    await flushPromises();

    wrapper.vm.onStageNotify({
      stage_key: 'order_drafting',
      notify_enabled: false,
    });
    await wrapper.vm.$nextTick();

    useAlert.mockClear();
    await wrapper.vm.saveNotifications();
    await flushPromises();

    // /notifications actually succeeded, so the error shown must not claim
    // notifications failed — it must be the stage-specific message.
    expect(useAlert).toHaveBeenCalledWith(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.STAGE_SAVE_ERROR'
    );
    expect(useAlert).not.toHaveBeenCalledWith(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.SAVE_ERROR'
    );
    expect(useAlert).not.toHaveBeenCalledWith(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.SAVE_SUCCESS'
    );

    // The stage draft must be retained so a re-save can retry just the
    // stage part, and the dirty flag must reflect that.
    expect(wrapper.vm.stageNotifyDraft).toEqual({
      order_drafting: expect.objectContaining({
        stage_key: 'order_drafting',
        notify_enabled: false,
      }),
    });
    expect(wrapper.vm.notificationsDirty).toBe(true);
  });
});
