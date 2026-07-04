<script setup>
import { reactive, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';

// NOTE: this component used to also render a connector ENABLE checkbox list
// (one checkbox per entry in `connectors.available`) plus its own "Save
// Connectors" button. That list has moved to the unified Connector tab in
// Index.vue, where "connect Ewity" (choosing the type + saving) now also
// enables it in account_connectors — see `syncConnectorEnabled` there. This
// component now renders only the soft-wall capability toggles (which
// capabilities stay usable even while a connector is enabled) and the
// provider-conflict <select> (relevant once >1 connector can be enabled).
const props = defineProps({
  connectors: { type: Object, required: true },
  softWarnings: { type: Array, default: () => [] },
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
  disabledCapabilities: [],
});

watch(
  () => props.connectors,
  connectors => {
    state.enabled = [...(connectors.enabled || [])];
    state.providers = { ...(connectors.providers || {}) };
    state.disabledCapabilities = [...(connectors.disabled_capabilities || [])];
  },
  { immediate: true }
);

const capabilitiesNeedingProvider = computed(() =>
  Object.keys(state.providers)
);

// Union of capability names surfaced via disabled_capabilities and via
// softWarnings (which the backend emits when an enabled connector provides
// a capability that's been disabled), de-duplicated.
const toggleableCapabilities = computed(() => {
  const names = [
    ...state.disabledCapabilities,
    ...props.softWarnings.map(w => w.capability),
  ];
  return [...new Set(names)];
});

function emitUpdate() {
  emit('update:connectors', {
    enabled: [...state.enabled],
    providers: { ...state.providers },
    disabled_capabilities: [...state.disabledCapabilities],
  });
}

function onProviderChange(capability, value) {
  state.providers = { ...state.providers, [capability]: value };
  emitUpdate();
}

function toggleCapability(capability, checked) {
  if (checked) {
    state.disabledCapabilities = state.disabledCapabilities.filter(
      c => c !== capability
    );
  } else if (!state.disabledCapabilities.includes(capability)) {
    state.disabledCapabilities = [...state.disabledCapabilities, capability];
  }
  emitUpdate();
}
</script>

<template>
  <div class="flex flex-col gap-3">
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

    <div v-if="toggleableCapabilities.length" class="flex flex-col gap-2">
      <h5 class="text-xs font-semibold text-n-slate-12">
        {{ t('COMVOR_SETTINGS.DISCOVERY.CONNECTORS.CAPABILITIES_TITLE') }}
      </h5>
      <label
        v-for="capability in toggleableCapabilities"
        :key="capability"
        class="flex items-center gap-2"
      >
        <input
          data-testid="capability-checkbox"
          type="checkbox"
          :checked="!state.disabledCapabilities.includes(capability)"
          class="w-4 h-4 accent-n-brand"
          @change="toggleCapability(capability, $event.target.checked)"
        />
        <span class="text-xs font-medium text-n-slate-12">{{
          t('COMVOR_SETTINGS.DISCOVERY.CONNECTORS.CAPABILITY_ENABLED_LABEL', {
            capability,
          })
        }}</span>
      </label>
    </div>
  </div>
</template>
