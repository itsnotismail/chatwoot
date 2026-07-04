import { mount } from '@vue/test-utils';
import NotificationsEditor from '../NotificationsEditor.vue';

// Minimal i18n mock, matching the pattern used in other discovery specs.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => {
      if (
        key === 'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.EVENT_STAGE_COMPLETED'
      ) {
        return `${params.stage} completed`;
      }
      return key;
    },
  }),
}));

const MASK = '********';

const notifiableStages = [
  {
    stage_key: 'order_drafting',
    display_name: 'Order taking',
    flow_key: 'sales',
    notify_enabled: false,
    notify_guidance: '',
  },
  {
    stage_key: 'payment_fulfillment',
    display_name: 'Payment',
    flow_key: 'sales',
    notify_enabled: true,
    notify_guidance: '',
  },
];

function baseNotifications(overrides = {}) {
  return {
    channels: [
      {
        id: 5,
        kind: 'telegram',
        config: { bot_token: MASK, chat_id: '123' },
        enabled: true,
        is_default: true,
      },
    ],
    subscriptions: [],
    muted_events: [],
    ...overrides,
  };
}

function mountEditor(props = {}) {
  return mount(NotificationsEditor, {
    props: {
      notifications: baseNotifications(),
      notifiableStages,
      ...props,
    },
  });
}

function lastEmitted(wrapper) {
  const emitted = wrapper.emitted('update:notifications');
  return emitted[emitted.length - 1][0];
}

function lastStageNotifyEmitted(wrapper) {
  const emitted = wrapper.emitted('update:stageNotify');
  return emitted[emitted.length - 1][0];
}

describe('NotificationsEditor.vue', () => {
  // ── Token behaviors preserved from Task 1 ──
  it('round-trips the sentinel + id for an untouched existing channel', async () => {
    const wrapper = mountEditor();
    const chatIdInput = wrapper.find(
      'input[data-testid="channel-chat-id-input"]'
    );
    await chatIdInput.setValue('123');

    const lastEvent = lastEmitted(wrapper);
    expect(lastEvent.channels[0]).toMatchObject({
      id: 5,
      config: { bot_token: MASK, chat_id: '123' },
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

  it('sends the newly typed token instead of the sentinel when the user edits it', async () => {
    const wrapper = mountEditor();
    const tokenInput = wrapper.find(
      'input[data-testid="channel-bot-token-input"]'
    );
    await tokenInput.setValue('new-secret-token');

    const lastEvent = lastEmitted(wrapper);
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

    const lastEvent = lastEmitted(wrapper);
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

    const lastEvent = lastEmitted(wrapper);
    expect(lastEvent.channels[1]).toMatchObject({
      config: { bot_token: 'brand-new-token' },
    });
  });

  // ── Default star ──
  it('seeds the default radio from is_default and round-trips it on save', () => {
    const wrapper = mountEditor();
    const radio = wrapper.find('input[data-testid="channel-default-radio"]');
    expect(radio.element.checked).toBe(true);
  });

  it('moving the default star to another channel marks that channel is_default and unmarks the rest', async () => {
    const wrapper = mountEditor({
      notifications: baseNotifications({
        channels: [
          {
            id: 5,
            kind: 'telegram',
            config: { bot_token: MASK, chat_id: '123' },
            enabled: true,
            is_default: true,
          },
          {
            id: 6,
            kind: 'telegram',
            config: { bot_token: MASK, chat_id: '456' },
            enabled: true,
            is_default: false,
          },
        ],
      }),
    });

    const radios = wrapper.findAll(
      'input[data-testid="channel-default-radio"]'
    );
    await radios[1].setValue();

    const lastEvent = lastEmitted(wrapper);
    expect(lastEvent.channels[0].is_default).toBe(false);
    expect(lastEvent.channels[1].is_default).toBe(true);
  });

  it('shows a hint when no channel is marked default', () => {
    const wrapper = mountEditor({
      notifications: baseNotifications({
        channels: [
          {
            id: 5,
            kind: 'telegram',
            config: { bot_token: MASK, chat_id: '123' },
            enabled: true,
            is_default: false,
          },
        ],
      }),
    });
    expect(
      wrapper.find('[data-testid="no-default-channel-hint"]').exists()
    ).toBe(true);
  });

  // ── Routing table ──
  it('builds one routing row per fixed event plus one per notifiable stage', () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    // handoff, resolved, order_drafting, payment_fulfillment
    expect(rows).toHaveLength(4);
    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.EVENT_HANDOFF'
    );
    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.EVENT_RESOLVED'
    );
    expect(wrapper.text()).toContain('Order taking completed');
    expect(wrapper.text()).toContain('Payment completed');
  });

  it('renders the two group subheaders and no per-row "Channel" label', () => {
    const wrapper = mountEditor();
    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.GROUP_CONVERSATION'
    );
    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.GROUP_STAGE'
    );
    expect(wrapper.find('[data-testid="route-channel-label"]').exists()).toBe(
      false
    );
  });

  it('a fixed event (handoff/resolved) with no subscription and not muted defaults to the Default option', () => {
    const wrapper = mountEditor();
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    expect(selects[0].element.value).toBe('default');
    expect(selects[1].element.value).toBe('default');
  });

  it('a stage row with notify_enabled=false seeds to Off', () => {
    const wrapper = mountEditor();
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    // Third row is order_drafting (notify_enabled: false in fixture).
    expect(selects[2].element.value).toBe('off');
  });

  it('a stage row with notify_enabled=true and no subscription seeds to Default', () => {
    const wrapper = mountEditor();
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    // Fourth row is payment_fulfillment (notify_enabled: true in fixture).
    expect(selects[3].element.value).toBe('default');
  });

  it('there is no separate Muted option -- Off replaces it', () => {
    const wrapper = mountEditor();
    const select = wrapper.find('select[data-testid="route-channel-select"]');
    const optionValues = select.findAll('option').map(o => o.element.value);
    expect(optionValues).toContain('off');
    expect(optionValues).not.toContain('muted');
  });

  it('selecting a specific channel for a fixed event PUTs a subscription with the correct channel_index', async () => {
    const wrapper = mountEditor({
      notifications: baseNotifications({
        channels: [
          {
            id: 5,
            kind: 'telegram',
            config: { bot_token: MASK, chat_id: '123' },
            enabled: true,
            is_default: true,
          },
          {
            id: 6,
            kind: 'telegram',
            config: { bot_token: MASK, chat_id: '456' },
            enabled: true,
            is_default: false,
          },
        ],
      }),
    });

    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    // First row is `handoff`; route it to channel index 1.
    await selects[0].setValue('1');

    const lastEvent = lastEmitted(wrapper);
    expect(lastEvent.subscriptions).toEqual([
      { event: 'handoff', channel_index: 1, template: '' },
    ]);
    expect(lastEvent.muted_events).toEqual([]);
  });

  it('selecting Off for a fixed event PUTs it into muted_events with no subscription', async () => {
    const wrapper = mountEditor();
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    // Second row is `resolved`; select Off.
    await selects[1].setValue('off');

    const lastEvent = lastEmitted(wrapper);
    expect(lastEvent.muted_events).toEqual(['resolved']);
    expect(lastEvent.subscriptions).toEqual([]);
  });

  it('a stage-completion row routes to stage:<stage_key>', async () => {
    const wrapper = mountEditor();
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    // Third row is the first notifiable stage (order_drafting).
    await selects[2].setValue('0');

    const lastEvent = lastEmitted(wrapper);
    expect(lastEvent.subscriptions).toEqual([
      { event: 'stage:order_drafting', channel_index: 0, template: '' },
    ]);
  });

  it('selecting Default on a stage row emits update:stageNotify with notify_enabled true and no subscription/mute', async () => {
    const wrapper = mountEditor();
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    // Third row is order_drafting (starts at Off).
    await selects[2].setValue('default');

    const stageEvent = lastStageNotifyEmitted(wrapper);
    expect(stageEvent).toMatchObject({
      stage_key: 'order_drafting',
      notify_enabled: true,
    });

    const lastEvent = lastEmitted(wrapper);
    expect(
      lastEvent.subscriptions.some(s => s.event === 'stage:order_drafting')
    ).toBe(false);
    expect(lastEvent.muted_events).not.toContain('stage:order_drafting');
  });

  it('selecting Off on a stage row emits update:stageNotify with notify_enabled false', async () => {
    const wrapper = mountEditor();
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    // Fourth row is payment_fulfillment (starts at Default).
    await selects[3].setValue('off');

    const stageEvent = lastStageNotifyEmitted(wrapper);
    expect(stageEvent).toMatchObject({
      stage_key: 'payment_fulfillment',
      notify_enabled: false,
    });
  });

  it('selecting a channel on a stage row emits both update:stageNotify (enabled) and a subscription', async () => {
    const wrapper = mountEditor({
      notifications: baseNotifications({
        channels: [
          {
            id: 5,
            kind: 'telegram',
            config: { bot_token: MASK, chat_id: '123' },
            enabled: true,
            is_default: true,
          },
        ],
      }),
    });
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    await selects[2].setValue('0');

    const stageEvent = lastStageNotifyEmitted(wrapper);
    expect(stageEvent).toMatchObject({
      stage_key: 'order_drafting',
      notify_enabled: true,
    });
    const lastEvent = lastEmitted(wrapper);
    expect(lastEvent.subscriptions).toEqual([
      { event: 'stage:order_drafting', channel_index: 0, template: '' },
    ]);
  });

  it('shows a template override input only when a specific channel is chosen', async () => {
    const wrapper = mountEditor();
    let templateInputs = wrapper.findAll(
      'input[data-testid="route-template-input"]'
    );
    expect(templateInputs).toHaveLength(0);

    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    await selects[0].setValue('0');

    templateInputs = wrapper.findAll(
      'input[data-testid="route-template-input"]'
    );
    expect(templateInputs).toHaveLength(1);

    await templateInputs[0].setValue('custom template {stage}');
    const lastEvent = lastEmitted(wrapper);
    expect(lastEvent.subscriptions[0].template).toBe('custom template {stage}');
  });

  it('seeds routing rows from an existing subscription', () => {
    const wrapper = mountEditor({
      notifications: baseNotifications({
        subscriptions: [
          { id: 1, event: 'handoff', channel_id: 5, template: 'hi' },
        ],
      }),
    });
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    expect(selects[0].element.value).toBe('0');
    const templateInputs = wrapper.findAll(
      'input[data-testid="route-template-input"]'
    );
    expect(templateInputs[0].element.value).toBe('hi');
  });

  it('seeds routing rows from muted_events for fixed events', () => {
    const wrapper = mountEditor({
      notifications: baseNotifications({ muted_events: ['resolved'] }),
    });
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    expect(selects[1].element.value).toBe('off');
  });

  // ── In-row guidance input for stage rows ──
  it('renders a guidance input for a stage row only when its route is not off', () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    // order_drafting (index 2) starts at Off -> no guidance input.
    expect(rows[2].find('[data-testid="route-guidance-input"]').exists()).toBe(
      false
    );
    // payment_fulfillment (index 3) starts at Default -> guidance input shown.
    expect(rows[3].find('[data-testid="route-guidance-input"]').exists()).toBe(
      true
    );
  });

  it('does not render a guidance input for fixed-event rows', () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    expect(rows[0].find('[data-testid="route-guidance-input"]').exists()).toBe(
      false
    );
    expect(rows[1].find('[data-testid="route-guidance-input"]').exists()).toBe(
      false
    );
  });

  it('editing the guidance input for a stage row emits update:stageNotify with the new guidance', async () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    const guidanceInput = rows[3].find('[data-testid="route-guidance-input"]');
    await guidanceInput.setValue('mention the order total');

    const stageEvent = lastStageNotifyEmitted(wrapper);
    expect(stageEvent).toMatchObject({
      stage_key: 'payment_fulfillment',
      notify_guidance: 'mention the order total',
    });
  });

  // ── Empty state ──
  it('renders the BotFather guide when there are zero channels', () => {
    const wrapper = mountEditor({
      notifications: baseNotifications({ channels: [] }),
    });
    expect(wrapper.find('[data-testid="botfather-empty-state"]').exists()).toBe(
      true
    );
  });

  it('the BotFather guide steps are collapsed until toggled', async () => {
    const wrapper = mountEditor({
      notifications: baseNotifications({ channels: [] }),
    });
    expect(wrapper.find('[data-testid="botfather-guide-steps"]').exists()).toBe(
      false
    );

    await wrapper
      .find('[data-testid="botfather-guide-toggle"]')
      .trigger('click');

    const steps = wrapper.find('[data-testid="botfather-guide-steps"]');
    expect(steps.exists()).toBe(true);
    expect(steps.findAll('li')).toHaveLength(3);
  });

  it('does not render the guide once a channel exists', () => {
    const wrapper = mountEditor();
    expect(wrapper.find('[data-testid="botfather-empty-state"]').exists()).toBe(
      false
    );
  });
});
