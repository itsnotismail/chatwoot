<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  engineUrl: { type: String, required: true },
  authHeaders: { type: Function, required: true },
});
const emit = defineEmits(['provisioned']);
const { t } = useI18n();

const businessCategory = ref('');
const verticals = ref([]);
const businessName = ref('');
const businessDescription = ref('');
const submitting = ref(false);
const error = ref('');

const canSubmit = computed(
  () =>
    businessCategory.value &&
    businessName.value.trim() &&
    businessDescription.value.trim() &&
    !submitting.value
);

async function fetchVerticals() {
  try {
    const res = await fetch(`${props.engineUrl}/api/verticals`, {
      headers: props.authHeaders(),
    });
    if (res.ok) verticals.value = await res.json();
  } catch (_) {
    /* non-fatal: dropdown falls back to empty until retry */
  }
}

onMounted(fetchVerticals);

async function submit() {
  submitting.value = true;
  error.value = '';
  try {
    const res = await fetch(
      `${props.engineUrl}/api/accounts/${props.accountId}`,
      {
        method: 'POST',
        headers: props.authHeaders(),
        body: JSON.stringify({
          business_category: businessCategory.value,
          business_name: businessName.value.trim(),
          business_description: businessDescription.value.trim(),
        }),
      }
    );
    if (res.status === 409) {
      const getRes = await fetch(
        `${props.engineUrl}/api/accounts/${props.accountId}`,
        {
          headers: props.authHeaders(),
        }
      );
      emit('provisioned', await getRes.json());
      return;
    }
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    emit('provisioned', await res.json());
  } catch (e) {
    error.value = t('COMVOR_SETTINGS.ONBOARDING.ERROR');
  } finally {
    submitting.value = false;
  }
}
</script>

<template>
  <div class="mx-auto flex max-w-xl flex-col gap-4 py-12">
    <h2 class="text-lg font-semibold text-n-slate-12">
      {{ t('COMVOR_SETTINGS.ONBOARDING.TITLE') }}
    </h2>
    <p class="text-sm text-n-slate-11">
      {{ t('COMVOR_SETTINGS.ONBOARDING.DESCRIPTION') }}
    </p>

    <label class="flex flex-col gap-1">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('COMVOR_SETTINGS.ONBOARDING.CATEGORY.LABEL') }}
      </span>
      <select
        v-model="businessCategory"
        class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
      >
        <option v-for="v in verticals" :key="v.key" :value="v.key">
          {{ v.display_name }}
        </option>
      </select>
    </label>

    <label class="flex flex-col gap-1">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('COMVOR_SETTINGS.ONBOARDING.BUSINESS_NAME.LABEL') }}
      </span>
      <input
        v-model="businessName"
        type="text"
        maxlength="255"
        class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        :placeholder="t('COMVOR_SETTINGS.ONBOARDING.BUSINESS_NAME.PLACEHOLDER')"
      />
    </label>

    <label class="flex flex-col gap-1">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('COMVOR_SETTINGS.ONBOARDING.BUSINESS_DESCRIPTION.LABEL') }}
      </span>
      <textarea
        v-model="businessDescription"
        rows="3"
        maxlength="300"
        class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        :placeholder="
          t('COMVOR_SETTINGS.ONBOARDING.BUSINESS_DESCRIPTION.PLACEHOLDER')
        "
      />
    </label>

    <p v-if="error" class="text-sm text-n-ruby-9">{{ error }}</p>

    <button
      class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white hover:bg-n-brand/90 disabled:opacity-50"
      :disabled="!canSubmit"
      @click="submit"
    >
      {{
        submitting
          ? t('COMVOR_SETTINGS.ONBOARDING.SUBMITTING')
          : t('COMVOR_SETTINGS.ONBOARDING.SUBMIT')
      }}
    </button>
  </div>
</template>
