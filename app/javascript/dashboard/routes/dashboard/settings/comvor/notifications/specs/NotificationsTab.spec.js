import { flushPromises, mount } from '@vue/test-utils';
import NotificationsTab from '../NotificationsTab.vue';

// Minimal i18n + store + alert mocks (components use these composables).
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentUser: { access_token: 'tok' } } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

function mockFetch({ putResponse } = {}) {
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
    if (url.endsWith('/flow-config')) {
      return Promise.resolve({
        ok: true,
        status: 200,
        json: () =>
          Promise.resolve({
            flows: [
              {
                flow_key: 'sales',
                stages: [
                  {
                    stage_key: 'order_drafting',
                    display_name: 'Order taking',
                    notifiable: true,
                  },
                  {
                    stage_key: 'discovery',
                    display_name: 'Discovery',
                    notifiable: false,
                  },
                ],
              },
            ],
          }),
        text: () => Promise.resolve(''),
      });
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

  it('also fetches flow-config (read-only) and derives notifiable stages for the routing table', async () => {
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
      { stage_key: 'order_drafting', display_name: 'Order taking' },
    ]);
    // flow-config is never PUT from this tab.
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

  it('still renders the handoff/resolved routing rows when the flow-config fetch fails', async () => {
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

    // The fixed events (handoff/resolved) don't depend on flow-config, so
    // the routing table still renders them even though the notifiable-stages
    // fetch failed.
    expect(wrapper.vm.notifiableStages).toEqual([]);
    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.EVENT_HANDOFF'
    );
    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.EVENT_RESOLVED'
    );
    const routingRows = wrapper.findAll('[data-testid="routing-row"]');
    expect(routingRows).toHaveLength(2);
  });
});
