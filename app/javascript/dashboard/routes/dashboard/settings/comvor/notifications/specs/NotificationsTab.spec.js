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
        json: () => Promise.resolve({ channels: [], subscriptions: [] }),
        text: () => Promise.resolve(''),
      });
    }
    return Promise.resolve({
      ok: true,
      status: 200,
      json: () => Promise.resolve({ channels: [], subscriptions: [] }),
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
    expect(saveNotifBtn.attributes('disabled')).toBe('true');
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
    expect(saveNotifBtn.attributes('disabled')).toBe('false');
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
    });
    await wrapper.vm.$nextTick();
    expect(wrapper.vm.notificationsDirty).toBe(true);

    await wrapper.vm.saveNotifications();
    await flushPromises();

    const putCall = global.fetch.mock.calls.find(
      call => call[0].endsWith('/notifications') && call[1]?.method === 'PUT'
    );
    expect(putCall).toBeTruthy();
    expect(wrapper.vm.notificationsDirty).toBe(false);
  });
});
