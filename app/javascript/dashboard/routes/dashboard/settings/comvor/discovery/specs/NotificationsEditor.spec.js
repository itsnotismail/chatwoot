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

  it('shows the Set as default affordance for a non-default channel and the Default pill for the default one', () => {
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

    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.DEFAULT_LABEL'
    );
    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.SET_DEFAULT_LABEL'
    );
  });

  it('shows the enabled hint text next to the enabled checkbox', () => {
    const wrapper = mountEditor();
    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.ENABLED_HINT'
    );
  });

  it('preserves all five channel-card testids per channel', () => {
    const wrapper = mountEditor();
    expect(wrapper.find('[data-testid="channel-default-radio"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="channel-bot-token-input"]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-testid="channel-chat-id-input"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="channel-enabled-checkbox"]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-testid="remove-channel-button"]').exists()).toBe(
      true
    );
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
    // new_order, handoff, resolved, order_drafting, payment_fulfillment
    expect(rows).toHaveLength(5);
    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.EVENT_NEW_ORDER'
    );
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

  it('a fixed event (new_order/handoff/resolved) with no subscription and not muted defaults to the Default option', () => {
    const wrapper = mountEditor();
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    expect(selects[0].element.value).toBe('default');
    expect(selects[1].element.value).toBe('default');
    expect(selects[2].element.value).toBe('default');
  });

  it('a stage row with notify_enabled=false seeds to Off', () => {
    const wrapper = mountEditor();
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    // Fourth row is order_drafting (notify_enabled: false in fixture).
    expect(selects[3].element.value).toBe('off');
  });

  it('a stage row with notify_enabled=true and no subscription seeds to Default', () => {
    const wrapper = mountEditor();
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    // Fifth row is payment_fulfillment (notify_enabled: true in fixture).
    expect(selects[4].element.value).toBe('default');
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
    // Second row is `handoff`; route it to channel index 1.
    await selects[1].setValue('1');

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
    // Third row is `resolved`; select Off.
    await selects[2].setValue('off');

    const lastEvent = lastEmitted(wrapper);
    expect(lastEvent.muted_events).toEqual(['resolved']);
    expect(lastEvent.subscriptions).toEqual([]);
  });

  it('a stage-completion row routes to stage:<stage_key>', async () => {
    const wrapper = mountEditor();
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    // Fourth row is the first notifiable stage (order_drafting).
    await selects[3].setValue('0');

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
    // Fourth row is order_drafting (starts at Off).
    await selects[3].setValue('default');

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
    // Fifth row is payment_fulfillment (starts at Default).
    await selects[4].setValue('off');

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
    await selects[3].setValue('0');

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

  it('shows a template override field for a Default-routed row (not just a channel)', () => {
    const wrapper = mountEditor();
    // First row (new_order) starts at Default.
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    expect(rows[0].find('[data-testid="route-template-input"]').exists()).toBe(
      true
    );
  });

  it('does not show a template override field for an Off-routed row', () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    // Fourth row is order_drafting, seeded to Off.
    expect(rows[3].find('[data-testid="route-template-input"]').exists()).toBe(
      false
    );
  });

  it('shows a template override input when a specific channel is chosen', async () => {
    const wrapper = mountEditor();
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    await selects[0].setValue('0');

    const rows = wrapper.findAll('[data-testid="routing-row"]');
    const templateInput = rows[0].find(
      'textarea[data-testid="route-template-input"]'
    );
    expect(templateInput.exists()).toBe(true);

    await templateInput.setValue('custom template {stage}');
    const lastEvent = lastEmitted(wrapper);
    expect(lastEvent.subscriptions[0].template).toBe('custom template {stage}');
  });

  it('a Default route with a non-empty template emits a subscription with channel_index null', async () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    const templateInput = rows[0].find(
      'textarea[data-testid="route-template-input"]'
    );
    await templateInput.setValue('custom default template');

    const lastEvent = lastEmitted(wrapper);
    expect(lastEvent.subscriptions).toEqual([
      {
        event: 'new_order',
        channel_index: null,
        template: 'custom default template',
      },
    ]);
  });

  it('a Default route with a blank template emits no subscription', async () => {
    const wrapper = mountEditor();
    // Trigger an emit by touching an unrelated field (chat ID), then confirm
    // the still-blank new_order row (Default route) has no subscription.
    const chatIdInput = wrapper.find(
      'input[data-testid="channel-chat-id-input"]'
    );
    await chatIdInput.setValue('123');

    const lastEvent = lastEmitted(wrapper);
    expect(lastEvent.subscriptions.some(s => s.event === 'new_order')).toBe(
      false
    );
  });

  it('selecting Off for new_order PUTs it into muted_events with no subscription', async () => {
    const wrapper = mountEditor();
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    // First row is `new_order`; select Off.
    await selects[0].setValue('off');

    const lastEvent = lastEmitted(wrapper);
    expect(lastEvent.muted_events).toEqual(['new_order']);
    expect(lastEvent.subscriptions).toEqual([]);
  });

  it('a Default+template route for new_order emits a null-channel subscription', async () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    const templateInput = rows[0].find(
      'textarea[data-testid="route-template-input"]'
    );
    await templateInput.setValue('custom order template {items}');

    const lastEvent = lastEmitted(wrapper);
    expect(lastEvent.subscriptions).toEqual([
      {
        event: 'new_order',
        channel_index: null,
        template: 'custom order template {items}',
      },
    ]);
  });

  it('seeds a Default route with a template from a channel_id: null subscription', () => {
    const wrapper = mountEditor({
      notifications: baseNotifications({
        subscriptions: [
          {
            event: 'handoff',
            channel_id: null,
            template: 'default-routed custom',
          },
        ],
      }),
    });
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    // Second row is `handoff`.
    const select = rows[1].find('select[data-testid="route-channel-select"]');
    expect(select.element.value).toBe('default');
    const templateInput = rows[1].find(
      'textarea[data-testid="route-template-input"]'
    );
    expect(templateInput.element.value).toBe('default-routed custom');
  });

  // ── Placeholder chips ──
  it('renders the new_order event chip set (Items/Address/Phone/Payment/Summary/Link)', () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    const chips = rows[0].findAll('[data-testid="template-chip"]');
    const labels = chips.map(c => c.text());
    expect(labels).toEqual(
      expect.arrayContaining([
        'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHIP_ITEMS',
        'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHIP_ADDRESS',
        'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHIP_PHONE',
        'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHIP_PAYMENT',
        'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHIP_SUMMARY',
        'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHIP_LINK',
      ])
    );
  });

  it('renders the handoff event chip set (Reason/Link only, no order chips)', () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    const chips = rows[1].findAll('[data-testid="template-chip"]');
    const labels = chips.map(c => c.text());
    expect(labels).toEqual([
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHIP_REASON',
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHIP_LINK',
    ]);
  });

  it('renders the resolved event chip set (Summary/Link only)', () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    const chips = rows[2].findAll('[data-testid="template-chip"]');
    const labels = chips.map(c => c.text());
    expect(labels).toEqual([
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHIP_SUMMARY',
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHIP_LINK',
    ]);
  });

  it('renders the stage-completion event chip set (Stage/Summary/Link)', () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    // Fifth row is payment_fulfillment (Default, not Off).
    const chips = rows[4].findAll('[data-testid="template-chip"]');
    const labels = chips.map(c => c.text());
    expect(labels).toEqual([
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHIP_STAGE',
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHIP_SUMMARY',
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHIP_LINK',
    ]);
  });

  it('typing directly into the template field persists the value and round-trips it', async () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    const templateInput = rows[0].find(
      'textarea[data-testid="route-template-input"]'
    );
    await templateInput.setValue('typed template {items}');

    expect(templateInput.element.value).toBe('typed template {items}');
    const lastEvent = lastEmitted(wrapper);
    expect(lastEvent.subscriptions).toEqual([
      {
        event: 'new_order',
        channel_index: null,
        template: 'typed template {items}',
      },
    ]);
  });

  it('clicking a chip inserts its token at the cursor position in that row template', async () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    // Second row is `handoff`.
    const templateInput = rows[1].find(
      'textarea[data-testid="route-template-input"]'
    );
    await templateInput.setValue('before  after');
    const el = templateInput.element;
    el.selectionStart = 7;
    el.selectionEnd = 7;

    const chips = rows[1].findAll('[data-testid="template-chip"]');
    const linkChip = chips.find(c => c.text().includes('CHIP_LINK'));
    await linkChip.trigger('click');

    const lastEvent = lastEmitted(wrapper);
    const sub = lastEvent.subscriptions.find(s => s.event === 'handoff');
    expect(sub.template).toBe('before {link} after');
  });

  // ── Start from default ──
  it('"Start from default" fills the new_order field with the order-layout default template', async () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    // First row is `new_order`.
    const startFromDefaultBtn = rows[0].find(
      '[data-testid="template-start-from-default"]'
    );
    await startFromDefaultBtn.trigger('click');

    const templateInput = rows[0].find(
      'textarea[data-testid="route-template-input"]'
    );
    expect(templateInput.element.value).toBe(
      '🛎️ New order — please finalize with the customer\n{items}\n📍 {address}\n📞 {phone} · 💳 {payment}\n→ {link}'
    );
  });

  it('"Start from default" fills the handoff field with the plain default template (not the order layout)', async () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    // Second row is `handoff`.
    const startFromDefaultBtn = rows[1].find(
      '[data-testid="template-start-from-default"]'
    );
    await startFromDefaultBtn.trigger('click');

    const templateInput = rows[1].find(
      'textarea[data-testid="route-template-input"]'
    );
    expect(templateInput.element.value).toBe(
      '👤 Conversation needs a human ({reason}) → {link}'
    );
  });

  // ── Live preview ──
  it('renders a live preview substituting sample data into the current template', async () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    const templateInput = rows[0].find(
      'textarea[data-testid="route-template-input"]'
    );
    await templateInput.setValue('Order: {items} — {address}');

    const preview = rows[0].find('[data-testid="template-preview"]');
    expect(preview.text()).toContain('123 Example Road');
  });

  it('the new_order preview shows the order block sample via its default template', () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    const preview = rows[0].find('[data-testid="template-preview"]');
    expect(preview.text()).toContain('123 Example Road');
    expect(preview.text()).toContain('7XXXXXX');
  });

  it('the new_order preview populates the payment placeholder (no stray em-dash for a fully-sampled template)', () => {
    // The default template's {payment} segment must resolve to real sample
    // text now that PREVIEW_SAMPLE.payment is populated, not the em-dash
    // fallback (that fallback is covered directly in TemplateEditor's own
    // substitute() unit test below, using a template/sample pair that
    // deliberately omits a value).
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    const preview = rows[0].find('[data-testid="template-preview"]');
    expect(preview.text()).toContain('Bank transfer');
  });

  it('the handoff preview substitutes the {reason} sample into the plain default template', () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    // Second row is `handoff`; its default template includes {reason}.
    const preview = rows[1].find('[data-testid="template-preview"]');
    expect(preview.text()).toContain('customer asked for a human');
    expect(preview.text()).not.toContain('{reason}');
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
    // Second row is `handoff`.
    expect(selects[1].element.value).toBe('0');
    const templateInputs = wrapper.findAll(
      'textarea[data-testid="route-template-input"]'
    );
    expect(templateInputs[1].element.value).toBe('hi');
  });

  it('seeds routing rows from muted_events for fixed events', () => {
    const wrapper = mountEditor({
      notifications: baseNotifications({ muted_events: ['resolved'] }),
    });
    const selects = wrapper.findAll(
      'select[data-testid="route-channel-select"]'
    );
    // Third row is `resolved`.
    expect(selects[2].element.value).toBe('off');
  });

  // ── In-row guidance input for stage rows ──
  it('renders a guidance input for a stage row only when its route is not off', () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    // order_drafting (index 3) starts at Off -> no guidance input.
    expect(rows[3].find('[data-testid="route-guidance-input"]').exists()).toBe(
      false
    );
    // payment_fulfillment (index 4) starts at Default -> guidance input shown.
    expect(rows[4].find('[data-testid="route-guidance-input"]').exists()).toBe(
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
    expect(rows[2].find('[data-testid="route-guidance-input"]').exists()).toBe(
      false
    );
  });

  it('editing the guidance input for a stage row emits update:stageNotify with the new guidance', async () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="routing-row"]');
    const guidanceInput = rows[4].find('[data-testid="route-guidance-input"]');
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
