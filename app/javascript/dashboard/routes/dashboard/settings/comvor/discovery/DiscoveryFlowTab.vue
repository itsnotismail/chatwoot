<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import FlowEditor from './FlowEditor.vue';

const props = defineProps({
  accountId: { type: String, required: true },
  engineUrl: { type: String, default: '' },
});

const { t } = useI18n();
const store = useStore();

const isLoading = ref(false);
const isSaving = ref(false);
const flowConfig = ref(null);
const connectors = ref(null);
const notifications = ref(null);
const draftStages = ref({});
const hasUnsavedChanges = ref(false);

function authHeaders() {
  const token = store.getters.getCurrentUser?.access_token || '';
  return {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${token}`,
  };
}
function url(suffix) {
  return `${props.engineUrl}/api/accounts/${props.accountId}${suffix}`;
}

async function loadAll() {
  if (!props.engineUrl) return;
  isLoading.value = true;
  try {
    const [fc, conn, notif] = await Promise.all([
      fetch(url('/flow-config'), { headers: authHeaders() }),
      fetch(url('/connectors'), { headers: authHeaders() }),
      fetch(url('/notifications'), { headers: authHeaders() }),
    ]);
    if (fc.ok) flowConfig.value = await fc.json();
    if (conn.ok) connectors.value = await conn.json();
    if (notif.ok) notifications.value = await notif.json();
  } catch (e) {
    useAlert(t('COMVOR_SETTINGS.FETCH_ERROR'));
  } finally {
    isLoading.value = false;
  }
}

function onStageUpdate(update) {
  const key = `${update.flow_key}:${update.stage_key}`;
  draftStages.value = { ...draftStages.value, [key]: update };
  hasUnsavedChanges.value = true;
}

async function saveDraft() {
  if (!props.engineUrl) return;
  isSaving.value = true;
  try {
    const stages = Object.values(draftStages.value).map(s => ({
      flow_key: s.flow_key,
      stage_key: s.stage_key,
      action_mode: s.action_mode,
      on_complete: s.on_complete,
      guidance: s.guidance,
      skipped: s.skipped,
      enabled_reads: [],
    }));
    const res = await fetch(url('/flow-config'), {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({ stages, policy: flowConfig.value.policy }),
    });
    if (!res.ok) {
      const msg = await res.text();
      throw new Error(msg || `HTTP ${res.status}`);
    }
    await loadAll();
    draftStages.value = {};
    hasUnsavedChanges.value = false;
    useAlert(t('COMVOR_SETTINGS.DISCOVERY.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('COMVOR_SETTINGS.DISCOVERY.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
}

onMounted(loadAll);
defineExpose({ loadAll, saveDraft });
</script>

<template>
  <div class="flex flex-col gap-6">
    <div v-if="isLoading">{{ t('COMVOR_SETTINGS.LOADING') }}</div>
    <template v-else-if="flowConfig">
      <div class="flex items-center gap-2">
        <span class="text-sm font-medium"
          >{{ t('COMVOR_SETTINGS.DISCOVERY.STATUS') }}:</span
        >
        <span
          class="text-xs px-2 py-0.5 rounded bg-slate-100 dark:bg-slate-700"
          >{{ flowConfig.status }}</span
        >
      </div>

      <div
        v-for="flow in flowConfig.flows"
        :key="flow.flow_key"
        class="border rounded-md p-3"
      >
        <h4 class="font-semibold mb-2">
          {{ flow.flow_key }}
          <span class="text-xs opacity-60">({{ flow.mode }})</span>
        </h4>
        <FlowEditor
          :flow="flow"
          :walls="flowConfig.hard_errors || []"
          @update:stage="onStageUpdate"
        />
      </div>

      <div class="border rounded-md p-3 text-sm">
        <h4 class="font-semibold mb-2">
          {{ t('COMVOR_SETTINGS.DISCOVERY.POLICY.TITLE') }}
        </h4>
        <div>
          {{ t('COMVOR_SETTINGS.DISCOVERY.POLICY.DEBOUNCE_MS') }}:
          {{ flowConfig.policy.debounce_ms }} ·
          {{ t('COMVOR_SETTINGS.DISCOVERY.POLICY.IDLE_TERMINAL') }}:
          {{ flowConfig.policy.idle_terminal }}
        </div>
      </div>

      <div class="flex items-center justify-end gap-3 px-1 py-2">
        <span v-if="hasUnsavedChanges" class="text-xs text-amber-600">
          {{ t('COMVOR_SETTINGS.DISCOVERY.UNSAVED_CHANGES') }}
        </span>
        <woot-button :is-loading="isSaving" @click="saveDraft">
          {{
            isSaving
              ? t('COMVOR_SETTINGS.DISCOVERY.SAVING')
              : t('COMVOR_SETTINGS.DISCOVERY.SAVE')
          }}
        </woot-button>
      </div>
    </template>
  </div>
</template>
