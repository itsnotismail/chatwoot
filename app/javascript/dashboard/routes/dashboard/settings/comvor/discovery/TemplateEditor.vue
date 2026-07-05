<script setup>
import { computed, nextTick, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

// `row` is a routing row from NotificationsEditor: { event, isStage, template, ... }.
// `defaultTemplate` is this row's event's built-in default template string,
// sourced from the API's `default_templates` map (threaded down through
// NotificationsTab -> NotificationsEditor -> here). The field is always
// pre-filled with this default when there is no saved custom template.
const props = defineProps({
  row: { type: Object, required: true },
  defaultTemplate: { type: String, default: '' },
});

const emit = defineEmits(['chip', 'template', 'startFromDefault', 'register']);

const { t } = useI18n();

const TEMPLATE_MAX = 1000;

function defaultTemplateFor() {
  return props.defaultTemplate || '';
}

// Placeholder chip sets per event, as [i18n label key, token] pairs.
const NEW_ORDER_CHIPS = [
  ['CHIP_ITEMS', '{items}'],
  ['CHIP_ADDRESS', '{address}'],
  ['CHIP_PHONE', '{phone}'],
  ['CHIP_PAYMENT', '{payment}'],
  ['CHIP_SUMMARY', '{summary}'],
  ['CHIP_LINK', '{link}'],
];
const HANDOFF_CHIPS = [
  ['CHIP_REASON', '{reason}'],
  ['CHIP_LINK', '{link}'],
];
const RESOLVED_CHIPS = [
  ['CHIP_SUMMARY', '{summary}'],
  ['CHIP_LINK', '{link}'],
];
const STAGE_CHIPS = [
  ['CHIP_STAGE', '{stage}'],
  ['CHIP_SUMMARY', '{summary}'],
  ['CHIP_LINK', '{link}'],
];

const chips = computed(() => {
  if (props.row.isStage) return STAGE_CHIPS;
  if (props.row.event === 'new_order') return NEW_ORDER_CHIPS;
  if (props.row.event === 'handoff') return HANDOFF_CHIPS;
  if (props.row.event === 'resolved') return RESOLVED_CHIPS;
  return [];
});

// Sample data used to render the live preview — mirrors the backend's
// substitution semantics (render() in notifier.go): named placeholders with
// no sample value fall back to an em-dash, everything else (stage/summary/
// link) substitutes verbatim, and any remaining unknown token is left as-is.
// Values here are deliberately generic placeholders (not a real order) so the
// preview clearly reads as a sample, not live customer data.
const PREVIEW_SAMPLE = {
  items: '• Sample product ×1 — MVR 100\n• Another item ×2 — MVR 250',
  address: '123 Example Road, Malé',
  phone: '7XXXXXX',
  payment: 'Bank transfer',
  stage: 'Order taking',
  summary: 'Short summary of the conversation',
  reason: 'customer asked for a human',
  link: 'https://…/conversation',
};
const EM_DASH = '—';
const NAMED_PLACEHOLDER_KEYS = ['items', 'address', 'phone', 'payment'];

// Pure client-side mirror of the backend's render(): named placeholder keys
// fall back to an em-dash when the sample has no value, other known sample
// keys (stage/summary/link) substitute verbatim, and any remaining `{token}`
// is left untouched.
function substitute(template, sample) {
  let out = template;
  NAMED_PLACEHOLDER_KEYS.forEach(key => {
    const value = sample[key] || EM_DASH;
    out = out.split(`{${key}}`).join(value);
  });
  Object.entries(sample).forEach(([key, value]) => {
    if (NAMED_PLACEHOLDER_KEYS.includes(key)) return;
    out = out.split(`{${key}}`).join(value);
  });
  return out;
}

const effectiveTemplate = computed(
  () => props.row.template || defaultTemplateFor()
);

const preview = computed(() =>
  substitute(effectiveTemplate.value, PREVIEW_SAMPLE)
);

function onChipClick(token) {
  emit('chip', token);
}

// Auto-height: the textarea grows with its content (no scrolling) between a
// sane minimum (~3 rows) and maximum (~12 rows), then scrolls beyond that.
const textareaEl = ref(null);
const MIN_HEIGHT = 72; // ~3 rows
const MAX_HEIGHT = 288; // ~12 rows

function resizeToContent() {
  const el = textareaEl.value;
  if (!el) return;
  el.style.height = 'auto';
  const next = Math.min(Math.max(el.scrollHeight, MIN_HEIGHT), MAX_HEIGHT);
  el.style.height = `${next}px`;
  el.style.overflowY = el.scrollHeight > MAX_HEIGHT ? 'auto' : 'hidden';
}

function onStartFromDefault() {
  emit('startFromDefault', defaultTemplateFor());
  nextTick(resizeToContent);
}

function registerTextarea(el) {
  textareaEl.value = el;
  emit('register', el);
}

function onInput(event) {
  emit('template', event.target.value);
  resizeToContent();
}

onMounted(resizeToContent);

// Exposed for a direct unit test of the em-dash fallback (see
// TemplateEditor.spec.js) — PREVIEW_SAMPLE itself now has every named
// placeholder populated, so the fallback is otherwise unreachable from the
// live preview and needs to be exercised against a sample that deliberately
// omits a value. `resizeToContent` is exposed so a unit test can assert the
// height calc directly.
defineExpose({ substitute, resizeToContent });
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <textarea
      :ref="el => registerTextarea(el)"
      data-testid="route-template-input"
      rows="3"
      :value="row.template"
      :maxlength="TEMPLATE_MAX"
      :placeholder="t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.TEMPLATE_LABEL')"
      class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand resize-none"
      @input="onInput"
    />

    <div class="flex flex-wrap items-center gap-1.5">
      <button
        v-for="[labelKey, token] in chips"
        :key="labelKey"
        type="button"
        data-testid="template-chip"
        class="rounded-full border border-n-weak bg-n-surface-1 px-2 py-0.5 text-xs text-n-slate-11 hover:bg-n-slate-3"
        @click="onChipClick(token)"
      >
        {{ t(`COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.${labelKey}`) }}
      </button>
    </div>

    <div class="flex items-center justify-between gap-2">
      <span class="text-xs text-n-slate-10">
        {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.TEMPLATE_HINT') }}
      </span>
      <button
        type="button"
        data-testid="template-start-from-default"
        class="shrink-0 text-xs text-n-brand"
        @click="onStartFromDefault"
      >
        {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.RESET_TO_DEFAULT') }}
      </button>
    </div>

    <div
      data-testid="template-preview"
      class="rounded-lg bg-n-slate-3 px-3 py-2 text-xs text-n-slate-12 whitespace-pre-wrap"
    >
      <span class="mb-1 block font-medium text-n-slate-10">
        {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.PREVIEW_LABEL') }}
      </span>
      {{ preview }}
    </div>
  </div>
</template>
