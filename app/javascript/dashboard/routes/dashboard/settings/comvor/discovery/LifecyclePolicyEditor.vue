<script setup>
import { reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  policy: { type: Object, required: true },
});

const emit = defineEmits(['update:policy']);

const { t } = useI18n();

const policyEdits = reactive({
  debounce_ms: 0,
  follow_up_after: 0,
  follow_up_count: 0,
  resolve_after: 0,
  idle_terminal: 'resolve',
});

watch(
  () => props.policy,
  policy => {
    policyEdits.debounce_ms = policy.debounce_ms;
    policyEdits.follow_up_after = policy.follow_up_after;
    policyEdits.follow_up_count = policy.follow_up_count;
    policyEdits.resolve_after = policy.resolve_after;
    policyEdits.idle_terminal = policy.idle_terminal;
  },
  { immediate: true }
);

function onFieldChange(field, value) {
  policyEdits[field] = value;
  emit('update:policy', { ...policyEdits });
}
</script>

<template>
  <div class="flex flex-col gap-3">
    <label class="flex flex-col gap-1">
      <span class="text-xs font-medium text-n-slate-12">{{
        t('COMVOR_SETTINGS.DISCOVERY.POLICY.DEBOUNCE_MS_LABEL')
      }}</span>
      <input
        data-testid="debounce-ms-input"
        type="number"
        :value="policyEdits.debounce_ms"
        class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        @change="onFieldChange('debounce_ms', Number($event.target.value))"
      />
    </label>

    <label class="flex flex-col gap-1">
      <span class="text-xs font-medium text-n-slate-12">{{
        t('COMVOR_SETTINGS.DISCOVERY.POLICY.FOLLOW_UP_AFTER_LABEL')
      }}</span>
      <input
        data-testid="follow-up-after-input"
        type="number"
        :value="policyEdits.follow_up_after"
        class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        @change="onFieldChange('follow_up_after', Number($event.target.value))"
      />
    </label>

    <label class="flex flex-col gap-1">
      <span class="text-xs font-medium text-n-slate-12">{{
        t('COMVOR_SETTINGS.DISCOVERY.POLICY.FOLLOW_UP_COUNT_LABEL')
      }}</span>
      <input
        data-testid="follow-up-count-input"
        type="number"
        :value="policyEdits.follow_up_count"
        class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        @change="onFieldChange('follow_up_count', Number($event.target.value))"
      />
    </label>

    <label class="flex flex-col gap-1">
      <span class="text-xs font-medium text-n-slate-12">{{
        t('COMVOR_SETTINGS.DISCOVERY.POLICY.RESOLVE_AFTER_LABEL')
      }}</span>
      <input
        data-testid="resolve-after-input"
        type="number"
        :value="policyEdits.resolve_after"
        class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        @change="onFieldChange('resolve_after', Number($event.target.value))"
      />
    </label>

    <label class="flex flex-col gap-1">
      <span class="text-xs font-medium text-n-slate-12">{{
        t('COMVOR_SETTINGS.DISCOVERY.POLICY.IDLE_TERMINAL_LABEL')
      }}</span>
      <select
        data-testid="idle-terminal-select"
        :value="policyEdits.idle_terminal"
        class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        @change="onFieldChange('idle_terminal', $event.target.value)"
      >
        <option value="resolve">
          {{ t('COMVOR_SETTINGS.DISCOVERY.POLICY.IDLE_TERMINAL_RESOLVE') }}
        </option>
        <option value="handoff">
          {{ t('COMVOR_SETTINGS.DISCOVERY.POLICY.IDLE_TERMINAL_HANDOFF') }}
        </option>
      </select>
    </label>
  </div>
</template>
