import { getAvailableAgents } from 'widget/api/agent';
import { getFromCache, setCache } from 'shared/helpers/cache';

const state = {
  records: [],
  uiFlags: {
    isError: false,
    hasFetched: false,
  },
};

export const getters = {
  getHasFetched: $state => $state.uiFlags.hasFetched,
  availableAgents: $state =>
    $state.records.filter(agent => agent.availability_status === 'online'),
};

const CACHE_KEY_PREFIX = 'chatwoot_available_agents_';

export const actions = {
  fetchAvailableAgents: async ({ commit }, websiteToken) => {
    try {
      const cachedData = getFromCache(`${CACHE_KEY_PREFIX}${websiteToken}`);
      if (cachedData) {
        commit('setAgents', cachedData);
        commit('setError', false);
        commit('setHasFetched', true);
        return;
      }

      const { data } = await getAvailableAgents(websiteToken);
      const { payload = [] } = data;
      setCache(`${CACHE_KEY_PREFIX}${websiteToken}`, payload);
      commit('setAgents', payload);
      commit('setError', false);
      commit('setHasFetched', true);
    } catch (error) {
      commit('setError', true);
      commit('setHasFetched', true);
    }
  },
  updatePresence: async ({ commit }, data) => {
    commit('updatePresence', data);
  },
};

export const mutations = {
  setAgents($state, data) {
    $state.records = data;
  },
  // Comvor: a synthetic AI-bot agent (id "agent-bot-<n>", injected by the
  // widget inbox_members endpoint so a bot-only inbox reads as available) is
  // NOT tracked in human presence, so the shared updatePresence would flip it
  // to "offline" on the first presence.update and the widget would render "We
  // are away". Keep bot agents at their fetched status; reconcile only real
  // human agents against the presence map.
  updatePresence($state, data) {
    $state.records.forEach((element, index) => {
      if (
        typeof element.id === 'string' &&
        element.id.startsWith('agent-bot-')
      ) {
        return;
      }
      $state.records[index].availability_status = data[element.id] || 'offline';
    });
  },
  setError($state, value) {
    $state.uiFlags.isError = value;
  },
  setHasFetched($state, value) {
    $state.uiFlags.hasFetched = value;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
