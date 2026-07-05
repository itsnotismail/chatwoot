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

  it('renders a pointer to the Notifications tab for a notifiable stage, with no notify toggle', () => {
    const wrapper = mountEditor();
    const cards = wrapper.findAll('[data-testid="stage-card"]');
    // discovery: notifiable false -> no pointer
    expect(cards[0].find('[data-testid="notify-moved-pointer"]').exists()).toBe(
      false
    );
    // order_drafting: notifiable true -> pointer present
    const pointer = cards[1].find('[data-testid="notify-moved-pointer"]');
    expect(pointer.exists()).toBe(true);
    expect(pointer.text()).toBe(
      'COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.NOTIFY_MOVED_POINTER'
    );

    // The old checkbox/guidance controls are gone entirely.
    expect(wrapper.find('[data-testid="notify-toggle"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="notify-guidance-input"]').exists()).toBe(
      false
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

  // The dejargoned automatic-mode wall message (comvor-engine's
  // flowcfg.ValidatePublish, "action wall" branch) reuses the "Who completes
  // this step" select's exact option labels instead of the old internal
  // terms "Automatic mode"/"Confirm-only" (which matched no UI copy). This
  // is a passthrough render (the message string itself is API-provided,
  // like the other wall messages above) — the test pins the integration
  // point and confirms the em dash and quoted labels render intact.
  it('renders the dejargoned automatic-mode wall message verbatim, matching the "Who completes this step" select labels', () => {
    const walls = [
      {
        flow_key: 'sales',
        stage_key: 'order_drafting',
        capability: 'order.draft',
        kind: 'hard',
        message:
          '"Bot completes it" needs a connected system providing order.draft. Choose "Bot prepares, your team completes" instead — or connect one under Connectors.',
      },
    ];
    const wrapper = mountEditor({ walls });
    const card = wrapper.findAll('[data-testid="stage-card"]')[1];
    const whoCompletesOptions = card
      .findAll('[data-testid="who-completes-select"] option')
      .map(o => o.text());
    expect(whoCompletesOptions).toEqual([
      'COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.WHO_COMPLETES_AUTO',
      'COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.WHO_COMPLETES_DEFERRED',
    ]);
    expect(card.text()).toContain(
      '"Bot completes it" needs a connected system providing order.draft. Choose "Bot prepares, your team completes" instead — or connect one under Connectors.'
    );
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
