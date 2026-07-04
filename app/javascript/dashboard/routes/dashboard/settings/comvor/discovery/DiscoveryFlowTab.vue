<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import SalesFlowEditor from './SalesFlowEditor.vue';
import SupportIntentsEditor from './SupportIntentsEditor.vue';
import PublishConfirmModal from './PublishConfirmModal.vue';
import { flowSummary } from './summary.js';

const props = defineProps({
  accountId: { type: String, required: true },
  engineUrl: { type: String, default: '' },
});

const { t } = useI18n();
const store = useStore();

const isLoading = ref(false);
const isSaving = ref(false);
const isPublishing = ref(false);
const flowConfig = ref(null);
// Which sub-tab is showing: the ordered (sales) flow or the unordered
// (support) flow. Defaults to sales.
const activeSubTab = ref('sales');
const salesFlow = computed(() =>
  (flowConfig.value?.flows || []).find(f => f.mode === 'ordered')
);
const supportFlow = computed(() =>
  (flowConfig.value?.flows || []).find(f => f.mode === 'unordered')
);
const salesSummary = computed(() =>
  salesFlow.value ? flowSummary(salesFlow.value, t) : ''
);

// Looks up a stage's merchant-facing display name by flow_key/stage_key so
// soft-warning panels can speak in plain language instead of showing raw
// capability keys (e.g. "order.draft"). Falls back to the stage_key itself
// if the stage can't be found (e.g. a stale flowConfig).
function stageDisplayName(flowKey, stageKey) {
  const flow = (flowConfig.value?.flows || []).find(
    f => f.flow_key === flowKey
  );
  const stage = flow?.stages?.find(s => s.stage_key === stageKey);
  return stage?.display_name || stageKey;
}
const draftStages = ref({});
const flowDirty = ref(false);
const hasUnsavedChanges = computed(() => flowDirty.value);
const hardErrors = ref([]);
const softWarnings = ref([]);
const showPublishModal = ref(false);

const STATUS_PILL_MAP = {
  defaults: {
    labelKey: 'COMVOR_SETTINGS.STATUS_PILL.DEFAULTS',
    classes: 'bg-n-slate-3 text-n-slate-11',
  },
  draft: {
    labelKey: 'COMVOR_SETTINGS.STATUS_PILL.DRAFT',
    classes:
      'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300',
  },
  published: {
    labelKey: 'COMVOR_SETTINGS.STATUS_PILL.PUBLISHED',
    classes:
      'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300',
  },
};
const statusPill = computed(
  () => STATUS_PILL_MAP[flowConfig.value?.status] || STATUS_PILL_MAP.defaults
);
// Which heading the wall panel shows: publish-blocked vs draft-can't-publish.
const hardErrorsTitleKey = ref(
  'COMVOR_SETTINGS.DISCOVERY.PUBLISH_HARD_ERRORS_TITLE'
);
// version_id of the flow-config the UI last loaded — echoed back on PUT as
// expected_version_id so concurrent edits from another session 409 instead
// of silently clobbering each other.
const versionId = ref(0);

function applyFlowConfig(resp) {
  flowConfig.value = resp;
  versionId.value = resp?.version_id || 0;
}

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

async function loadFlowConfig() {
  if (!props.engineUrl) return;
  try {
    const fc = await fetch(url('/flow-config'), { headers: authHeaders() });
    if (fc.ok) applyFlowConfig(await fc.json());
  } catch (e) {
    useAlert(t('COMVOR_SETTINGS.FETCH_ERROR'));
  }
}

async function loadAll() {
  if (!props.engineUrl) return;
  isLoading.value = true;
  try {
    await loadFlowConfig();
  } finally {
    isLoading.value = false;
  }
}

function onStageUpdate(update) {
  const key = `${update.flow_key}:${update.stage_key}`;
  // Merge partial updates for the same stage so, e.g., a notify-only edit
  // doesn't clobber an earlier guidance-only edit on the same stage.
  draftStages.value = {
    ...draftStages.value,
    [key]: { ...draftStages.value[key], ...update },
  };
  // Optimistically reflect the edit in the rendered config so derived UI
  // (cutoff zones, the handoff marker, who-completes) updates immediately
  // instead of only after a save+reload.
  const flow = (flowConfig.value?.flows || []).find(
    f => f.flow_key === update.flow_key
  );
  const stage = flow?.stages?.find(s => s.stage_key === update.stage_key);
  if (stage) {
    const { flow_key: _fk, stage_key: _sk, ...fields } = update;
    Object.assign(stage, fields);
  }
  flowDirty.value = true;
}

async function saveDraft() {
  if (!props.engineUrl) return;
  isSaving.value = true;
  try {
    // Minimal PUT: send only the fields that were actually changed (plus
    // the identifying keys). Both SalesFlowEditor and SupportIntentsEditor
    // emit single- or few-field payloads per control; the backend preserves
    // every omitted field on partial PUTs, so we never need to round-trip
    // the full stage here.
    const stages = Object.values(draftStages.value).map(s => {
      const stage = { flow_key: s.flow_key, stage_key: s.stage_key };
      [
        'action_mode',
        'on_complete',
        'guidance',
        'skipped',
        'notify_enabled',
        'notify_guidance',
      ].forEach(field => {
        if (s[field] !== undefined) stage[field] = s[field];
      });
      return stage;
    });
    const res = await fetch(url('/flow-config'), {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({
        stages,
        policy: flowConfig.value.policy,
        expected_version_id: versionId.value,
      }),
    });
    if (res.status === 409) {
      // Someone else changed the config since we loaded it. Server wins:
      // reload the latest and drop the local edits rather than clobbering.
      useAlert(t('COMVOR_SETTINGS.DISCOVERY.VERSION_CONFLICT_RELOADED'));
      await loadFlowConfig();
      draftStages.value = {};
      flowDirty.value = false;
      return;
    }
    if (!res.ok) {
      const msg = await res.text();
      throw new Error(msg || `HTTP ${res.status}`);
    }
    await loadFlowConfig();
    draftStages.value = {};
    flowDirty.value = false;
    // Surface the refreshed draft's walls right away — "this draft can't be
    // published yet" — instead of waiting for a publish attempt to fail.
    hardErrors.value = flowConfig.value?.hard_errors || [];
    softWarnings.value = flowConfig.value?.soft_warnings || [];
    hardErrorsTitleKey.value =
      'COMVOR_SETTINGS.DISCOVERY.SAVE_HARD_ERRORS_TITLE';
    useAlert(t('COMVOR_SETTINGS.DISCOVERY.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('COMVOR_SETTINGS.DISCOVERY.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
}

async function publish() {
  if (!props.engineUrl || flowDirty.value) return;
  isPublishing.value = true;
  try {
    const res = await fetch(url('/flow-config/publish'), {
      method: 'POST',
      headers: authHeaders(),
    });
    if (res.status === 422) {
      const body = await res.json();
      hardErrors.value = body.hard_errors || [];
      softWarnings.value = body.soft_warnings || [];
      hardErrorsTitleKey.value =
        'COMVOR_SETTINGS.DISCOVERY.PUBLISH_HARD_ERRORS_TITLE';
      return;
    }
    if (!res.ok) {
      const msg = await res.text();
      throw new Error(msg || `HTTP ${res.status}`);
    }
    await loadFlowConfig();
    hardErrors.value = [];
    softWarnings.value = [];
    useAlert(t('COMVOR_SETTINGS.DISCOVERY.PUBLISH_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('COMVOR_SETTINGS.DISCOVERY.PUBLISH_ERROR'));
  } finally {
    isPublishing.value = false;
    showPublishModal.value = false;
  }
}

function openPublishModal() {
  if (flowDirty.value) return;
  showPublishModal.value = true;
}

function cancelPublishModal() {
  showPublishModal.value = false;
}

async function confirmPublish() {
  await publish();
}

onMounted(loadAll);
defineExpose({
  loadAll,
  loadFlowConfig,
  saveDraft,
  publish,
  openPublishModal,
  confirmPublish,
  cancelPublishModal,
  showPublishModal,
  flowConfig,
  hardErrors,
  softWarnings,
  hasUnsavedChanges,
  flowDirty,
  activeSubTab,
  stageDisplayName,
  onStageUpdate,
});
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
          data-testid="status-pill"
          class="text-xs px-2 py-0.5 rounded font-medium"
          :class="statusPill.classes"
          >{{ t(statusPill.labelKey) }}</span
        >
      </div>

      <p
        v-if="activeSubTab === 'sales' && salesSummary"
        data-testid="sales-summary"
        class="text-sm text-n-slate-11"
      >
        {{ salesSummary }}
      </p>

      <div class="flex gap-1 rounded-lg bg-n-slate-2 p-1 w-fit">
        <button
          type="button"
          data-testid="sub-tab-sales"
          class="rounded-md px-3 py-1.5 text-sm font-medium transition-colors"
          :class="
            activeSubTab === 'sales'
              ? 'bg-n-solid-2 text-n-slate-12 shadow-sm'
              : 'text-n-slate-10'
          "
          @click="activeSubTab = 'sales'"
        >
          {{ t('COMVOR_SETTINGS.DISCOVERY.SUB_TABS.SALES') }}
        </button>
        <button
          type="button"
          data-testid="sub-tab-support"
          class="rounded-md px-3 py-1.5 text-sm font-medium transition-colors"
          :class="
            activeSubTab === 'support'
              ? 'bg-n-solid-2 text-n-slate-12 shadow-sm'
              : 'text-n-slate-10'
          "
          @click="activeSubTab = 'support'"
        >
          {{ t('COMVOR_SETTINGS.DISCOVERY.SUB_TABS.SUPPORT') }}
        </button>
      </div>

      <div
        v-if="hardErrors.length"
        class="border border-red-300 bg-red-50 dark:bg-red-900/30 dark:border-red-700 rounded-md p-3 text-sm text-red-700 dark:text-red-300"
      >
        <h4 class="font-semibold mb-2">
          {{ t(hardErrorsTitleKey) }}
        </h4>
        <ul class="list-disc list-inside">
          <li v-for="(err, idx) in hardErrors" :key="idx">
            {{ err.message }}
          </li>
        </ul>
      </div>

      <div
        v-if="softWarnings.length"
        data-testid="soft-warnings-panel"
        class="border border-amber-300 bg-amber-50 dark:bg-amber-900/30 dark:border-amber-700 rounded-md p-3 text-sm text-amber-700 dark:text-amber-300"
      >
        <h4 class="font-semibold mb-2">
          {{ t('COMVOR_SETTINGS.DISCOVERY.PUBLISH_SOFT_WARNINGS_TITLE') }}
        </h4>
        <ul class="list-disc list-inside">
          <li v-for="(warn, idx) in softWarnings" :key="idx">
            {{
              t('COMVOR_SETTINGS.DISCOVERY.PUBLISH_MODAL.SOFT_WARNING', {
                stage: stageDisplayName(warn.flow_key, warn.stage_key),
              })
            }}
          </li>
        </ul>
      </div>

      <div
        v-if="activeSubTab === 'sales' && salesFlow"
        class="border rounded-md p-3"
      >
        <SalesFlowEditor
          :flow="salesFlow"
          :walls="flowConfig.hard_errors || []"
          @update:stage="onStageUpdate"
        />
      </div>

      <div
        v-if="activeSubTab === 'support' && supportFlow"
        class="border rounded-md p-3"
      >
        <SupportIntentsEditor
          :flow="supportFlow"
          :walls="flowConfig.hard_errors || []"
          @update:stage="onStageUpdate"
        />
      </div>

      <div class="flex items-center justify-end gap-3 px-1 py-2">
        <span v-if="hasUnsavedChanges" class="text-xs text-amber-600">
          {{ t('COMVOR_SETTINGS.DISCOVERY.UNSAVED_CHANGES') }}
        </span>
        <button
          type="button"
          data-testid="publish-button"
          :disabled="flowDirty || isPublishing"
          :title="
            flowDirty
              ? t('COMVOR_SETTINGS.DISCOVERY.PUBLISH_DISABLED_UNSAVED_HINT')
              : null
          "
          class="rounded-lg border border-n-weak px-4 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-50"
          @click="openPublishModal"
        >
          {{
            isPublishing
              ? t('COMVOR_SETTINGS.DISCOVERY.PUBLISHING')
              : t('COMVOR_SETTINGS.DISCOVERY.PUBLISH')
          }}
        </button>
        <button
          type="button"
          data-testid="save-draft-button"
          :disabled="isSaving"
          class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white hover:bg-n-brand/90 disabled:opacity-50"
          @click="saveDraft"
        >
          {{
            isSaving
              ? t('COMVOR_SETTINGS.DISCOVERY.SAVING')
              : t('COMVOR_SETTINGS.DISCOVERY.SAVE')
          }}
        </button>
      </div>

      <PublishConfirmModal
        v-if="showPublishModal"
        :summary="salesSummary"
        :soft-warnings="flowConfig.soft_warnings || []"
        :is-publishing="isPublishing"
        :stage-display-name="stageDisplayName"
        @confirm="confirmPublish"
        @cancel="cancelPublishModal"
      />
    </template>
  </div>
</template>
