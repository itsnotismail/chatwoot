<script setup>
import { reactive, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  connectors: { type: Object, required: true },
});

const emit = defineEmits(['update:connectors']);

const { t } = useI18n();

// NOTE: the /connectors GET response does not tell us which connector(s)
// provide which capability, only the currently-chosen `providers` map. So we
// can't truly detect "provided by >1 enabled connector" conflicts from the
// data available here. As a simplification, we only render a provider
// <select> for capabilities that already appear in `providers` (i.e. the
// backend has already surfaced them as needing a choice), and the options
// offered are the currently-enabled connectors.
const state = reactive({
  enabled: [],
  providers: {},
  available: [],
});

watch(
  () => props.connectors,
  connectors => {
    state.enabled = [...(connectors.enabled || [])];
    state.providers = { ...(connectors.providers || {}) };
    state.available = [...(connectors.available || [])];
  },
  { immediate: true }
);

const capabilitiesNeedingProvider = computed(() =>
  Object.keys(state.providers)
);

function emitUpdate() {
  emit('update:connectors', {
    enabled: [...state.enabled],
    providers: { ...state.providers },
  });
}

function toggleConnector(connector, checked) {
  if (checked) {
    if (!state.enabled.includes(connector)) {
      state.enabled = [...state.enabled, connector];
    }
  } else {
    state.enabled = state.enabled.filter(c => c !== connector);
  }
  emitUpdate();
}

function onProviderChange(capability, value) {
  state.providers = { ...state.providers, [capability]: value };
  emitUpdate();
}
</script>

<template>
  <div class="flex flex-col gap-3">
    <label
      v-for="connector in state.available"
      :key="connector"
      class="flex items-center gap-2"
    >
      <input
        data-testid="connector-checkbox"
        type="checkbox"
        :checked="state.enabled.includes(connector)"
        class="w-4 h-4 accent-n-brand"
        @change="toggleConnector(connector, $event.target.checked)"
      />
      <span class="text-xs font-medium text-n-slate-12">{{ connector }}</span>
    </label>

    <label
      v-for="capability in capabilitiesNeedingProvider"
      :key="capability"
      class="flex flex-col gap-1"
    >
      <span class="text-xs font-medium text-n-slate-12">{{
        t('COMVOR_SETTINGS.DISCOVERY.CONNECTORS.PROVIDER_LABEL', {
          capability,
        })
      }}</span>
      <select
        data-testid="provider-select"
        :value="state.providers[capability]"
        class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        @change="onProviderChange(capability, $event.target.value)"
      >
        <option v-for="conn in state.enabled" :key="conn" :value="conn">
          {{ conn }}
        </option>
      </select>
    </label>
  </div>
</template>
