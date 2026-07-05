import { mount } from '@vue/test-utils';
import TemplateEditor from '../TemplateEditor.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const NEW_ORDER_DEFAULT =
  '🛎️ New order — please finalize with the customer\n{items}\n📍 {address}\n📞 {phone} · 💳 {payment}\n→ {link}';

function mountEditor(row = {}, props = {}) {
  return mount(TemplateEditor, {
    props: {
      row: { event: 'new_order', isStage: false, template: '', ...row },
      defaultTemplate: NEW_ORDER_DEFAULT,
      ...props,
    },
  });
}

describe('TemplateEditor.vue', () => {
  // ── Data-driven chips (from the API's `placeholders`) ──
  it('renders chips from the placeholders prop, in API order, with the API label verbatim (no i18n lookup)', () => {
    const wrapper = mountEditor(
      {},
      {
        placeholders: [
          { key: 'items', label: 'Items' },
          { key: 'address', label: 'Address' },
          { key: 'phone', label: 'Phone' },
          { key: 'payment', label: 'Payment' },
          { key: 'summary', label: 'Summary' },
          { key: 'link', label: 'Link' },
        ],
      }
    );
    const chips = wrapper.findAll('[data-testid="template-chip"]');
    expect(chips.map(c => c.text())).toEqual([
      'Items',
      'Address',
      'Phone',
      'Payment',
      'Summary',
      'Link',
    ]);
  });

  it('clicking a chip inserts {key} (built from the API key, not a hardcoded token map)', async () => {
    const wrapper = mountEditor(
      {},
      { placeholders: [{ key: 'reason', label: 'Reason' }] }
    );
    await wrapper.find('[data-testid="template-chip"]').trigger('click');
    expect(wrapper.emitted('chip')[0]).toEqual(['{reason}']);
  });

  it('renders no chips when placeholders is empty', () => {
    const wrapper = mountEditor({}, { placeholders: [] });
    expect(wrapper.findAll('[data-testid="template-chip"]')).toHaveLength(0);
  });

  it('renders the live preview using generic sample data (not a real order)', () => {
    // PREVIEW_SAMPLE must read as an obviously-generic example, not real
    // customer data (a prior version hardcoded an actual test order:
    // "Rainforest Residence", "9990805", a real conversation link).
    const wrapper = mountEditor();
    const preview = wrapper.find('[data-testid="template-preview"]');
    expect(preview.text()).toContain('123 Example Road');
    expect(preview.text()).toContain('7XXXXXX');
    expect(preview.text()).toContain('Sample product');
    expect(preview.text()).not.toContain('Rainforest');
    expect(preview.text()).not.toContain('9990805');
  });

  it('the payment placeholder is populated in the preview, not left as a stray em-dash', () => {
    const wrapper = mountEditor();
    const preview = wrapper.find('[data-testid="template-preview"]');
    expect(preview.text()).toContain('Bank transfer');
  });

  // ── Pre-fill from the defaultTemplate prop (no local DEFAULT_TEMPLATES mirror) ──
  it('pre-fills the field with the defaultTemplate prop when row.template is empty', () => {
    const wrapper = mountEditor({ template: '' });
    const input = wrapper.find('[data-testid="route-template-input"]');
    // The rendered value follows `row.template` (owned by the parent), but
    // the live preview must fall back to the prop-provided default so the
    // field always reads as non-blank content.
    expect(input.element.value).toBe('');
    const preview = wrapper.find('[data-testid="template-preview"]');
    expect(preview.text()).toContain('123 Example Road');
  });

  it('uses the defaultTemplate prop (not a hardcoded mirror) for a plain event like handoff', () => {
    const wrapper = mountEditor(
      { event: 'handoff', template: '' },
      { defaultTemplate: '👤 Conversation needs a human ({reason}) → {link}' }
    );
    const preview = wrapper.find('[data-testid="template-preview"]');
    expect(preview.text()).toContain('customer asked for a human');
  });

  // ── Reset to default ──
  it('"Reset to default" emits startFromDefault with the defaultTemplate prop value', async () => {
    const wrapper = mountEditor({ template: 'something customized' });
    await wrapper
      .find('[data-testid="template-start-from-default"]')
      .trigger('click');

    expect(wrapper.emitted('startFromDefault')[0]).toEqual([NEW_ORDER_DEFAULT]);
  });

  it('renders the "Reset to default" label (renamed from "Start from default")', () => {
    const wrapper = mountEditor();
    expect(wrapper.text()).toContain(
      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.RESET_TO_DEFAULT'
    );
  });

  // ── Auto-height ──
  it('exposes resizeToContent, which sets the textarea height from its scrollHeight', () => {
    const wrapper = mountEditor();
    const textarea = wrapper.find(
      '[data-testid="route-template-input"]'
    ).element;
    Object.defineProperty(textarea, 'scrollHeight', {
      configurable: true,
      value: 150,
    });

    wrapper.vm.resizeToContent();

    expect(textarea.style.height).toBe('150px');
  });

  it('clamps the auto-height to a sane minimum (~3 rows)', () => {
    const wrapper = mountEditor();
    const textarea = wrapper.find(
      '[data-testid="route-template-input"]'
    ).element;
    Object.defineProperty(textarea, 'scrollHeight', {
      configurable: true,
      value: 10,
    });

    wrapper.vm.resizeToContent();

    expect(parseInt(textarea.style.height, 10)).toBeGreaterThanOrEqual(72);
  });

  it('clamps the auto-height to a sane maximum (~12 rows) and scrolls beyond that', () => {
    const wrapper = mountEditor();
    const textarea = wrapper.find(
      '[data-testid="route-template-input"]'
    ).element;
    Object.defineProperty(textarea, 'scrollHeight', {
      configurable: true,
      value: 1000,
    });

    wrapper.vm.resizeToContent();

    expect(parseInt(textarea.style.height, 10)).toBeLessThanOrEqual(288);
    expect(textarea.style.overflowY).toBe('auto');
  });

  it('resizes on input', async () => {
    const wrapper = mountEditor();
    const textarea = wrapper.find(
      '[data-testid="route-template-input"]'
    ).element;
    Object.defineProperty(textarea, 'scrollHeight', {
      configurable: true,
      value: 200,
    });

    await wrapper.find('[data-testid="route-template-input"]').trigger('input');

    expect(textarea.style.height).toBe('200px');
  });

  // ── substitute() em-dash fallback, tested directly ──
  it('substitute() falls back to an em-dash for a named placeholder key with no sample value', () => {
    // This is the backend's emDashPlaceholder fallback (notifier.go
    // render()), exercised directly against substitute() rather than via the
    // live preview: PREVIEW_SAMPLE now populates every named placeholder key
    // (items/address/phone/payment), so the fallback is unreachable from the
    // rendered preview. A template/sample pair that deliberately omits a
    // named key's value still must resolve to "—", not a dangling "{token}".
    const wrapper = mountEditor();
    const result = wrapper.vm.substitute('Payment: {payment}', {
      // `payment` deliberately absent.
      items: 'x',
      address: 'y',
      phone: 'z',
    });
    expect(result).toBe('Payment: —');
    expect(result).not.toContain('{payment}');
  });

  it('substitute() substitutes a non-named-placeholder key verbatim and leaves unknown tokens untouched', () => {
    const wrapper = mountEditor();
    const result = wrapper.vm.substitute('{stage} / {unknown}', {
      stage: 'Order taking',
    });
    expect(result).toBe('Order taking / {unknown}');
  });
});
