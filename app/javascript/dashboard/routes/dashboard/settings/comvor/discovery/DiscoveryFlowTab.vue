<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import FlowEditor from './FlowEditor.vue';
import LifecyclePolicyEditor from './LifecyclePolicyEditor.vue';
import ConnectorsEditor from './ConnectorsEditor.vue';
import NotificationsEditor from './NotificationsEditor.vue';

const props = defineProps({
  accountId: { type: String, required: true },
  engineUrl: { type: String, default: '' },
});

const { t } = useI18n();
const store = useStore();

const isLoading = ref(false);
const isSaving = ref(false);
const isSavingConnectors = ref(false);
const isSavingNotifications = ref(false);
const isPublishing = ref(false);
const flowConfig = ref(null);
const connectors = ref(null);
const notifications = ref(null);
const draftStages = ref({});
const flowDirty = ref(false);
const connectorsDirty = ref(false);
const notificationsDirty = ref(false);
const hasUnsavedChanges = computed(
  () => flowDirty.value || connectorsDirty.value || notificationsDirty.value
);
// Mirrors the backend's 422: a new (id-less) Telegram channel must carry a
// non-empty, non-masked bot_token before it can be saved.
const notificationsInvalid = computed(() =>
  (notifications.value?.channels || []).some(c => !c.id && !c.config?.bot_token)
);
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
// Snapshot (sorted, stringified) of disabled_capabilities as last loaded
// from the backend — used to detect whether a connectors save actually
// changed the disabled set, see the comment in saveConnectors below.
const lastDisabledCapabilitiesSnapshot = ref('[]');

function disabledCapabilitiesSnapshot(disabled) {
  return JSON.stringify([...(disabled || [])].sort());
}

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

async function loadConnectors() {
  if (!props.engineUrl) return;
  try {
    const conn = await fetch(url('/connectors'), { headers: authHeaders() });
    if (conn.ok) {
      connectors.value = await conn.json();
      lastDisabledCapabilitiesSnapshot.value = disabledCapabilitiesSnapshot(
        connectors.value.disabled_capabilities
      );
    }
  } catch (e) {
    useAlert(t('COMVOR_SETTINGS.FETCH_ERROR'));
  }
}

async function loadNotifications() {
  if (!props.engineUrl) return;
  try {
    const notif = await fetch(url('/notifications'), {
      headers: authHeaders(),
    });
    if (notif.ok) notifications.value = await notif.json();
  } catch (e) {
    useAlert(t('COMVOR_SETTINGS.FETCH_ERROR'));
  }
}

async function loadAll() {
  if (!props.engineUrl) return;
  isLoading.value = true;
  try {
    await Promise.all([
      loadFlowConfig(),
      loadConnectors(),
      loadNotifications(),
    ]);
  } finally {
    isLoading.value = false;
  }
}

function onStageUpdate(update) {
  const key = `${update.flow_key}:${update.stage_key}`;
  draftStages.value = { ...draftStages.value, [key]: update };
  flowDirty.value = true;
}

function onPolicyUpdate(policy) {
  flowConfig.value = { ...flowConfig.value, policy };
  flowDirty.value = true;
}

function onConnectorsUpdate(update) {
  connectors.value = { ...connectors.value, ...update };
  connectorsDirty.value = true;
}

function onNotificationsUpdate(update) {
  notifications.value = { ...notifications.value, ...update };
  notificationsDirty.value = true;
}

async function saveConnectors() {
  if (!props.engineUrl) return;
  isSavingConnectors.value = true;
  try {
    const disabledBeforeSave = lastDisabledCapabilitiesSnapshot.value;
    const res = await fetch(url('/connectors'), {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({
        enabled: connectors.value.enabled,
        providers: connectors.value.providers,
        disabled_capabilities: connectors.value.disabled_capabilities || [],
      }),
    });
    if (!res.ok) {
      const msg = await res.text();
      throw new Error(msg || `HTTP ${res.status}`);
    }
    await loadConnectors();
    connectorsDirty.value = false;
    // Other save handlers only reload their own section, so a save can't
    // clobber another section's pending edits (see saveDraft/saveNotifications
    // above/below). Disabled capabilities are a deliberate exception: they
    // change which stages are in-scope, so if the saved disabled set differs
    // from what we last loaded, also refresh flow-config to pick up the
    // updated soft_warnings / stage scoping right away.
    if (lastDisabledCapabilitiesSnapshot.value !== disabledBeforeSave) {
      await loadFlowConfig();
    }
    useAlert(t('COMVOR_SETTINGS.DISCOVERY.CONNECTORS.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('COMVOR_SETTINGS.DISCOVERY.CONNECTORS.SAVE_ERROR'));
  } finally {
    isSavingConnectors.value = false;
  }
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

async function saveNotifications() {
  if (!props.engineUrl || notificationsInvalid.value) return;
  isSavingNotifications.value = true;
  try {
    const res = await fetch(url('/notifications'), {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({
        channels: notifications.value.channels,
        subscriptions: notifications.value.subscriptions,
      }),
    });
    if (!res.ok) {
      const msg = await res.text();
      throw new Error(msg || `HTTP ${res.status}`);
    }
    await loadNotifications();
    notificationsDirty.value = false;
    useAlert(t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(
      e.message || t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.SAVE_ERROR')
    );
  } finally {
    isSavingNotifications.value = false;
  }
}

onMounted(loadAll);
defineExpose({
  loadAll,
  loadFlowConfig,
  loadConnectors,
  loadNotifications,
  saveDraft,
  saveConnectors,
  saveNotifications,
  publish,
  onConnectorsUpdate,
  onNotificationsUpdate,
  flowConfig,
  hardErrors,
  softWarnings,
  hasUnsavedChanges,
  flowDirty,
  connectorsDirty,
  notificationsDirty,
  notificationsInvalid,
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
        <LifecyclePolicyEditor
          :policy="flowConfig.policy"
          @update:policy="onPolicyUpdate"
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

      <div v-if="connectors" class="border rounded-md p-3 text-sm">
        <h4 class="font-semibold mb-2">
          {{ t('COMVOR_SETTINGS.DISCOVERY.CONNECTORS.TITLE') }}
        </h4>
        <ConnectorsEditor
          :connectors="connectors"
          :soft-warnings="softWarnings"
          @update:connectors="onConnectorsUpdate"
        />
        <div class="flex items-center justify-end gap-3 px-1 py-2">
          <woot-button :is-loading="isSavingConnectors" @click="saveConnectors">
            {{
              isSavingConnectors
                ? t('COMVOR_SETTINGS.DISCOVERY.CONNECTORS.SAVING')
                : t('COMVOR_SETTINGS.DISCOVERY.CONNECTORS.SAVE')
            }}
          </woot-button>
        </div>
      </div>

      <div v-if="notifications" class="border rounded-md p-3 text-sm">
        <h4 class="font-semibold mb-2">
          {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.TITLE') }}
        </h4>
        <NotificationsEditor
          :notifications="notifications"
          @update:notifications="onNotificationsUpdate"
        />
        <div class="flex items-center justify-end gap-3 px-1 py-2">
          <span v-if="notificationsInvalid" class="text-xs text-amber-600">
            {{
              t(
                'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.NEW_CHANNEL_TOKEN_REQUIRED_HINT'
              )
            }}
          </span>
          <woot-button
            data-testid="save-notifications-button"
            :is-loading="isSavingNotifications"
            :disabled="notificationsInvalid"
            @click="saveNotifications"
          >
            {{
              isSavingNotifications
                ? t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.SAVING')
                : t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.SAVE')
            }}
          </woot-button>
        </div>
      </div>
    </template>
  </div>
</template>
