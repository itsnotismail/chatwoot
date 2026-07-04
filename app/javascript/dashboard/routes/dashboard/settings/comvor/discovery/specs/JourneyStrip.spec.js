import { mount } from '@vue/test-utils';
import JourneyStrip from '../JourneyStrip.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const stages = [
  {
    stage_key: 'discovery',
    display_name: 'Discovery',
    on_complete: 'continue',
  },
  {
    stage_key: 'order_drafting',
    display_name: 'Order drafting',
    on_complete: 'handoff',
  },
  {
    stage_key: 'payment_fulfillment',
    display_name: 'Payment',
    on_complete: 'continue',
  },
];

function mountStrip(props = {}) {
  return mount(JourneyStrip, {
    props: { stages, cutoffKey: 'order_drafting', ...props },
  });
}

describe('JourneyStrip.vue', () => {
  it('renders one step per stage, with data-testids', () => {
    const wrapper = mountStrip();
    const steps = wrapper.findAll('[data-testid="journey-step"]');
    expect(steps).toHaveLength(3);
    expect(steps[0].attributes('data-stage-key')).toBe('discovery');
    expect(steps[1].attributes('data-stage-key')).toBe('order_drafting');
    expect(steps[2].attributes('data-stage-key')).toBe('payment_fulfillment');
  });

  it('colors bot-zone steps (up to and including the cutoff) and greys post-cutoff steps', () => {
    const wrapper = mountStrip();
    const steps = wrapper.findAll('[data-testid="journey-step"]');
    // discovery and order_drafting are bot-zone (cutoff is order_drafting)
    expect(steps[0].classes().join(' ')).not.toContain('grey');
    expect(steps[0].attributes('data-zone')).toBe('bot');
    expect(steps[1].attributes('data-zone')).toBe('bot');
    // payment_fulfillment is after the cutoff -> team zone / greyed
    expect(steps[2].attributes('data-zone')).toBe('team');
  });

  it('treats every stage as team-zone when cutoffKey is null (no cutoff yet)', () => {
    const wrapper = mountStrip({ cutoffKey: null });
    const steps = wrapper.findAll('[data-testid="journey-step"]');
    steps.forEach(step => {
      expect(step.attributes('data-zone')).toBe('team');
    });
  });

  it('emits select-cutoff with the stage_key when a step is clicked', async () => {
    const wrapper = mountStrip();
    const steps = wrapper.findAll('[data-testid="journey-step"]');
    await steps[2].trigger('click');
    expect(wrapper.emitted('selectCutoff')).toBeTruthy();
    expect(wrapper.emitted('selectCutoff')[0]).toEqual(['payment_fulfillment']);
  });

  it('renders exactly one handoff marker, positioned right after the cutoff pill and before the next pill', () => {
    const wrapper = mountStrip();
    const markers = wrapper.findAll('[data-testid="handoff-marker"]');
    expect(markers).toHaveLength(1);

    const allNodes = wrapper.findAll(
      '[data-testid="journey-step"], [data-testid="handoff-marker"]'
    );
    const cutoffPillIndex = allNodes.findIndex(
      node => node.attributes('data-stage-key') === 'order_drafting'
    );
    const markerIndex = allNodes.findIndex(
      node => node.attributes('data-testid') === 'handoff-marker'
    );
    const nextPillIndex = allNodes.findIndex(
      node => node.attributes('data-stage-key') === 'payment_fulfillment'
    );

    expect(markerIndex).toBeGreaterThan(cutoffPillIndex);
    expect(markerIndex).toBeLessThan(nextPillIndex);
  });

  it('does not render a separate journey terminus button', () => {
    const wrapper = mountStrip();
    expect(wrapper.find('[data-testid="journey-terminus"]').exists()).toBe(
      false
    );
  });

  it('clicking the pill after the cutoff emits select-cutoff with that stage key', async () => {
    const wrapper = mountStrip();
    await wrapper
      .find('[data-stage-key="payment_fulfillment"]')
      .trigger('click');
    expect(wrapper.emitted('selectCutoff')).toBeTruthy();
    expect(wrapper.emitted('selectCutoff')[0]).toEqual(['payment_fulfillment']);
  });
});
