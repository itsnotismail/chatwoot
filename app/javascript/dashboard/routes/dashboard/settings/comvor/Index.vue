<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SectionLayout from '../account/components/SectionLayout.vue';

const { t } = useI18n();
const store = useStore();
const route = useRoute();

const accountId = route.params.accountId;
const engineURL = window.chatwootConfig?.COMVOR_ENGINE_URL || '';

const isLoading = ref(false);
const isSaving = ref(false);

const form = ref({
  business_description: '',
  brand_voice: '',
  faq_text: '',
  operating_hours: '',
  timezone: '',
  currency: '',
});

function authHeaders() {
  const token = store.getters.getCurrentUser?.access_token || '';
  return {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${token}`,
  };
}

async function fetchSettings() {
  if (!engineURL) return;
  isLoading.value = true;
  try {
    const res = await fetch(`${engineURL}/api/accounts/${accountId}`, {
      headers: authHeaders(),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    form.value = {
      business_description: data.business_description || '',
      brand_voice: data.brand_voice || '',
      faq_text: data.faq_text || '',
      operating_hours: data.operating_hours || '',
      timezone: data.timezone || '',
      currency: data.currency || '',
    };
  } catch (e) {
    useAlert(t('COMVOR_SETTINGS.FETCH_ERROR'));
  } finally {
    isLoading.value = false;
  }
}

async function saveSettings() {
  if (!engineURL) return;
  isSaving.value = true;
  try {
    const res = await fetch(`${engineURL}/api/accounts/${accountId}`, {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify(form.value),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    useAlert(t('COMVOR_SETTINGS.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(t('COMVOR_SETTINGS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
}

onMounted(fetchSettings);
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :loading-message="t('COMVOR_SETTINGS.LOADING')"
    :no-records-message="''"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('COMVOR_SETTINGS.TITLE')"
        :description="t('COMVOR_SETTINGS.DESCRIPTION')"
        icon-name="bot-message-square"
      />
    </template>
    <template #body>
      <SectionLayout
        :title="t('COMVOR_SETTINGS.SECTION.BUSINESS.TITLE')"
        :description="t('COMVOR_SETTINGS.SECTION.BUSINESS.DESCRIPTION')"
      >
        <div class="flex flex-col gap-4">
          <label class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.BUSINESS_DESCRIPTION.LABEL') }}</span>
            <textarea
              v-model="form.business_description"
              rows="4"
              class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              :placeholder="t('COMVOR_SETTINGS.FIELDS.BUSINESS_DESCRIPTION.PLACEHOLDER')"
            />
          </label>

          <label class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.BRAND_VOICE.LABEL') }}</span>
            <textarea
              v-model="form.brand_voice"
              rows="3"
              class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              :placeholder="t('COMVOR_SETTINGS.FIELDS.BRAND_VOICE.PLACEHOLDER')"
            />
          </label>

          <label class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.FAQ_TEXT.LABEL') }}</span>
            <textarea
              v-model="form.faq_text"
              rows="5"
              class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              :placeholder="t('COMVOR_SETTINGS.FIELDS.FAQ_TEXT.PLACEHOLDER')"
            />
          </label>
        </div>
      </SectionLayout>

      <SectionLayout
        :title="t('COMVOR_SETTINGS.SECTION.OPERATIONS.TITLE')"
        :description="t('COMVOR_SETTINGS.SECTION.OPERATIONS.DESCRIPTION')"
        with-border
      >
        <div class="flex flex-col gap-4">
          <label class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.OPERATING_HOURS.LABEL') }}</span>
            <textarea
              v-model="form.operating_hours"
              rows="2"
              class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              :placeholder="t('COMVOR_SETTINGS.FIELDS.OPERATING_HOURS.PLACEHOLDER')"
            />
          </label>

          <div class="grid grid-cols-2 gap-4">
            <label class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.TIMEZONE.LABEL') }}</span>
              <input
                v-model="form.timezone"
                type="text"
                class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                :placeholder="t('COMVOR_SETTINGS.FIELDS.TIMEZONE.PLACEHOLDER')"
              />
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.CURRENCY.LABEL') }}</span>
              <input
                v-model="form.currency"
                type="text"
                class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                :placeholder="t('COMVOR_SETTINGS.FIELDS.CURRENCY.PLACEHOLDER')"
              />
            </label>
          </div>
        </div>
      </SectionLayout>

      <div class="flex justify-end px-6 py-4">
        <button
          class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white hover:bg-n-brand/90 disabled:opacity-50"
          :disabled="isSaving"
          @click="saveSettings"
        >
          {{ isSaving ? t('COMVOR_SETTINGS.SAVING') : t('COMVOR_SETTINGS.SAVE') }}
        </button>
      </div>
    </template>
  </SettingsLayout>
</template>
