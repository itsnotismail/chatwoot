<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  summary: { type: String, default: '' },
  softWarnings: { type: Array, default: () => [] },
  isPublishing: { type: Boolean, default: false },
});

const emit = defineEmits(['confirm', 'cancel']);

const { t } = useI18n();
</script>

<template>
  <div
    data-testid="publish-confirm-modal"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
    @click.self="emit('cancel')"
  >
    <div
      class="w-full max-w-md rounded-lg bg-n-solid-1 p-6 flex flex-col gap-4 shadow-lg"
    >
      <h3 class="text-base font-semibold text-n-slate-12">
        {{ t('COMVOR_SETTINGS.DISCOVERY.PUBLISH_MODAL.TITLE') }}
      </h3>

      <p
        v-if="summary"
        data-testid="publish-modal-summary"
        class="text-sm text-n-slate-11"
      >
        {{ summary }}
      </p>

      <div
        v-if="softWarnings.length"
        data-testid="publish-modal-consequences"
        class="border border-amber-300 bg-amber-50 dark:bg-amber-900/30 dark:border-amber-700 rounded-md p-3 text-sm text-amber-700 dark:text-amber-300"
      >
        <h4 class="font-semibold mb-2">
          {{ t('COMVOR_SETTINGS.DISCOVERY.PUBLISH_MODAL.CONSEQUENCES_TITLE') }}
        </h4>
        <ul class="list-disc list-inside">
          <li
            v-for="(warn, idx) in softWarnings"
            :key="idx"
            data-testid="publish-modal-consequence-item"
          >
            {{
              t('COMVOR_SETTINGS.DISCOVERY.PUBLISH_MODAL.SOFT_WARNING', {
                capability: warn.capability,
              })
            }}
          </li>
        </ul>
      </div>

      <div class="flex items-center justify-end gap-3 pt-2">
        <button
          type="button"
          data-testid="publish-modal-cancel"
          class="rounded-lg border border-n-weak px-4 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-1"
          @click="emit('cancel')"
        >
          {{ t('COMVOR_SETTINGS.DISCOVERY.PUBLISH_MODAL.CANCEL') }}
        </button>
        <button
          type="button"
          data-testid="publish-modal-confirm"
          :disabled="isPublishing"
          class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white hover:bg-n-brand/90 disabled:opacity-50"
          @click="emit('confirm')"
        >
          {{
            isPublishing
              ? t('COMVOR_SETTINGS.DISCOVERY.PUBLISHING')
              : t('COMVOR_SETTINGS.DISCOVERY.PUBLISH_MODAL.CONFIRM')
          }}
        </button>
      </div>
    </div>
  </div>
</template>
