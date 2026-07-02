<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import FlowEditor from './FlowEditor.vue';
import SalesFlowEditor from './SalesFlowEditor.vue';
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
const draftStages = ref({});
const flowDirty = ref(false);
const hasUnsavedChanges = computed(() => flowDirty.value);
const hardErrors = ref([]);
const softWarnings = ref([]);
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
  flowDirty.value = true;
}

async function saveDraft() {
  if (!props.engineUrl) return;
  isSaving.value = true;
  try {
    // Minimal PUT: send only the fields that were actually changed (plus
    // the identifying keys). FlowEditor (support flow, full-field editor)
    // always includes `skipped`, so its stages also carry an explicit
    // `enabled_reads: []` the way the API previously expected; SalesFlowEditor
    // sends only the specific field(s) a control changed.
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
      if (s.skipped !== undefined) stage.enabled_reads = [];
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
  }
}

onMounted(loadAll);
defineExpose({
  loadAll,
  loadFlowConfig,
  saveDraft,
  publish,
  flowConfig,
  hardErrors,
  softWarnings,
  hasUnsavedChanges,
  flowDirty,
  activeSubTab,
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
          class="text-xs px-2 py-0.5 rounded bg-slate-100 dark:bg-slate-700"
          >{{ flowConfig.status }}</span
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
        class="border border-amber-300 bg-amber-50 dark:bg-amber-900/30 dark:border-amber-700 rounded-md p-3 text-sm text-amber-700 dark:text-amber-300"
      >
        <h4 class="font-semibold mb-2">
          {{ t('COMVOR_SETTINGS.DISCOVERY.PUBLISH_SOFT_WARNINGS_TITLE') }}
        </h4>
        <ul class="list-disc list-inside">
          <li v-for="(warn, idx) in softWarnings" :key="idx">
            {{ warn.capability }} — {{ warn.message }}
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
        <h4 class="font-semibold mb-2">
          {{ supportFlow.flow_key }}
          <span class="text-xs opacity-60">({{ supportFlow.mode }})</span>
        </h4>
        <FlowEditor
          :flow="supportFlow"
          :walls="flowConfig.hard_errors || []"
          @update:stage="onStageUpdate"
        />
      </div>

      <div class="flex items-center justify-end gap-3 px-1 py-2">
        <span v-if="hasUnsavedChanges" class="text-xs text-amber-600">
          {{ t('COMVOR_SETTINGS.DISCOVERY.UNSAVED_CHANGES') }}
        </span>
        <woot-button
          variant="clear"
          :is-loading="isPublishing"
          :disabled="flowDirty"
          :title="
            flowDirty
              ? t('COMVOR_SETTINGS.DISCOVERY.PUBLISH_DISABLED_UNSAVED_HINT')
              : null
          "
          @click="publish"
        >
          {{
            isPublishing
              ? t('COMVOR_SETTINGS.DISCOVERY.PUBLISHING')
              : t('COMVOR_SETTINGS.DISCOVERY.PUBLISH')
          }}
        </woot-button>
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
