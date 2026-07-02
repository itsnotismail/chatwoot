import { mount } from '@vue/test-utils';
import NotificationsEditor from '../NotificationsEditor.vue';

// Minimal i18n mock, matching the pattern used in other discovery specs.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const MASK = '********';

const notifications = {
  channels: [
    {
      id: 5,
      kind: 'telegram',
      config: { bot_token: MASK, chat_id: '123' },
      enabled: true,
    },
  ],
  subscriptions: [{ id: 1, event: 'handoff', channel_id: 5, template: '' }],
};

function mountEditor(props = {}) {
  return mount(NotificationsEditor, {
    props: { notifications, ...props },
  });
}

describe('NotificationsEditor.vue', () => {
  it('maps the subscription channel_id to the correct channel_index in the emitted body', async () => {
    const wrapper = mountEditor();
    // Trigger an emit by editing the template textarea (no-op value change still emits).
    const textarea = wrapper.find(
      'textarea[data-testid="subscription-template-input"]'
    );
    await textarea.setValue('hello');

    const emitted = wrapper.emitted('update:notifications');
    expect(emitted).toBeTruthy();
    const lastEvent = emitted[emitted.length - 1][0];
    expect(lastEvent.subscriptions).toHaveLength(1);
    expect(lastEvent.subscriptions[0].channel_index).toBe(0);
    expect(lastEvent.subscriptions[0].event).toBe('handoff');
    expect(lastEvent.channels).toHaveLength(1);
    expect(lastEvent.channels[0]).toMatchObject({
      id: 5,
      kind: 'telegram',
      config: { bot_token: MASK, chat_id: '123' },
      enabled: true,
    });
  });

  it('shows the bot token input empty (not the mask) for an existing masked channel', () => {
    const wrapper = mountEditor();
    const input = wrapper.find('input[data-testid="channel-bot-token-input"]');
    expect(input.element.value).toBe('');
    expect(input.attributes('placeholder')).toBe(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.BOT_TOKEN_SAVED_PLACEHOLDER'
    );
  });

  it('round-trips the sentinel + id for an untouched existing channel', async () => {
    const wrapper = mountEditor();
    // Trigger an emit via an unrelated field change (chat_id), token untouched.
    const chatIdInput = wrapper.find(
      'input[data-testid="channel-chat-id-input"]'
    );
    await chatIdInput.setValue('123');

    const emitted = wrapper.emitted('update:notifications');
    const lastEvent = emitted[emitted.length - 1][0];
    expect(lastEvent.channels[0]).toMatchObject({
      id: 5,
      config: { bot_token: MASK, chat_id: '123' },
    });
  });

  it('sends the newly typed token instead of the sentinel when the user edits it', async () => {
    const wrapper = mountEditor();
    const tokenInput = wrapper.find(
      'input[data-testid="channel-bot-token-input"]'
    );
    await tokenInput.setValue('new-secret-token');

    const emitted = wrapper.emitted('update:notifications');
    const lastEvent = emitted[emitted.length - 1][0];
    expect(lastEvent.channels[0]).toMatchObject({
      id: 5,
      config: { bot_token: 'new-secret-token' },
    });
  });

  it('adds a channel via the add-channel button, growing the local list', async () => {
    const wrapper = mountEditor();
    const addChannelBtn = wrapper.find(
      'button[data-testid="add-channel-button"]'
    );
    await addChannelBtn.trigger('click');

    const channelRows = wrapper.findAll(
      '[data-testid="channel-bot-token-input"]'
    );
    expect(channelRows).toHaveLength(2);
  });

  it('removes a channel via the remove-channel button, shrinking the local list', async () => {
    const wrapper = mountEditor();
    const removeChannelBtn = wrapper.find(
      'button[data-testid="remove-channel-button"]'
    );
    await removeChannelBtn.trigger('click');

    const channelRows = wrapper.findAll(
      '[data-testid="channel-bot-token-input"]'
    );
    expect(channelRows).toHaveLength(0);
  });

  it('a new channel without a token is emitted with an empty bot_token (no sentinel), blocking save', async () => {
    const wrapper = mountEditor();
    const addChannelBtn = wrapper.find(
      'button[data-testid="add-channel-button"]'
    );
    await addChannelBtn.trigger('click');

    const emitted = wrapper.emitted('update:notifications');
    const lastEvent = emitted[emitted.length - 1][0];
    const newChannel = lastEvent.channels[1];
    expect(newChannel.id).toBeFalsy();
    expect(newChannel.config.bot_token).toBe('');
  });

  it('a new channel with a typed token is emitted with that token', async () => {
    const wrapper = mountEditor();
    const addChannelBtn = wrapper.find(
      'button[data-testid="add-channel-button"]'
    );
    await addChannelBtn.trigger('click');

    const tokenInputs = wrapper.findAll(
      'input[data-testid="channel-bot-token-input"]'
    );
    await tokenInputs[1].setValue('brand-new-token');

    const emitted = wrapper.emitted('update:notifications');
    const lastEvent = emitted[emitted.length - 1][0];
    expect(lastEvent.channels[1]).toMatchObject({
      config: { bot_token: 'brand-new-token' },
    });
  });

  it('adds a subscription via the add-subscription button, growing the local list', async () => {
    const wrapper = mountEditor();
    const addSubBtn = wrapper.find(
      'button[data-testid="add-subscription-button"]'
    );
    await addSubBtn.trigger('click');

    const subRows = wrapper.findAll(
      'textarea[data-testid="subscription-template-input"]'
    );
    expect(subRows).toHaveLength(2);
  });

  it('removes a subscription via the remove-subscription button, shrinking the local list', async () => {
    const wrapper = mountEditor();
    const removeSubBtn = wrapper.find(
      'button[data-testid="remove-subscription-button"]'
    );
    await removeSubBtn.trigger('click');

    const subRows = wrapper.findAll(
      'textarea[data-testid="subscription-template-input"]'
    );
    expect(subRows).toHaveLength(0);
  });
});
