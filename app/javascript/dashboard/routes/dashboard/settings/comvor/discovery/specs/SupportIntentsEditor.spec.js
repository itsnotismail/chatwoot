import { mount } from '@vue/test-utils';
import SupportIntentsEditor from '../SupportIntentsEditor.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

function baseFlow(overrides = {}) {
  return {
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
        has_action: true,
        notifiable: true,
        notify_enabled: false,
        notify_guidance: '',
        on_complete: 'handoff',
        skipped: false,
        in_scope: true,
      },
      {
        stage_key: 'order_status',
        display_name: 'Order status',
        description: 'Answers order status questions',
        guidance: '',
        action_tool: '',
        has_action: false,
        notifiable: false,
        notify_enabled: false,
        notify_guidance: '',
        on_complete: 'resolve',
        skipped: true,
        in_scope: false,
      },
    ],
    ...overrides,
  };
}

function mountEditor(props = {}) {
  return mount(SupportIntentsEditor, {
    props: { flow: baseFlow(), walls: [], ...props },
  });
}

describe('SupportIntentsEditor.vue', () => {
  it('toggling the enable checkbox off emits a skipped-only payload', async () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="intent-row"]');
    const toggle = rows[0].find('[data-testid="enable-toggle"]');
    await toggle.setValue(false);

    const emitted = wrapper.emitted('update:stage');
    expect(emitted).toBeTruthy();
    const last = emitted[emitted.length - 1][0];
    expect(last).toMatchObject({
      flow_key: 'support',
      stage_key: 'refund_request',
      skipped: true,
    });
    expect(Object.keys(last).sort()).toEqual(
      ['flow_key', 'stage_key', 'skipped'].sort()
    );
  });

  it('toggling the enable checkbox on (for a skipped intent) emits a skipped-only payload', async () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="intent-row"]');
    const toggle = rows[1].find('[data-testid="enable-toggle"]');
    await toggle.setValue(true);

    const emitted = wrapper.emitted('update:stage');
    const last = emitted[emitted.length - 1][0];
    expect(last).toMatchObject({
      flow_key: 'support',
      stage_key: 'order_status',
      skipped: false,
    });
    expect(Object.keys(last).sort()).toEqual(
      ['flow_key', 'stage_key', 'skipped'].sort()
    );
  });

  it('disabled (skipped) intents render collapsed and muted, without expandable controls', () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="intent-row"]');
    const skippedRow = rows[1];
    expect(skippedRow.classes()).toContain('opacity-60');
    expect(
      skippedRow.find('[data-testid="who-completes-select"]').exists()
    ).toBe(false);
    expect(skippedRow.find('[data-testid="guidance-textarea"]').exists()).toBe(
      false
    );
  });

  it('clicking an enabled row expands it and shows the who-completes select, finish radios, and guidance', async () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="intent-row"]');
    const enabledRow = rows[0];
    expect(
      enabledRow.find('[data-testid="who-completes-select"]').exists()
    ).toBe(false);

    await enabledRow.find('[data-testid="row-expand-toggle"]').trigger('click');

    expect(
      enabledRow.find('[data-testid="who-completes-select"]').exists()
    ).toBe(true);
    expect(
      enabledRow.find('[data-testid="finish-handoff-radio"]').exists()
    ).toBe(true);
    expect(enabledRow.find('[data-testid="guidance-textarea"]').exists()).toBe(
      true
    );
  });

  it('emits action_mode only when the who-completes select changes', async () => {
    const wrapper = mountEditor();
    const row = wrapper.findAll('[data-testid="intent-row"]')[0];
    await row.find('[data-testid="row-expand-toggle"]').trigger('click');

    const select = row.find('[data-testid="who-completes-select"]');
    await select.setValue('deferred');

    const emitted = wrapper.emitted('update:stage');
    const last = emitted[emitted.length - 1][0];
    expect(last).toMatchObject({
      flow_key: 'support',
      stage_key: 'refund_request',
      action_mode: 'deferred',
    });
    expect(Object.keys(last).sort()).toEqual(
      ['flow_key', 'stage_key', 'action_mode'].sort()
    );
  });

  it('emits on_complete only when the finish radio changes', async () => {
    const wrapper = mountEditor();
    const row = wrapper.findAll('[data-testid="intent-row"]')[0];
    await row.find('[data-testid="row-expand-toggle"]').trigger('click');

    const radio = row.find('[data-testid="finish-resolve-radio"]');
    await radio.setValue(true);

    const emitted = wrapper.emitted('update:stage');
    const last = emitted[emitted.length - 1][0];
    expect(last).toMatchObject({
      flow_key: 'support',
      stage_key: 'refund_request',
      on_complete: 'resolve',
    });
    expect(Object.keys(last).sort()).toEqual(
      ['flow_key', 'stage_key', 'on_complete'].sort()
    );
  });

  it('renders a pointer to the Notifications tab for a notifiable intent, with no notify toggle', async () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="intent-row"]');
    const notifiableRow = rows[0]; // refund_request: notifiable true
    await notifiableRow
      .find('[data-testid="row-expand-toggle"]')
      .trigger('click');

    const pointer = notifiableRow.find('[data-testid="notify-moved-pointer"]');
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

  it('renders the special-instructions helper text and emits guidance only, capped at 2000', async () => {
    const wrapper = mountEditor();
    const row = wrapper.findAll('[data-testid="intent-row"]')[0];
    await row.find('[data-testid="row-expand-toggle"]').trigger('click');

    expect(row.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.GUIDANCE_HINT'
    );
    const textarea = row.find('[data-testid="guidance-textarea"]');
    expect(textarea.attributes('maxlength')).toBe('2000');

    await textarea.setValue('always ask for a photo of the damaged item');
    const emitted = wrapper.emitted('update:stage');
    const last = emitted[emitted.length - 1][0];
    expect(last).toMatchObject({
      flow_key: 'support',
      stage_key: 'refund_request',
      guidance: 'always ask for a photo of the damaged item',
    });
    expect(Object.keys(last).sort()).toEqual(
      ['flow_key', 'stage_key', 'guidance'].sort()
    );
  });

  it('a read wall (has_action false) keeps the enable checkbox usable so the intent can be turned off, and shows the connector pointer', async () => {
    const flow = baseFlow();
    // Enabled read-walled intent: the wall blocks publish, but the merchant
    // must still be able to untick it to clear the wall (turning it off drops
    // the capability requirement) — the checkbox must NOT be disabled.
    flow.stages[1].has_action = false;
    flow.stages[1].skipped = false;
    const walls = [
      {
        flow_key: 'support',
        stage_key: 'order_status',
        capability: 'order.read',
        kind: 'hard',
        message: 'no connector provides order.read',
      },
    ];
    const wrapper = mountEditor({ flow, walls });
    const row = wrapper.findAll('[data-testid="intent-row"]')[1];

    const toggle = row.find('[data-testid="enable-toggle"]');
    expect(toggle.attributes('disabled')).toBeUndefined();
    expect(row.text()).toContain('no connector provides order.read');
    expect(row.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.READ_WALL_POINTER'
    );

    // Unticking it (the fix for the wall) emits a skipped-only payload.
    await toggle.setValue(false);
    const emitted = wrapper.emitted('update:stage');
    const last = emitted[emitted.length - 1][0];
    expect(last).toMatchObject({
      flow_key: 'support',
      stage_key: 'order_status',
      skipped: true,
    });
  });

  it('an action wall (has_action true) keeps the row fully editable and shows a badge', async () => {
    const flow = baseFlow();
    flow.stages[0].has_action = true;
    const walls = [
      {
        flow_key: 'support',
        stage_key: 'refund_request',
        capability: 'refund.create',
        kind: 'hard',
        message: 'no connector provides refund.create',
      },
    ];
    const wrapper = mountEditor({ flow, walls });
    const row = wrapper.findAll('[data-testid="intent-row"]')[0];

    expect(
      row.find('[data-testid="enable-toggle"]').attributes('disabled')
    ).toBeUndefined();

    await row.find('[data-testid="row-expand-toggle"]').trigger('click');
    expect(row.find('[data-testid="action-wall-badge"]').exists()).toBe(true);
    expect(row.text()).toContain('no connector provides refund.create');

    const controls = row.findAll('select, textarea, input');
    controls.forEach(control => {
      expect(control.attributes('disabled')).toBeUndefined();
    });
  });

  it('re-seeds cleanly when the flow prop is replaced with a new stage set (no crash, controls reflect new values)', async () => {
    const wrapper = mountEditor();
    // Expand + interact with the original stage set first.
    const rows = wrapper.findAll('[data-testid="intent-row"]');
    await rows[0].find('[data-testid="row-expand-toggle"]').trigger('click');
    expect(wrapper.find('[data-testid="guidance-textarea"]').exists()).toBe(
      true
    );

    const newFlow = baseFlow({
      stages: [
        {
          stage_key: 'warranty_claim',
          display_name: 'Warranty claim',
          description: 'Handles warranty claims',
          guidance: 'ask for proof of purchase',
          action_tool: '',
          has_action: false,
          notifiable: false,
          notify_enabled: false,
          notify_guidance: '',
          on_complete: 'resolve',
          skipped: false,
          in_scope: true,
        },
      ],
    });

    await wrapper.setProps({ flow: newFlow });
    await wrapper.vm.$nextTick();

    const newRows = wrapper.findAll('[data-testid="intent-row"]');
    expect(newRows).toHaveLength(1);
    expect(newRows[0].text()).toContain('Warranty claim');
    // New stage set starts collapsed again (fresh reactive() re-seed), and
    // toggling it still emits correctly — no stale state from the old flow.
    expect(newRows[0].find('[data-testid="guidance-textarea"]').exists()).toBe(
      false
    );

    const toggle = newRows[0].find('[data-testid="enable-toggle"]');
    await toggle.setValue(false);
    const emitted = wrapper.emitted('update:stage');
    const last = emitted[emitted.length - 1][0];
    expect(last).toMatchObject({
      flow_key: 'support',
      stage_key: 'warranty_claim',
      skipped: true,
    });
  });
});
