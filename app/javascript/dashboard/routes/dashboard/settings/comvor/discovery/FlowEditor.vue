<script setup>
import { reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  flow: { type: Object, required: true },
  walls: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:stage']);

const { t } = useI18n();

const stageEdits = reactive({});
watch(
  () => props.flow,
  flow => {
    flow.stages.forEach(stage => {
      stageEdits[stage.stage_key] = {
        action_mode: stage.action_mode || 'auto',
        on_complete: stage.on_complete,
        guidance: stage.guidance,
        skipped: !!stage.skipped,
      };
    });
  },
  { immediate: true }
);

function wallFor(stageKey) {
  return props.walls.find(
    w => w.flow_key === props.flow.flow_key && w.stage_key === stageKey
  );
}

function showsActionMode(stage) {
  return !!stage.action_tool || !!wallFor(stage.stage_key);
}

function onFieldChange(stage, field, value) {
  const edited = stageEdits[stage.stage_key];
  edited[field] = value;
  emit('update:stage', {
    flow_key: props.flow.flow_key,
    stage_key: stage.stage_key,
    ...edited,
  });
}
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      v-for="stage in flow.stages"
      :key="stage.stage_key"
      data-testid="stage-row"
      class="border rounded-md p-3 flex flex-col gap-2"
    >
      <div class="flex items-center justify-between gap-2">
        <span class="font-mono text-sm">{{ stage.stage_key }}</span>
        <span
          v-if="wallFor(stage.stage_key)"
          class="text-xs px-1.5 rounded bg-amber-100 text-amber-800"
        >
          {{ wallFor(stage.stage_key).message }}
        </span>
      </div>

      <label class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-12">{{
          t('COMVOR_SETTINGS.DISCOVERY.EDITOR.ON_COMPLETE_LABEL')
        }}</span>
        <select
          data-testid="on-complete-select"
          :value="stageEdits[stage.stage_key].on_complete"
          :disabled="!!wallFor(stage.stage_key)"
          class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          @change="onFieldChange(stage, 'on_complete', $event.target.value)"
        >
          <option value="continue">
            {{ t('COMVOR_SETTINGS.DISCOVERY.EDITOR.ON_COMPLETE_CONTINUE') }}
          </option>
          <option value="handoff">
            {{ t('COMVOR_SETTINGS.DISCOVERY.EDITOR.ON_COMPLETE_HANDOFF') }}
          </option>
          <option value="resolve">
            {{ t('COMVOR_SETTINGS.DISCOVERY.EDITOR.ON_COMPLETE_RESOLVE') }}
          </option>
        </select>
      </label>

      <label class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-12">{{
          t('COMVOR_SETTINGS.DISCOVERY.EDITOR.GUIDANCE_LABEL')
        }}</span>
        <textarea
          data-testid="guidance-textarea"
          :value="stageEdits[stage.stage_key].guidance"
          :disabled="!!wallFor(stage.stage_key)"
          rows="2"
          class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          @change="onFieldChange(stage, 'guidance', $event.target.value)"
        />
      </label>

      <label v-if="showsActionMode(stage)" class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-12">{{
          t('COMVOR_SETTINGS.DISCOVERY.EDITOR.ACTION_MODE_LABEL')
        }}</span>
        <select
          data-testid="action-mode-select"
          :value="stageEdits[stage.stage_key].action_mode"
          :disabled="!!wallFor(stage.stage_key)"
          class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          @change="onFieldChange(stage, 'action_mode', $event.target.value)"
        >
          <option value="auto">
            {{ t('COMVOR_SETTINGS.DISCOVERY.EDITOR.ACTION_MODE_AUTO') }}
          </option>
          <option value="deferred">
            {{ t('COMVOR_SETTINGS.DISCOVERY.EDITOR.ACTION_MODE_DEFERRED') }}
          </option>
        </select>
      </label>

      <label class="flex items-center gap-2">
        <input
          data-testid="skipped-checkbox"
          type="checkbox"
          :checked="stageEdits[stage.stage_key].skipped"
          :disabled="!!wallFor(stage.stage_key)"
          class="w-4 h-4 accent-n-brand"
          @change="onFieldChange(stage, 'skipped', $event.target.checked)"
        />
        <span class="text-xs font-medium text-n-slate-12">{{
          t('COMVOR_SETTINGS.DISCOVERY.EDITOR.SKIPPED_LABEL')
        }}</span>
      </label>
    </div>
  </div>
</template>
