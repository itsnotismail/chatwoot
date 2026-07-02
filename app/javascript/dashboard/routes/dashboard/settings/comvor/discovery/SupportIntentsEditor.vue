<script setup>
import { reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  flow: { type: Object, required: true },
  walls: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:stage']);

const { t } = useI18n();

const GUIDANCE_MAX = 2000;
const NOTIFY_GUIDANCE_MAX = 500;

// Which stages currently have their row expanded — purely local UI state,
// re-seeded (collapsed) whenever the flow reloads.
const expanded = reactive({});

watch(
  () => props.flow,
  flow => {
    (flow.stages || []).forEach(stage => {
      if (!(stage.stage_key in expanded)) {
        expanded[stage.stage_key] = false;
      }
    });
  },
  { immediate: true }
);

function wallFor(stageKey) {
  return props.walls.find(
    w => w.flow_key === props.flow.flow_key && w.stage_key === stageKey
  );
}

// A wall on a stage is either:
//  - a "read wall": the stage has no action capability (has_action === false),
//    so the wall is blocking the read this intent depends on. Nothing on the
//    card can fix that — the row stays disabled until a connector is added.
//  - an "action wall": the stage has an action capability (has_action ===
//    true) and the wall is on that action. The fix is on the card itself
//    (switch who-completes to "Bot prepares, your team completes"), so the
//    row stays fully editable and just shows a suggestion badge.
function isReadWall(stage) {
  return !!wallFor(stage.stage_key) && !stage.has_action;
}

function isActionWall(stage) {
  return !!wallFor(stage.stage_key) && !!stage.has_action;
}

function toggleExpanded(stageKey) {
  expanded[stageKey] = !expanded[stageKey];
}

function emitStageUpdate(stage, fields) {
  emit('update:stage', {
    flow_key: props.flow.flow_key,
    stage_key: stage.stage_key,
    ...fields,
  });
}

function setEnabled(stage, enabled) {
  emitStageUpdate(stage, { skipped: !enabled });
}

function setActionMode(stage, mode) {
  emitStageUpdate(stage, { action_mode: mode });
}

function setFinish(stage, finish) {
  emitStageUpdate(stage, { on_complete: finish });
}

function setNotifyEnabled(stage, enabled) {
  emitStageUpdate(stage, { notify_enabled: enabled });
}

function setNotifyGuidance(stage, value) {
  emitStageUpdate(stage, { notify_guidance: value });
}

function setGuidance(stage, value) {
  emitStageUpdate(stage, { guidance: value });
}
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      v-for="stage in flow.stages"
      :key="stage.stage_key"
      data-testid="intent-row"
      class="border rounded-md p-3 flex flex-col gap-2"
      :class="{ 'opacity-60': stage.skipped }"
    >
      <div class="flex items-center gap-2">
        <input
          type="checkbox"
          data-testid="enable-toggle"
          :checked="!stage.skipped"
          :disabled="isReadWall(stage)"
          class="w-4 h-4 accent-n-brand shrink-0"
          @change="setEnabled(stage, $event.target.checked)"
        />
        <button
          type="button"
          data-testid="row-expand-toggle"
          class="flex-1 flex items-center justify-between gap-2 text-left"
          :disabled="stage.skipped"
          @click="toggleExpanded(stage.stage_key)"
        >
          <span class="text-sm">
            <span class="font-medium text-n-slate-12">{{
              stage.display_name || stage.stage_key
            }}</span>
            <span v-if="stage.description" class="text-n-slate-10">
              — {{ stage.description }}</span
            >
          </span>
          <span
            v-if="!stage.skipped"
            class="text-xs text-n-slate-9 shrink-0"
            aria-hidden="true"
            >{{
              expanded[stage.stage_key]
                ? t('COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.COLLAPSE_LABEL')
                : t('COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.EXPAND_LABEL')
            }}</span
          >
        </button>
      </div>

      <p
        v-if="isReadWall(stage)"
        data-testid="read-wall-message"
        class="text-xs text-amber-700 dark:text-amber-400 ml-6"
      >
        {{ wallFor(stage.stage_key).message }}
        {{ t('COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.READ_WALL_POINTER') }}
      </p>

      <div
        v-if="!stage.skipped && expanded[stage.stage_key]"
        class="flex flex-col gap-3 ml-6"
      >
        <span
          v-if="isActionWall(stage)"
          data-testid="action-wall-badge"
          class="self-start text-xs px-1.5 rounded bg-amber-100 text-amber-800"
        >
          {{ wallFor(stage.stage_key).message }}
          {{ t('COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.ACTION_WALL_BADGE') }}
        </span>

        <label v-if="stage.has_action" class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">{{
            t('COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.WHO_COMPLETES_LABEL')
          }}</span>
          <select
            data-testid="who-completes-select"
            :value="stage.action_mode || 'auto'"
            class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            @change="setActionMode(stage, $event.target.value)"
          >
            <option value="auto">
              {{
                t('COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.WHO_COMPLETES_AUTO')
              }}
            </option>
            <option value="deferred">
              {{
                t(
                  'COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.WHO_COMPLETES_DEFERRED'
                )
              }}
            </option>
          </select>
        </label>

        <div class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">{{
            t('COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.FINISH_LABEL')
          }}</span>
          <div class="flex items-center gap-4">
            <label class="flex items-center gap-1.5 text-xs">
              <input
                type="radio"
                data-testid="finish-handoff-radio"
                :name="`finish-${stage.stage_key}`"
                :checked="stage.on_complete === 'handoff'"
                @change="setFinish(stage, 'handoff')"
              />
              {{ t('COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.FINISH_HANDOFF') }}
            </label>
            <label class="flex items-center gap-1.5 text-xs">
              <input
                type="radio"
                data-testid="finish-resolve-radio"
                :name="`finish-${stage.stage_key}`"
                :checked="stage.on_complete === 'resolve'"
                @change="setFinish(stage, 'resolve')"
              />
              {{ t('COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.FINISH_RESOLVE') }}
            </label>
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
            <span class="text-xs font-medium text-n-slate-12">{{
              t('COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.NOTIFY_TOGGLE_LABEL')
            }}</span>
          </label>
          <div v-if="stage.notify_enabled" class="flex flex-col gap-1 ml-6">
            <span class="text-xs font-medium text-n-slate-12">{{
              t(
                'COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.NOTIFY_GUIDANCE_LABEL'
              )
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
                t('COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.CHAR_COUNT', {
                  count: (stage.notify_guidance || '').length,
                  max: NOTIFY_GUIDANCE_MAX,
                })
              }}
            </span>
          </div>
        </div>

        <div class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">{{
            t('COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.GUIDANCE_LABEL')
          }}</span>
          <p class="text-[11px] text-n-slate-9">
            {{ t('COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.GUIDANCE_HINT') }}
          </p>
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
              t('COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.CHAR_COUNT', {
                count: (stage.guidance || '').length,
                max: GUIDANCE_MAX,
              })
            }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>
