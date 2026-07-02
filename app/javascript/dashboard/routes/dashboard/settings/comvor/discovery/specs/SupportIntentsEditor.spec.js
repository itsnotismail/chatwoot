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

  it('shows the notify toggle only when notifiable, and emits notify_enabled only', async () => {
    const wrapper = mountEditor();
    const rows = wrapper.findAll('[data-testid="intent-row"]');
    const row = rows[0]; // notifiable: true
    await row.find('[data-testid="row-expand-toggle"]').trigger('click');

    const toggle = row.find('[data-testid="notify-toggle"]');
    expect(toggle.exists()).toBe(true);
    expect(row.find('[data-testid="notify-guidance-input"]').exists()).toBe(
      false
    );

    await toggle.setValue(true);
    const emitted = wrapper.emitted('update:stage');
    const last = emitted[emitted.length - 1][0];
    expect(last).toMatchObject({
      flow_key: 'support',
      stage_key: 'refund_request',
      notify_enabled: true,
    });
    expect(Object.keys(last).sort()).toEqual(
      ['flow_key', 'stage_key', 'notify_enabled'].sort()
    );
  });

  it('emits notify_guidance only when the include-input changes', async () => {
    const flow = baseFlow();
    flow.stages[0].notify_enabled = true;
    const wrapper = mountEditor({ flow });
    const row = wrapper.findAll('[data-testid="intent-row"]')[0];
    await row.find('[data-testid="row-expand-toggle"]').trigger('click');

    const input = row.find('[data-testid="notify-guidance-input"]');
    expect(input.exists()).toBe(true);
    expect(input.attributes('maxlength')).toBe('500');
    await input.setValue('include the order number');

    const emitted = wrapper.emitted('update:stage');
    const last = emitted[emitted.length - 1][0];
    expect(last).toMatchObject({
      flow_key: 'support',
      stage_key: 'refund_request',
      notify_guidance: 'include the order number',
    });
    expect(Object.keys(last).sort()).toEqual(
      ['flow_key', 'stage_key', 'notify_guidance'].sort()
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

  it('a read wall (has_action false) disables the row and shows the connector pointer', () => {
    const flow = baseFlow();
    flow.stages[1].has_action = false;
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

    expect(
      row.find('[data-testid="enable-toggle"]').attributes('disabled')
    ).toBeDefined();
    expect(row.text()).toContain('no connector provides order.read');
    expect(row.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.READ_WALL_POINTER'
    );
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
});
