<script setup>
import { reactive, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import JourneyStrip from './JourneyStrip.vue';

const props = defineProps({
  flow: { type: Object, required: true },
  walls: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:stage']);

const { t } = useI18n();

const GUIDANCE_MAX = 2000;
const NOTIFY_GUIDANCE_MAX = 500;

// Which stages currently have their "Adjust guidance" expander open —
// purely local UI state, re-seeded (collapsed) whenever the flow reloads.
const guidanceOpen = reactive({});

watch(
  () => props.flow,
  flow => {
    (flow.stages || []).forEach(stage => {
      if (!(stage.stage_key in guidanceOpen)) {
        guidanceOpen[stage.stage_key] = false;
      }
    });
  },
  { immediate: true }
);

const cutoffKey = computed(() => {
  const stages = props.flow.stages || [];
  const cutoff = stages.find(s => s.on_complete !== 'continue');
  return cutoff ? cutoff.stage_key : null;
});

const cutoffIndex = computed(() =>
  (props.flow.stages || []).findIndex(s => s.stage_key === cutoffKey.value)
);

const botStages = computed(() => {
  const stages = props.flow.stages || [];
  if (cutoffIndex.value === -1) return stages;
  return stages.slice(0, cutoffIndex.value + 1);
});

const teamStages = computed(() => {
  const stages = props.flow.stages || [];
  if (cutoffIndex.value === -1) return [];
  return stages.slice(cutoffIndex.value + 1);
});

function wallFor(stageKey) {
  return props.walls.find(
    w => w.flow_key === props.flow.flow_key && w.stage_key === stageKey
  );
}

function emitStageUpdate(stageKey, fields) {
  emit('update:stage', {
    flow_key: props.flow.flow_key,
    stage_key: stageKey,
    ...fields,
  });
}

// Moving the cutoff to `stageKey`: that stage gets the current (or default)
// finish choice; any other stage that currently carries a non-continue
// on_complete is reset to 'continue'. Each stage gets its own minimal PUT
// payload (only on_complete + identifying keys).
function moveCutoffTo(stageKey) {
  if (stageKey === cutoffKey.value) return;
  const stages = props.flow.stages || [];
  const currentCutoff = stages.find(s => s.stage_key === cutoffKey.value);
  const finish =
    currentCutoff && currentCutoff.on_complete !== 'continue'
      ? currentCutoff.on_complete
      : 'handoff';

  stages.forEach(stage => {
    if (stage.stage_key === stageKey) return;
    if (stage.on_complete !== 'continue') {
      emitStageUpdate(stage.stage_key, { on_complete: 'continue' });
    }
  });
  emitStageUpdate(stageKey, { on_complete: finish });
}

function setFinish(stageKey, finish) {
  emitStageUpdate(stageKey, { on_complete: finish });
}

function setActionMode(stage, mode) {
  emitStageUpdate(stage.stage_key, { action_mode: mode });
}

function setGuidance(stage, value) {
  emitStageUpdate(stage.stage_key, { guidance: value });
}

function setNotifyEnabled(stage, enabled) {
  emitStageUpdate(stage.stage_key, { notify_enabled: enabled });
}

function setNotifyGuidance(stage, value) {
  emitStageUpdate(stage.stage_key, { notify_guidance: value });
}

function toggleGuidance(stageKey) {
  guidanceOpen[stageKey] = !guidanceOpen[stageKey];
}
</script>

<template>
  <div class="flex flex-col gap-4">
    <JourneyStrip
      :stages="flow.stages"
      :cutoff-key="cutoffKey"
      @select-cutoff="moveCutoffTo"
    />

    <div class="flex flex-col gap-3">
      <div
        v-for="stage in botStages"
        :key="stage.stage_key"
        data-testid="stage-card"
        class="border rounded-md p-3 flex flex-col gap-2"
      >
        <div class="flex items-center justify-between gap-2">
          <div class="flex flex-col">
            <span class="font-medium text-sm text-n-slate-12">{{
              stage.display_name || stage.stage_key
            }}</span>
            <span v-if="stage.description" class="text-xs text-n-slate-10">{{
              stage.description
            }}</span>
          </div>
          <span
            v-if="wallFor(stage.stage_key)"
            class="text-xs px-1.5 rounded bg-amber-100 text-amber-800 shrink-0"
          >
            {{ wallFor(stage.stage_key).message }}
          </span>
        </div>

        <label v-if="stage.has_action" class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">
            {{
              t('COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.WHO_COMPLETES_LABEL')
            }}
            <span
              :title="
                t(
                  'COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.WHO_COMPLETES_TOOLTIP'
                )
              "
              class="cursor-help text-n-slate-9"
              >?</span
            >
          </span>
          <select
            data-testid="who-completes-select"
            :value="stage.action_mode || 'auto'"
            class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            @change="setActionMode(stage, $event.target.value)"
          >
            <option value="auto">
              {{
                t('COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.WHO_COMPLETES_AUTO')
              }}
            </option>
            <option value="deferred">
              {{
                t(
                  'COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.WHO_COMPLETES_DEFERRED'
                )
              }}
            </option>
          </select>
        </label>

        <div v-if="stage.stage_key === cutoffKey" class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">
            {{ t('COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.FINISH_LABEL') }}
            <span
              :title="
                t('COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.FINISH_TOOLTIP')
              "
              class="cursor-help text-n-slate-9"
              >?</span
            >
          </span>
          <div class="flex items-center gap-4">
            <label class="flex items-center gap-1.5 text-xs">
              <input
                type="radio"
                data-testid="finish-handoff-radio"
                :name="`finish-${stage.stage_key}`"
                :checked="stage.on_complete === 'handoff'"
                @change="setFinish(stage.stage_key, 'handoff')"
              />
              {{ t('COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.FINISH_HANDOFF') }}
            </label>
            <label class="flex items-center gap-1.5 text-xs">
              <input
                type="radio"
                data-testid="finish-resolve-radio"
                :name="`finish-${stage.stage_key}`"
                :checked="stage.on_complete === 'resolve'"
                @change="setFinish(stage.stage_key, 'resolve')"
              />
              {{ t('COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.FINISH_RESOLVE') }}
            </label>
          </div>
        </div>

        <div class="flex flex-col gap-1">
          <button
            type="button"
            data-testid="adjust-guidance-toggle"
            class="self-start text-xs font-medium text-n-brand"
            @click="toggleGuidance(stage.stage_key)"
          >
            {{ t('COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.ADJUST_GUIDANCE') }}
          </button>
          <div v-if="guidanceOpen[stage.stage_key]" class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-12">{{
              t('COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.GUIDANCE_LABEL')
            }}</span>
            <textarea
              data-testid="guidance-textarea"
              :value="stage.guidance"
              :maxlength="GUIDANCE_MAX"
              rows="2"
              class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              @change="setGuidance(stage, $event.target.value)"
            />
            <span class="self-end text-[11px] text-n-slate-9">
              {{
                t('COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.CHAR_COUNT', {
                  count: (stage.guidance || '').length,
                  max: GUIDANCE_MAX,
                })
              }}
            </span>
          </div>
        </div>

        <div v-if="stage.notifiable" class="flex flex-col gap-1">
          <label class="flex items-center gap-2">
            <input
              type="checkbox"
              data-testid="notify-toggle"
              :checked="stage.notify_enabled"
              class="w-4 h-4 accent-n-brand"
              @change="setNotifyEnabled(stage, $event.target.checked)"
            />
            <span class="text-xs font-medium text-n-slate-12">
              {{
                t('COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.NOTIFY_TOGGLE_LABEL')
              }}
              <span
                :title="
                  t('COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.NOTIFY_TOOLTIP')
                "
                class="cursor-help text-n-slate-9"
                >?</span
              >
            </span>
          </label>
          <div v-if="stage.notify_enabled" class="flex flex-col gap-1 ml-6">
            <span class="text-xs font-medium text-n-slate-12">{{
              t('COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.NOTIFY_GUIDANCE_LABEL')
            }}</span>
            <input
              type="text"
              data-testid="notify-guidance-input"
              :value="stage.notify_guidance"
              :maxlength="NOTIFY_GUIDANCE_MAX"
              class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              @change="setNotifyGuidance(stage, $event.target.value)"
            />
            <span class="self-end text-[11px] text-n-slate-9">
              {{
                t('COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.CHAR_COUNT', {
                  count: (stage.notify_guidance || '').length,
                  max: NOTIFY_GUIDANCE_MAX,
                })
              }}
            </span>
          </div>
        </div>
      </div>

      <button
        v-for="stage in teamStages"
        :key="stage.stage_key"
        type="button"
        data-testid="post-cutoff-row"
        class="flex items-center justify-between gap-2 rounded-md border border-n-slate-5 bg-n-slate-2 px-3 py-1.5 text-left opacity-70"
        @click="moveCutoffTo(stage.stage_key)"
      >
        <span class="text-sm text-n-slate-10">{{
          stage.display_name || stage.stage_key
        }}</span>
        <span class="text-xs text-n-slate-9">{{
          t('COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.HANDLED_BY_TEAM')
        }}</span>
      </button>
    </div>
  </div>
</template>
