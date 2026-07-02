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
const notificationsDirty = ref(false);
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

async function loadNotifications() {
  if (!props.engineUrl) return;
  isLoading.value = true;
  try {
    const notif = await fetch(url('/notifications'), {
      headers: authHeaders(),
    });
    if (notif.ok) notifications.value = await notif.json();
  } catch (e) {
    useAlert(t('COMVOR_SETTINGS.FETCH_ERROR'));
  } finally {
    isLoading.value = false;
  }
}

function onNotificationsUpdate(update) {
  notifications.value = { ...notifications.value, ...update };
  notificationsDirty.value = true;
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

onMounted(loadNotifications);
defineExpose({
  loadNotifications,
  saveNotifications,
  onNotificationsUpdate,
  notifications,
  notificationsDirty,
  notificationsInvalid,
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
          @update:notifications="onNotificationsUpdate"
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
