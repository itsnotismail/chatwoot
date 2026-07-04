<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Presentational horizontal stepper: bot-zone stages (up to and including
// the cutoff) render colored, post-cutoff stages render greyed, and a
// "Your team takes over" marker sits right after the cutoff pill. Clicking
// any step moves the cutoff there.
const props = defineProps({
  stages: { type: Array, required: true },
  cutoffKey: { type: String, default: null },
});

const emit = defineEmits(['selectCutoff']);

const { t } = useI18n();

const cutoffIndex = computed(() =>
  props.stages.findIndex(s => s.stage_key === props.cutoffKey)
);

function zoneFor(index) {
  if (cutoffIndex.value === -1) return 'team';
  return index <= cutoffIndex.value ? 'bot' : 'team';
}

function selectCutoff(stageKey) {
  emit('selectCutoff', stageKey);
}

const arrow = computed(() => t('COMVOR_SETTINGS.DISCOVERY.JOURNEY.ARROW'));
</script>

<template>
  <div class="flex items-center gap-1 overflow-x-auto py-2">
    <template v-for="(stage, index) in stages" :key="stage.stage_key">
      <button
        type="button"
        data-testid="journey-step"
        :data-stage-key="stage.stage_key"
        :data-zone="zoneFor(index)"
        class="shrink-0 cursor-pointer rounded-full px-3 py-1.5 text-xs font-medium transition-colors hover:ring-2 hover:ring-n-brand/40"
        :class="
          zoneFor(index) === 'bot'
            ? 'bg-n-brand/10 text-n-brand border border-n-brand/40'
            : 'bg-n-slate-3 text-n-slate-10 border border-n-slate-5'
        "
        @click="selectCutoff(stage.stage_key)"
      >
        {{ stage.display_name || stage.stage_key }}
      </button>
      <span
        v-if="index === cutoffIndex"
        data-testid="handoff-marker"
        class="shrink-0 inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-medium bg-n-brand/10 text-n-brand border border-dashed border-n-brand/40"
      >
        {{ t('COMVOR_SETTINGS.DISCOVERY.JOURNEY.TEAM_TAKES_OVER') }}
      </span>
      <span
        v-if="index < stages.length - 1"
        class="shrink-0 text-n-slate-8"
        aria-hidden="true"
        >{{ arrow }}</span
      >
    </template>
  </div>
</template>
