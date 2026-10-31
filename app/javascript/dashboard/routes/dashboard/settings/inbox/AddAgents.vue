<script>
/* eslint no-console: 0 */
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';

import InboxMembersAPI from '../../../../api/inboxMembers';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TagInput from 'dashboard/components-next/taginput/TagInput.vue';
import router from '../../../index';
import PageHeader from '../SettingsSubPageHeader.vue';
import { useVuelidate } from '@vuelidate/core';

export default {
  components: {
    PageHeader,
    NextButton,
    TagInput,
  },
  validations: {
    selectedAgentIds: {
      isEmpty() {
        return !!this.selectedAgentIds.length;
      },
    },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      selectedAgentIds: [],
      selectionTouched: false,
      isCreating: false,
    };
  },
  computed: {
    ...mapGetters({
      agentList: 'agents/getAgents',
    }),
    selectedAgentNames() {
      return this.selectedAgentIds.map(
        id => this.agentList.find(a => a.id === id)?.name ?? ''
      );
    },
    agentMenuItems() {
      return this.agentList
        .filter(({ id }) => !this.selectedAgentIds.includes(id))
        .map(({ id, name, thumbnail, avatar_url }) => ({
          label: name,
          value: id,
          action: 'select',
          thumbnail: { name, src: thumbnail || avatar_url || '' },
        }));
    },
  },
  async mounted() {
    this.$store.dispatch('agents/get');
    // Comvor: start from the inbox's current members. Where the deployment adds
    // every account user to a new inbox, the owner removes someone rather than
    // having to add everyone, and saving the step keeps that choice.
    // A pick the owner made before the members arrived is kept.
    try {
      const { data } = await InboxMembersAPI.show(this.$route.params.inbox_id);
      if (!this.selectionTouched) {
        this.selectedAgentIds = data.payload.map(({ id }) => id);
      }
    } catch {
      // Keep whatever is selected: the step starts empty as upstream does.
    }
  },
  methods: {
    handleAgentAdd({ value }) {
      this.selectionTouched = true;
      if (!this.selectedAgentIds.includes(value)) {
        this.selectedAgentIds.push(value);
      }
    },
    handleAgentRemove(index) {
      this.selectionTouched = true;
      this.selectedAgentIds.splice(index, 1);
    },
    async addAgents() {
      this.isCreating = true;
      const inboxId = this.$route.params.inbox_id;

      try {
        await InboxMembersAPI.update({
          inboxId,
          agentList: this.selectedAgentIds,
        });
        router.replace({
          name: 'settings_inbox_finish',
          params: {
            page: 'new',
            inbox_id: this.$route.params.inbox_id,
          },
        });
      } catch (error) {
        useAlert(error.message);
      }
      this.isCreating = false;
    },
  },
};
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <form class="flex flex-wrap flex-col mx-0" @submit.prevent="addAgents()">
      <div class="w-full">
        <PageHeader
          :header-title="$t('INBOX_MGMT.ADD.AGENTS.TITLE')"
          :header-content="$t('INBOX_MGMT.ADD.AGENTS.DESC')"
        />
      </div>
      <div>
        <div class="w-full mb-4">
          <label :class="{ error: v$.selectedAgentIds.$error }">
            {{ $t('INBOX_MGMT.ADD.AGENTS.TITLE') }}
            <div
              class="rounded-xl outline outline-1 -outline-offset-1 outline-n-weak hover:outline-n-strong px-2 py-2"
            >
              <TagInput
                :model-value="selectedAgentNames"
                :placeholder="$t('INBOX_MGMT.ADD.AGENTS.PICK_AGENTS')"
                :menu-items="agentMenuItems"
                show-dropdown
                skip-label-dedup
                @add="handleAgentAdd"
                @remove="handleAgentRemove"
              />
            </div>
            <span v-if="v$.selectedAgentIds.$error" class="message">
              {{ $t('INBOX_MGMT.ADD.AGENTS.VALIDATION_ERROR') }}
            </span>
          </label>
        </div>
        <div class="w-full">
          <NextButton
            type="submit"
            :is-loading="isCreating"
            solid
            blue
            :label="$t('INBOX_MGMT.AGENTS.BUTTON_TEXT')"
          />
        </div>
      </div>
    </form>
  </div>
</template>
