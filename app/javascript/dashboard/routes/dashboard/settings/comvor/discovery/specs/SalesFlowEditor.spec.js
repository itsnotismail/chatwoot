import { mount } from '@vue/test-utils';
import SalesFlowEditor from '../SalesFlowEditor.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

function baseFlow(overrides = {}) {
  return {
    flow_key: 'sales',
    mode: 'ordered',
    display_name: 'Sales',
    description: '',
    stages: [
      {
        stage_key: 'discovery',
        display_name: 'Discovery',
        description: 'Answers product questions',
        guidance: 'greet warmly',
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
        description: 'Prepares the order',
        guidance: 'collect items',
        action_tool: 'create_order',
        has_action: true,
        notifiable: true,
        notify_enabled: false,
        notify_guidance: '',
        on_complete: 'handoff',
        in_scope: false,
      },
      {
        stage_key: 'payment_fulfillment',
        display_name: 'Payment',
        description: 'Handles payment',
        guidance: '',
        action_tool: '',
        has_action: false,
        notifiable: true,
        notify_enabled: false,
        notify_guidance: '',
        on_complete: 'continue',
        in_scope: false,
      },
    ],
    ...overrides,
  };
}

function mountEditor(props = {}) {
  return mount(SalesFlowEditor, {
    props: { flow: baseFlow(), walls: [], ...props },
  });
}

describe('SalesFlowEditor.vue', () => {
  it('derives the cutoff as the first stage with a non-continue on_complete', () => {
    const wrapper = mountEditor();
    expect(wrapper.vm.cutoffKey).toBe('order_drafting');
  });

  it('renders bot-zone stages as full cards and post-cutoff stages as slim grey rows', () => {
    const wrapper = mountEditor();
    const cards = wrapper.findAll('[data-testid="stage-card"]');
    expect(cards).toHaveLength(2); // discovery, order_drafting
    const greyed = wrapper.findAll('[data-testid="post-cutoff-row"]');
    expect(greyed).toHaveLength(1); // payment_fulfillment
    expect(greyed[0].text()).toContain('Payment');
    expect(greyed[0].text()).toContain('HANDLED_BY_TEAM');
  });

  it('moving the cutoff to a later stage emits finish for the new cutoff and continue for the old one', async () => {
    const wrapper = mountEditor();
    // Move cutoff from order_drafting -> payment_fulfillment via the strip.
    await wrapper
      .findComponent({ name: 'JourneyStrip' })
      .vm.$emit('selectCutoff', 'payment_fulfillment');

    const emitted = wrapper.emitted('update:stage');
    expect(emitted).toBeTruthy();
    // Exactly two update payloads: new cutoff gets a finish, old cutoff reset to continue.
    const payloads = emitted.map(e => e[0]);
    const newCutoffUpdate = payloads.find(
      p => p.stage_key === 'payment_fulfillment'
    );
    const oldCutoffUpdate = payloads.find(
      p => p.stage_key === 'order_drafting'
    );

    expect(newCutoffUpdate).toMatchObject({
      flow_key: 'sales',
      stage_key: 'payment_fulfillment',
      on_complete: 'handoff', // carries over the previous cutoff's finish choice
    });
    expect(oldCutoffUpdate).toMatchObject({
      flow_key: 'sales',
      stage_key: 'order_drafting',
      on_complete: 'continue',
    });
    // Minimal PUT payloads: only on_complete + identifying keys, nothing else.
    expect(Object.keys(newCutoffUpdate).sort()).toEqual(
      ['flow_key', 'on_complete', 'stage_key'].sort()
    );
    expect(Object.keys(oldCutoffUpdate).sort()).toEqual(
      ['flow_key', 'on_complete', 'stage_key'].sort()
    );
  });

  it('moving the cutoff to an earlier stage resets every other non-continue stage', async () => {
    const wrapper = mountEditor();
    await wrapper
      .findComponent({ name: 'JourneyStrip' })
      .vm.$emit('selectCutoff', 'discovery');

    const payloads = wrapper.emitted('update:stage').map(e => e[0]);
    const newCutoffUpdate = payloads.find(p => p.stage_key === 'discovery');
    const oldCutoffUpdate = payloads.find(
      p => p.stage_key === 'order_drafting'
    );

    expect(newCutoffUpdate.on_complete).toBe('handoff');
    expect(oldCutoffUpdate.on_complete).toBe('continue');
  });

  it('changing the finish radio on the cutoff stage emits only for that stage', async () => {
    const wrapper = mountEditor();
    const resolveRadio = wrapper.find(
      'input[data-testid="finish-resolve-radio"]'
    );
    await resolveRadio.setValue(true);

    const emitted = wrapper.emitted('update:stage');
    const last = emitted[emitted.length - 1][0];
    expect(last).toMatchObject({
      flow_key: 'sales',
      stage_key: 'order_drafting',
      on_complete: 'resolve',
    });
  });

  it('shows the who-completes select only when has_action is true', () => {
    const wrapper = mountEditor();
    const cards = wrapper.findAll('[data-testid="stage-card"]');
    // discovery: has_action false -> no select
    expect(cards[0].find('[data-testid="who-completes-select"]').exists()).toBe(
      false
    );
    // order_drafting: has_action true -> select present
    expect(cards[1].find('[data-testid="who-completes-select"]').exists()).toBe(
      true
    );
  });

  it('emits action_mode when the who-completes select changes', async () => {
    const wrapper = mountEditor();
    const select = wrapper
      .findAll('[data-testid="stage-card"]')[1]
      .find('[data-testid="who-completes-select"]');
    await select.setValue('deferred');

    const emitted = wrapper.emitted('update:stage');
    const last = emitted[emitted.length - 1][0];
    expect(last).toMatchObject({
      flow_key: 'sales',
      stage_key: 'order_drafting',
      action_mode: 'deferred',
    });
  });

  it('shows the notify toggle only when notifiable is true, and the guidance input only once enabled', async () => {
    const wrapper = mountEditor();
    const cards = wrapper.findAll('[data-testid="stage-card"]');
    // discovery: notifiable false -> no toggle
    expect(cards[0].find('[data-testid="notify-toggle"]').exists()).toBe(false);
    // order_drafting: notifiable true -> toggle present
    const toggle = cards[1].find('[data-testid="notify-toggle"]');
    expect(toggle.exists()).toBe(true);
    // notify_guidance input hidden until enabled
    expect(
      cards[1].find('[data-testid="notify-guidance-input"]').exists()
    ).toBe(false);

    await toggle.setValue(true);
    const emitted = wrapper.emitted('update:stage');
    const last = emitted[emitted.length - 1][0];
    expect(last).toMatchObject({
      flow_key: 'sales',
      stage_key: 'order_drafting',
      notify_enabled: true,
    });
    // Only notify_enabled changed -- no other fields in this payload.
    expect(Object.keys(last).sort()).toEqual(
      ['flow_key', 'stage_key', 'notify_enabled'].sort()
    );
  });

  it('emits notify_guidance only (not notify_enabled) when the guidance input changes', async () => {
    const flow = baseFlow();
    flow.stages[1].notify_enabled = true;
    const wrapper = mountEditor({ flow });

    const input = wrapper
      .findAll('[data-testid="stage-card"]')[1]
      .find('[data-testid="notify-guidance-input"]');
    expect(input.exists()).toBe(true);
    await input.setValue('include order total');

    const emitted = wrapper.emitted('update:stage');
    const last = emitted[emitted.length - 1][0];
    expect(last).toMatchObject({
      flow_key: 'sales',
      stage_key: 'order_drafting',
      notify_guidance: 'include order total',
    });
    expect(Object.keys(last).sort()).toEqual(
      ['flow_key', 'stage_key', 'notify_guidance'].sort()
    );
  });

  it('a wall badge is shown on the card but never disables its controls', () => {
    const walls = [
      {
        flow_key: 'sales',
        stage_key: 'order_drafting',
        capability: 'order.draft',
        kind: 'hard',
        message: 'no connector provides order.draft',
      },
    ];
    const wrapper = mountEditor({ walls });
    const card = wrapper.findAll('[data-testid="stage-card"]')[1];
    expect(card.text()).toContain('no connector provides order.draft');
    const controls = card.findAll('select, textarea, input');
    controls.forEach(control => {
      expect(control.attributes('disabled')).toBeUndefined();
    });
  });

  it('guidance textarea is hidden behind an Adjust expander and emits guidance on change', async () => {
    const wrapper = mountEditor();
    const card = wrapper.findAll('[data-testid="stage-card"]')[0];
    expect(card.find('[data-testid="guidance-textarea"]').exists()).toBe(false);

    await card.find('[data-testid="adjust-guidance-toggle"]').trigger('click');
    const textarea = card.find('[data-testid="guidance-textarea"]');
    expect(textarea.exists()).toBe(true);

    await textarea.setValue('new guidance text');
    const emitted = wrapper.emitted('update:stage');
    const last = emitted[emitted.length - 1][0];
    expect(last).toMatchObject({
      flow_key: 'sales',
      stage_key: 'discovery',
      guidance: 'new guidance text',
    });
  });

  it('clicking a post-cutoff row moves the cutoff there', async () => {
    const wrapper = mountEditor();
    await wrapper.find('[data-testid="post-cutoff-row"]').trigger('click');

    const payloads = wrapper.emitted('update:stage').map(e => e[0]);
    expect(
      payloads.some(
        p =>
          p.stage_key === 'payment_fulfillment' && p.on_complete === 'handoff'
      )
    ).toBe(true);
    expect(
      payloads.some(
        p => p.stage_key === 'order_drafting' && p.on_complete === 'continue'
      )
    ).toBe(true);
  });
});
