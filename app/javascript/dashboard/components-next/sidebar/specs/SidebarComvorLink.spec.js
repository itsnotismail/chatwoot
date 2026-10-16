import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import SidebarComvorLink from '../SidebarComvorLink.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('SidebarComvorLink', () => {
  it('links back to the Comvor portal with a visible label when expanded', () => {
    const wrapper = mount(SidebarComvorLink);
    const link = wrapper.get('[data-testid="comvor-dashboard-link"]');

    expect(link.element.tagName).toBe('A');
    expect(link.attributes('href')).toBe('https://app.comvor.com/app');
    expect(link.text()).toContain('SIDEBAR_ITEMS.COMVOR_DASHBOARD');
  });

  it('stays reachable when the sidebar is collapsed, labelled for screen readers', () => {
    const wrapper = mount(SidebarComvorLink, { props: { isCollapsed: true } });
    const link = wrapper.get('[data-testid="comvor-dashboard-link"]');

    expect(link.attributes('href')).toBe('https://app.comvor.com/app');
    expect(link.attributes('aria-label')).toBe(
      'SIDEBAR_ITEMS.COMVOR_DASHBOARD'
    );
  });
});
