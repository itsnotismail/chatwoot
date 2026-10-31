import { shallowMount, flushPromises } from '@vue/test-utils';
import AddAgents from '../AddAgents.vue';
import InboxMembersAPI from '../../../../../api/inboxMembers';

vi.mock('../../../../../api/inboxMembers', () => ({
  default: { show: vi.fn(), update: vi.fn() },
}));
vi.mock('../../../../index', () => ({ default: { replace: vi.fn() } }));

const mountWizard = () =>
  shallowMount(AddAgents, {
    global: {
      mocks: {
        $t: key => key,
        $route: { params: { inbox_id: 42 } },
        $store: {
          dispatch: vi.fn(),
          getters: {
            'agents/getAgents': [
              { id: 1, name: 'Owner' },
              { id: 2, name: 'Agent' },
            ],
          },
        },
      },
    },
  });

describe('AddAgents', () => {
  beforeEach(() => vi.clearAllMocks());

  it("starts from the inbox's current members", async () => {
    InboxMembersAPI.show.mockResolvedValue({
      data: { payload: [{ id: 1 }, { id: 2 }] },
    });
    const wrapper = mountWizard();
    await flushPromises();
    expect(InboxMembersAPI.show).toHaveBeenCalledWith(42);
    expect(wrapper.vm.selectedAgentIds).toEqual([1, 2]);
  });

  it('starts empty when the inbox has no members', async () => {
    InboxMembersAPI.show.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mountWizard();
    await flushPromises();
    expect(wrapper.vm.selectedAgentIds).toEqual([]);
  });

  it('starts empty when the members cannot be read', async () => {
    InboxMembersAPI.show.mockRejectedValue(new Error('boom'));
    const wrapper = mountWizard();
    await flushPromises();
    expect(wrapper.vm.selectedAgentIds).toEqual([]);
  });
});
