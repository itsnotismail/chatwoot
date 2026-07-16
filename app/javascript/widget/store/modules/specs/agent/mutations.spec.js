import { mutations } from '../../agent';
import { agents } from './data';

describe('#mutations', () => {
  describe('#setAgents', () => {
    it('set agent records', () => {
      const state = { records: [] };
      mutations.setAgents(state, agents);
      expect(state.records).toEqual(agents);
    });
  });

  describe('#setError', () => {
    it('set error flag', () => {
      const state = { records: [], uiFlags: {} };
      mutations.setError(state, true);
      expect(state.uiFlags.isError).toEqual(true);
    });
  });

  describe('#setHasFetched', () => {
    it('set fetched flag', () => {
      const state = { records: [], uiFlags: {} };
      mutations.setHasFetched(state, true);
      expect(state.uiFlags.hasFetched).toEqual(true);
    });
  });

  describe('#updatePresence', () => {
    it('keeps a synthetic bot agent online even when absent from the presence map', () => {
      // Comvor: a bot-only inbox injects an "agent-bot-<n>" agent so the widget
      // reads as available. It is not tracked in human presence, so it must NOT
      // be flipped offline by a presence.update (which would render "away").
      const state = {
        records: [
          {
            id: 'agent-bot-1',
            name: 'Comvor AI',
            avatar_url: '',
            availability_status: 'online',
          },
          {
            id: 2,
            name: 'Xavier',
            avatar_url: '',
            availability_status: 'online',
          },
        ],
      };
      mutations.updatePresence(state, {}); // empty presence map (no humans online)
      expect(state.records[0].availability_status).toEqual('online');
      expect(state.records[1].availability_status).toEqual('offline');
    });

    it('updates agent presence', () => {
      const state = { records: agents };
      mutations.updatePresence(state, { 1: 'busy', 2: 'online' });
      expect(state.records).toEqual([
        {
          id: 1,
          name: 'John',
          avatar_url: '',
          availability_status: 'busy',
        },
        {
          id: 2,
          name: 'Xavier',
          avatar_url: '',
          availability_status: 'online',
        },
        {
          id: 3,
          name: 'Pranav',
          avatar_url: '',
          availability_status: 'offline',
        },
        {
          id: 4,
          name: 'Nithin',
          avatar_url: '',
          availability_status: 'offline',
        },
      ]);
    });
  });
});
