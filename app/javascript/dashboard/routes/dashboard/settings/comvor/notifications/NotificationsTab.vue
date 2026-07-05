<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import NotificationsEditor from '../discovery/NotificationsEditor.vue';

const props = defineProps({
  accountId: { type: String, required: true },
  engineUrl: { type: String, default: '' },
});

const { t } = useI18n();
const store = useStore();

const isLoading = ref(false);
const isSavingNotifications = ref(false);
const notifications = ref(null);
// Baseline snapshot captured on load, used to compute dirty state as a diff
// rather than a one-way latch — reverting an edit by hand clears the
// "unsaved changes" message instead of leaving it stuck.
const notificationsBaseline = ref('');
function serializeNotifications() {
  const n = notifications.value || {};
  return JSON.stringify({
    channels: n.channels || [],
    subscriptions: n.subscriptions || [],
    muted_events: n.muted_events || [],
  });
}
// Pending stage-notify edits from the routing table, keyed by stage_key.
// These are PUT to /flow-config (not /notifications) alongside the regular
// notifications save.
const stageNotifyDraft = ref({});
const notificationsDirty = computed(
  () =>
    serializeNotifications() !== notificationsBaseline.value ||
    Object.keys(stageNotifyDraft.value).length > 0
);
// Fetched to learn which stages are notifiable (their stage_key,
// display_name, flow_key, notify_enabled, notify_guidance) so the routing
// table can offer one row per stage-completion event and seed its route from
// the stage's current notify_enabled/notify_guidance. Only ever PUT back via
// stageNotifyDraft on save.
const notifiableStages = ref([]);
// version_id of the flow-config last loaded — echoed back on the
// stage-notify PUT as expected_version_id so a concurrent edit from another
// session 409s instead of silently clobbering.
const flowVersionId = ref(0);
// Mirrors the backend's 422: a new (id-less) Telegram channel must carry a
// non-empty, non-masked bot_token before it can be saved.
const notificationsInvalid = computed(() =>
  (notifications.value?.channels || []).some(c => !c.id && !c.config?.bot_token)
);

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

function extractNotifiableStages(flowConfig) {
  return (flowConfig?.flows || [])
    .flatMap(f => (f.stages || []).map(s => ({ ...s, flow_key: f.flow_key })))
    .filter(s => s.notifiable)
    .map(s => ({
      stage_key: s.stage_key,
      display_name: s.display_name,
      flow_key: s.flow_key,
      notify_enabled: s.notify_enabled,
      notify_guidance: s.notify_guidance,
      on_complete: s.on_complete,
    }));
}

async function loadNotifiableStages() {
  if (!props.engineUrl) return;
  try {
    const fc = await fetch(url('/flow-config'), { headers: authHeaders() });
    if (fc.ok) {
      const flowConfig = await fc.json();
      notifiableStages.value = extractNotifiableStages(flowConfig);
      flowVersionId.value = flowConfig?.version_id || 0;
    }
  } catch (e) {
    useAlert(t('COMVOR_SETTINGS.FETCH_ERROR'));
  }
}

async function loadNotifications() {
  if (!props.engineUrl) return;
  isLoading.value = true;
  try {
    const notif = await fetch(url('/notifications'), {
      headers: authHeaders(),
    });
    if (notif.ok) notifications.value = await notif.json();
    notificationsBaseline.value = serializeNotifications();
    await loadNotifiableStages();
  } catch (e) {
    useAlert(t('COMVOR_SETTINGS.FETCH_ERROR'));
  } finally {
    isLoading.value = false;
  }
}

function onNotificationsUpdate(update) {
  notifications.value = { ...notifications.value, ...update };
}

function onStageNotify(update) {
  const { stage_key: stageKey, ...fields } = update;
  const existing = stageNotifyDraft.value[stageKey];
  const stage = notifiableStages.value.find(s => s.stage_key === stageKey);
  stageNotifyDraft.value = {
    ...stageNotifyDraft.value,
    [stageKey]: {
      flow_key: existing?.flow_key || stage?.flow_key,
      stage_key: stageKey,
      notify_enabled: existing?.notify_enabled ?? stage?.notify_enabled,
      notify_guidance: existing?.notify_guidance ?? stage?.notify_guidance,
      ...existing,
      ...fields,
    },
  };
}

// Returns 'ok' on success, 'conflict' on a handled 409 (after its own
// alert+reload+clear). Throws on any other failure so the caller can tell
// a stage-save failure apart from a /notifications failure.
async function saveStageNotifyDraft() {
  const stages = Object.values(stageNotifyDraft.value).map(s => ({
    flow_key: s.flow_key,
    stage_key: s.stage_key,
    notify_enabled: s.notify_enabled,
    notify_guidance: s.notify_guidance,
  }));
  const res = await fetch(url('/flow-config'), {
    method: 'PUT',
    headers: authHeaders(),
    body: JSON.stringify({
      stages,
      expected_version_id: flowVersionId.value,
    }),
  });
  if (res.status === 409) {
    // Someone else changed the flow config since we loaded it. Server wins:
    // reload the latest and drop the local stage-notify edits rather than
    // clobbering, matching DiscoveryFlowTab's saveDraft conflict handling.
    useAlert(t('COMVOR_SETTINGS.DISCOVERY.VERSION_CONFLICT_RELOADED'));
    stageNotifyDraft.value = {};
    await loadNotifiableStages();
    return 'conflict';
  }
  if (!res.ok) {
    const msg = await res.text();
    throw new Error(msg || `HTTP ${res.status}`);
  }
  stageNotifyDraft.value = {};
  return 'ok';
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
        muted_events: notifications.value.muted_events || [],
      }),
    });
    if (!res.ok) {
      const msg = await res.text();
      throw new Error(msg || `HTTP ${res.status}`);
    }
    if (Object.keys(stageNotifyDraft.value).length) {
      let stageResult;
      try {
        stageResult = await saveStageNotifyDraft();
      } catch (stageError) {
        // /notifications already succeeded — don't blame it for the stage
        // save failing. Keep the stage draft so a re-save retries just that
        // part.
        useAlert(t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.STAGE_SAVE_ERROR'));
        return;
      }
      if (stageResult === 'conflict') {
        // The 409 handler already alerted and reloaded; don't additionally
        // (and falsely) report success.
        return;
      }
    }
    await loadNotifications();
    useAlert(t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(
      e.message || t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.SAVE_ERROR')
    );
  } finally {
    isSavingNotifications.value = false;
  }
}

onMounted(loadNotifications);
defineExpose({
  loadNotifications,
  saveNotifications,
  onNotificationsUpdate,
  onStageNotify,
  notifications,
  notificationsDirty,
  notificationsInvalid,
  notifiableStages,
  stageNotifyDraft,
});
</script>

<template>
  <div class="flex flex-col gap-6">
    <div v-if="isLoading">{{ t('COMVOR_SETTINGS.LOADING') }}</div>
    <template v-else-if="notifications">
      <div class="border rounded-md p-3 text-sm">
        <h4 class="font-semibold mb-2">
          {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.TITLE') }}
        </h4>
        <NotificationsEditor
          :notifications="notifications"
          :notifiable-stages="notifiableStages"
          @update:notifications="onNotificationsUpdate"
          @update:stage-notify="onStageNotify"
        />
        <div class="flex items-center justify-end gap-3 px-1 py-2">
          <span v-if="notificationsDirty" class="text-xs text-amber-600">
            {{ t('COMVOR_SETTINGS.DISCOVERY.UNSAVED_CHANGES') }}
          </span>
          <span v-if="notificationsInvalid" class="text-xs text-amber-600">
            {{
              t(
                'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.NEW_CHANNEL_TOKEN_REQUIRED_HINT'
              )
            }}
          </span>
          <button
            type="button"
            data-testid="save-notifications-button"
            :disabled="notificationsInvalid || isSavingNotifications"
            class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white hover:bg-n-brand/90 disabled:opacity-50"
            @click="saveNotifications"
          >
            {{
              isSavingNotifications
                ? t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.SAVING')
                : t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.SAVE')
            }}
          </button>
        </div>
      </div>
    </template>
  </div>
</template>
