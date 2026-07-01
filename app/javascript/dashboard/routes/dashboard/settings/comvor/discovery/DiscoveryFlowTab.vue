<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  accountId: { type: String, required: true },
  engineUrl: { type: String, default: '' },
});

const { t } = useI18n();
const store = useStore();

const isLoading = ref(false);
const flowConfig = ref(null);
const connectors = ref(null);
const notifications = ref(null);

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

function wallFor(flowKey, stageKey) {
  return (flowConfig.value?.hard_errors || []).find(
    e => e.flow_key === flowKey && e.stage_key === stageKey
  );
}

onMounted(loadAll);
defineExpose({ loadAll });
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
        <ul class="flex flex-col gap-1">
          <li
            v-for="stage in flow.stages"
            :key="stage.stage_key"
            class="text-sm flex flex-wrap items-center gap-2"
          >
            <span class="font-mono">{{ stage.stage_key }}</span>
            <span
              v-if="stage.in_scope"
              class="text-xs px-1.5 rounded bg-green-100 text-green-800"
              >{{ t('COMVOR_SETTINGS.DISCOVERY.IN_SCOPE') }}</span
            >
            <span
              v-else
              class="text-xs px-1.5 rounded bg-amber-100 text-amber-800"
            >
              {{
                wallFor(flow.flow_key, stage.stage_key)?.message ||
                t('COMVOR_SETTINGS.DISCOVERY.OUT_OF_SCOPE')
              }}
            </span>
            <span class="text-xs opacity-60"
              >{{ t('COMVOR_SETTINGS.DISCOVERY.ON_COMPLETE_ARROW') }}
              {{ stage.on_complete }}</span
            >
          </li>
        </ul>
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
    </template>
  </div>
</template>
