import { mount } from '@vue/test-utils';
import TemplateEditor from '../TemplateEditor.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

function mountEditor(row = {}) {
  return mount(TemplateEditor, {
    props: {
      row: { event: 'new_order', isStage: false, template: '', ...row },
    },
  });
}

describe('TemplateEditor.vue', () => {
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
