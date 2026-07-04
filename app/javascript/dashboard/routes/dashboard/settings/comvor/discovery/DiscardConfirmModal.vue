<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  isDiscarding: { type: Boolean, default: false },
});

const emit = defineEmits(['confirm', 'cancel']);

const { t } = useI18n();
</script>

<template>
  <div
    data-testid="discard-confirm-modal"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
    @click.self="emit('cancel')"
  >
    <div
      class="w-full max-w-md rounded-lg bg-n-solid-1 p-6 flex flex-col gap-4 shadow-lg"
    >
      <h3 class="text-base font-semibold text-n-slate-12">
        {{ t('COMVOR_SETTINGS.DISCOVERY.DISCARD_MODAL.TITLE') }}
      </h3>

      <p class="text-sm text-n-slate-11">
        {{ t('COMVOR_SETTINGS.DISCOVERY.DISCARD_MODAL.BODY') }}
      </p>

      <div class="flex items-center justify-end gap-3 pt-2">
        <button
          type="button"
          data-testid="discard-modal-cancel"
          class="rounded-lg border border-n-weak px-4 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-1"
          @click="emit('cancel')"
        >
          {{ t('COMVOR_SETTINGS.DISCOVERY.DISCARD_MODAL.CANCEL') }}
        </button>
        <button
          type="button"
          data-testid="discard-modal-confirm"
          :disabled="isDiscarding"
          class="rounded-lg border border-red-300 bg-red-50 px-4 py-2 text-sm font-medium text-red-700 hover:bg-red-100 disabled:opacity-50 dark:bg-red-900/30 dark:border-red-700 dark:text-red-300"
          @click="emit('confirm')"
        >
          {{
            isDiscarding
              ? t('COMVOR_SETTINGS.DISCOVERY.DISCARDING')
              : t('COMVOR_SETTINGS.DISCOVERY.DISCARD_MODAL.CONFIRM')
          }}
        </button>
      </div>
    </div>
  </div>
</template>
