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

const isLoading = ref(false);
const isSaving = ref(false);
const isSavingCards = ref(false);

const TONE_OPTIONS = [
  { value: 'warm_friendly', label: t('COMVOR_SETTINGS.FIELDS.TONE.OPTIONS.WARM_FRIENDLY') },
  { value: 'playful',       label: t('COMVOR_SETTINGS.FIELDS.TONE.OPTIONS.PLAYFUL') },
  { value: 'professional',  label: t('COMVOR_SETTINGS.FIELDS.TONE.OPTIONS.PROFESSIONAL') },
  { value: 'concise',       label: t('COMVOR_SETTINGS.FIELDS.TONE.OPTIONS.CONCISE') },
];

const LEAD_CHIPS = [
  { key: 'NAME',    label: t('COMVOR_SETTINGS.INSTRUCTIONS.LEAD_COLLECTION.CHIPS.NAME') },
  { key: 'EMAIL',   label: t('COMVOR_SETTINGS.INSTRUCTIONS.LEAD_COLLECTION.CHIPS.EMAIL') },
  { key: 'PHONE',   label: t('COMVOR_SETTINGS.INSTRUCTIONS.LEAD_COLLECTION.CHIPS.PHONE') },
  { key: 'PRODUCT', label: t('COMVOR_SETTINGS.INSTRUCTIONS.LEAD_COLLECTION.CHIPS.PRODUCT') },
];

const AVOID_CHIPS = [
  { key: 'RETURNS',        label: t('COMVOR_SETTINGS.INSTRUCTIONS.AVOID_TOPICS.CHIPS.RETURNS') },
  { key: 'CUSTOM_PRICING', label: t('COMVOR_SETTINGS.INSTRUCTIONS.AVOID_TOPICS.CHIPS.CUSTOM_PRICING') },
  { key: 'COMPETITOR',     label: t('COMVOR_SETTINGS.INSTRUCTIONS.AVOID_TOPICS.CHIPS.COMPETITOR') },
];

const form = ref({
  agent_name: '',
  brand_voice: 'warm_friendly',
  business_description: '',
  website_url: '',
  phone: '',
  contact_email: '',
  location: '',
  operating_hours: '',
  timezone: '',
  currency: '',
  policies: {
    purchasing_info: '',
    payment_methods: '',
    shipping_delivery: '',
    promotions: '',
    returns_exchanges: '',
  },
  instruction_modules: {
    lead_collection: { enabled: false, chips: [], trigger: 'interest', custom: '' },
    avoid_topics: { enabled: false, chips: [], custom: '' },
    custom_instructions: '',
  },
});

const knowledgeCards = ref([]);

function authHeaders() {
  const token = store.getters.getCurrentUser?.access_token || '';
  return { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` };
}

function engineURL() {
  return window.globalConfig?.COMVOR_ENGINE_URL || '';
}

async function fetchSettings() {
  if (!engineURL()) return;
  isLoading.value = true;
  try {
    const [accRes, cardsRes] = await Promise.all([
      fetch(`${engineURL()}/api/accounts/${accountId}`, { headers: authHeaders() }),
      fetch(`${engineURL()}/api/accounts/${accountId}/knowledge-cards`, { headers: authHeaders() }),
    ]);
    if (!accRes.ok) throw new Error(`account HTTP ${accRes.status}`);
    if (!cardsRes.ok) throw new Error(`cards HTTP ${cardsRes.status}`);

    const data = await accRes.json();
    form.value = {
      agent_name:          data.agent_name || '',
      brand_voice:         data.brand_voice || 'warm_friendly',
      business_description: data.business_description || '',
      website_url:         data.website_url || '',
      phone:               data.phone || '',
      contact_email:       data.contact_email || '',
      location:            data.location || '',
      operating_hours:     data.operating_hours || '',
      timezone:            data.timezone || '',
      currency:            data.currency || '',
      policies: {
        purchasing_info:   data.policies?.purchasing_info || '',
        payment_methods:   data.policies?.payment_methods || '',
        shipping_delivery: data.policies?.shipping_delivery || '',
        promotions:        data.policies?.promotions || '',
        returns_exchanges: data.policies?.returns_exchanges || '',
      },
      instruction_modules: {
        lead_collection: {
          enabled: data.instruction_modules?.lead_collection?.enabled || false,
          chips:   data.instruction_modules?.lead_collection?.chips || [],
          trigger: data.instruction_modules?.lead_collection?.trigger || 'interest',
          custom:  data.instruction_modules?.lead_collection?.custom || '',
        },
        avoid_topics: {
          enabled: data.instruction_modules?.avoid_topics?.enabled || false,
          chips:   data.instruction_modules?.avoid_topics?.chips || [],
          custom:  data.instruction_modules?.avoid_topics?.custom || '',
        },
        custom_instructions: data.instruction_modules?.custom_instructions || '',
      },
    };

    knowledgeCards.value = await cardsRes.json();
  } catch (e) {
    useAlert(t('COMVOR_SETTINGS.FETCH_ERROR'));
  } finally {
    isLoading.value = false;
  }
}

async function saveSettings() {
  if (!engineURL()) return;
  isSaving.value = true;
  try {
    const res = await fetch(`${engineURL()}/api/accounts/${accountId}`, {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify(form.value),
    });
    if (!res.ok) {
      const msg = await res.text();
      throw new Error(msg || `HTTP ${res.status}`);
    }
    useAlert(t('COMVOR_SETTINGS.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('COMVOR_SETTINGS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
}

async function saveKnowledgeCards() {
  if (!engineURL()) return;
  isSavingCards.value = true;
  try {
    const res = await fetch(`${engineURL()}/api/accounts/${accountId}/knowledge-cards`, {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify(knowledgeCards.value),
    });
    if (!res.ok) {
      const msg = await res.text();
      throw new Error(msg || `HTTP ${res.status}`);
    }
    knowledgeCards.value = await res.json();
    useAlert(t('COMVOR_SETTINGS.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('COMVOR_SETTINGS.SAVE_ERROR'));
  } finally {
    isSavingCards.value = false;
  }
}

function addCard() {
  knowledgeCards.value.push({ id: 0, title: '', content: '', position: knowledgeCards.value.length });
}

function removeCard(index) {
  knowledgeCards.value.splice(index, 1);
}

function toggleChip(chipLabel, list) {
  const idx = list.indexOf(chipLabel);
  if (idx === -1) list.push(chipLabel);
  else list.splice(idx, 1);
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

      <!-- ── Section 1: Agent Identity ── -->
      <SectionLayout
        :title="t('COMVOR_SETTINGS.SECTION.IDENTITY.TITLE')"
        :description="t('COMVOR_SETTINGS.SECTION.IDENTITY.DESCRIPTION')"
      >
        <div class="grid grid-cols-2 gap-4">
          <label class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.AGENT_NAME.LABEL') }}</span>
            <input
              v-model="form.agent_name"
              type="text"
              maxlength="100"
              class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              :placeholder="t('COMVOR_SETTINGS.FIELDS.AGENT_NAME.PLACEHOLDER')"
            />
            <span class="text-xs text-n-slate-11">{{ t('COMVOR_SETTINGS.FIELDS.AGENT_NAME.HINT') }}</span>
          </label>

          <label class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.TONE.LABEL') }}</span>
            <select
              v-model="form.brand_voice"
              class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            >
              <option v-for="opt in TONE_OPTIONS" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
            </select>
            <span class="text-xs text-n-slate-11">{{ t('COMVOR_SETTINGS.FIELDS.TONE.HINT') }}</span>
          </label>
        </div>
      </SectionLayout>

      <!-- ── Section 2: Business Info ── -->
      <SectionLayout
        :title="t('COMVOR_SETTINGS.SECTION.BUSINESS.TITLE')"
        :description="t('COMVOR_SETTINGS.SECTION.BUSINESS.DESCRIPTION')"
        with-border
      >
        <div class="flex flex-col gap-4">
          <label class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.BUSINESS_DESCRIPTION.LABEL') }}</span>
            <textarea
              v-model="form.business_description"
              rows="3"
              maxlength="300"
              class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              :placeholder="t('COMVOR_SETTINGS.FIELDS.BUSINESS_DESCRIPTION.PLACEHOLDER')"
            />
            <span class="text-xs text-n-slate-11">{{ form.business_description.length }}/300 — {{ t('COMVOR_SETTINGS.FIELDS.BUSINESS_DESCRIPTION.HINT') }}</span>
          </label>

          <div class="grid grid-cols-2 gap-4">
            <label class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.WEBSITE_URL.LABEL') }}</span>
              <input v-model="form.website_url" type="url" maxlength="255"
                class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                :placeholder="t('COMVOR_SETTINGS.FIELDS.WEBSITE_URL.PLACEHOLDER')" />
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.PHONE.LABEL') }}</span>
              <input v-model="form.phone" type="tel" maxlength="50"
                class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                :placeholder="t('COMVOR_SETTINGS.FIELDS.PHONE.PLACEHOLDER')" />
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.CONTACT_EMAIL.LABEL') }}</span>
              <input v-model="form.contact_email" type="email" maxlength="255"
                class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                :placeholder="t('COMVOR_SETTINGS.FIELDS.CONTACT_EMAIL.PLACEHOLDER')" />
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.LOCATION.LABEL') }}</span>
              <input v-model="form.location" type="text" maxlength="255"
                class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                :placeholder="t('COMVOR_SETTINGS.FIELDS.LOCATION.PLACEHOLDER')" />
            </label>
          </div>

          <label class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.OPERATING_HOURS.LABEL') }}</span>
            <textarea v-model="form.operating_hours" rows="2" maxlength="300"
              class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              :placeholder="t('COMVOR_SETTINGS.FIELDS.OPERATING_HOURS.PLACEHOLDER')" />
          </label>

          <div class="grid grid-cols-2 gap-4">
            <label class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.TIMEZONE.LABEL') }}</span>
              <input v-model="form.timezone" type="text"
                class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                :placeholder="t('COMVOR_SETTINGS.FIELDS.TIMEZONE.PLACEHOLDER')" />
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.CURRENCY.LABEL') }}</span>
              <input v-model="form.currency" type="text"
                class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                :placeholder="t('COMVOR_SETTINGS.FIELDS.CURRENCY.PLACEHOLDER')" />
            </label>
          </div>
        </div>
      </SectionLayout>

      <!-- ── Section 3: Policies ── -->
      <SectionLayout
        :title="t('COMVOR_SETTINGS.SECTION.POLICIES.TITLE')"
        :description="t('COMVOR_SETTINGS.SECTION.POLICIES.DESCRIPTION')"
        with-border
      >
        <div class="flex flex-col gap-4">
          <label v-for="(policy, key) in form.policies" :key="key" class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t(`COMVOR_SETTINGS.FIELDS.POLICIES.${key.toUpperCase()}.LABEL`) }}
            </span>
            <textarea
              v-model="form.policies[key]"
              rows="3"
              class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              :placeholder="t(`COMVOR_SETTINGS.FIELDS.POLICIES.${key.toUpperCase()}.PLACEHOLDER`)"
            />
          </label>
        </div>
      </SectionLayout>

      <!-- ── Save button (sections 1-3) ── -->
      <div class="flex justify-end px-6 py-4 border-b border-n-weak">
        <button
          class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white hover:bg-n-brand/90 disabled:opacity-50"
          :disabled="isSaving"
          @click="saveSettings"
        >
          {{ isSaving ? t('COMVOR_SETTINGS.SAVING') : t('COMVOR_SETTINGS.SAVE') }}
        </button>
      </div>

      <!-- ── Section 4: Knowledge Cards ── -->
      <SectionLayout
        :title="t('COMVOR_SETTINGS.SECTION.KNOWLEDGE.TITLE')"
        :description="t('COMVOR_SETTINGS.SECTION.KNOWLEDGE.DESCRIPTION')"
        with-border
      >
        <div class="flex flex-col gap-3">
          <p v-if="knowledgeCards.length === 0" class="text-sm text-n-slate-11">
            {{ t('COMVOR_SETTINGS.FIELDS.KNOWLEDGE_CARDS.EMPTY_STATE') }}
          </p>

          <div
            v-for="(card, index) in knowledgeCards"
            :key="index"
            class="rounded-lg border border-n-weak bg-n-surface-1 p-4 flex flex-col gap-2"
          >
            <div class="flex items-center gap-2">
              <input
                v-model="card.title"
                type="text"
                maxlength="100"
                class="flex-1 rounded border border-n-weak bg-n-alpha-1 px-2 py-1 text-sm text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
                :placeholder="t('COMVOR_SETTINGS.FIELDS.KNOWLEDGE_CARDS.TITLE_PLACEHOLDER')"
              />
              <button
                class="text-n-slate-10 hover:text-n-red-9 text-xs px-2 py-1"
                @click="removeCard(index)"
              >✕</button>
            </div>
            <textarea
              v-model="card.content"
              rows="3"
              maxlength="1000"
              class="w-full rounded border border-n-weak bg-n-alpha-1 px-2 py-1 text-sm text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
              :placeholder="t('COMVOR_SETTINGS.FIELDS.KNOWLEDGE_CARDS.CONTENT_PLACEHOLDER')"
            />
            <span class="text-xs text-n-slate-11 text-right">{{ card.content.length }}/1000</span>
          </div>

          <div class="flex items-center justify-between mt-1">
            <button
              v-if="knowledgeCards.length < 20"
              class="text-sm text-n-brand hover:underline"
              @click="addCard"
            >+ {{ t('COMVOR_SETTINGS.FIELDS.KNOWLEDGE_CARDS.ADD_BUTTON') }}</button>
            <span v-else class="text-xs text-n-slate-11">Maximum 20 cards reached</span>

            <button
              class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white hover:bg-n-brand/90 disabled:opacity-50"
              :disabled="isSavingCards"
              @click="saveKnowledgeCards"
            >
              {{ isSavingCards ? t('COMVOR_SETTINGS.FIELDS.KNOWLEDGE_CARDS.SAVING_CARDS') : t('COMVOR_SETTINGS.FIELDS.KNOWLEDGE_CARDS.SAVE_CARDS') }}
            </button>
          </div>
        </div>
      </SectionLayout>

      <!-- ── Section 5: Instructions ── -->
      <SectionLayout
        :title="t('COMVOR_SETTINGS.SECTION.INSTRUCTIONS.TITLE')"
        :description="t('COMVOR_SETTINGS.SECTION.INSTRUCTIONS.DESCRIPTION')"
        with-border
      >
        <div class="flex flex-col gap-6">

          <!-- Collect leads -->
          <div class="flex flex-col gap-3">
            <div class="flex items-center gap-3">
              <input type="checkbox" v-model="form.instruction_modules.lead_collection.enabled"
                class="w-4 h-4 accent-n-brand" id="lead-toggle" />
              <label for="lead-toggle" class="text-sm font-medium text-n-slate-12">
                {{ t('COMVOR_SETTINGS.INSTRUCTIONS.LEAD_COLLECTION.TITLE') }}
              </label>
            </div>
            <p class="text-xs text-n-slate-11 ml-7">{{ t('COMVOR_SETTINGS.INSTRUCTIONS.LEAD_COLLECTION.DESCRIPTION') }}</p>

            <template v-if="form.instruction_modules.lead_collection.enabled">
              <div class="ml-7 flex flex-wrap gap-2">
                <button
                  v-for="chip in LEAD_CHIPS"
                  :key="chip.key"
                  class="rounded-full border px-3 py-1 text-xs transition-colors"
                  :class="form.instruction_modules.lead_collection.chips.includes(chip.label)
                    ? 'border-n-brand bg-n-brand/10 text-n-brand'
                    : 'border-n-weak text-n-slate-11 hover:border-n-brand'"
                  @click="toggleChip(chip.label, form.instruction_modules.lead_collection.chips)"
                >{{ chip.label }}</button>
              </div>

              <div class="ml-7">
                <label class="text-xs text-n-slate-11 mb-1 block">{{ t('COMVOR_SETTINGS.INSTRUCTIONS.LEAD_COLLECTION.TRIGGER_LABEL') }}</label>
                <select v-model="form.instruction_modules.lead_collection.trigger"
                  class="rounded border border-n-weak bg-n-surface-1 px-2 py-1 text-sm text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand">
                  <option value="interest">{{ t('COMVOR_SETTINGS.INSTRUCTIONS.LEAD_COLLECTION.TRIGGER_INTEREST') }}</option>
                  <option value="greeting">{{ t('COMVOR_SETTINGS.INSTRUCTIONS.LEAD_COLLECTION.TRIGGER_GREETING') }}</option>
                </select>
              </div>

              <textarea
                v-model="form.instruction_modules.lead_collection.custom"
                rows="2"
                maxlength="500"
                class="ml-7 w-[calc(100%-1.75rem)] rounded border border-n-weak bg-n-surface-1 px-2 py-1 text-sm text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
                :placeholder="t('COMVOR_SETTINGS.INSTRUCTIONS.LEAD_COLLECTION.CUSTOM_PLACEHOLDER')"
              />
            </template>
          </div>

          <!-- Avoid certain topics -->
          <div class="flex flex-col gap-3">
            <div class="flex items-center gap-3">
              <input type="checkbox" v-model="form.instruction_modules.avoid_topics.enabled"
                class="w-4 h-4 accent-n-brand" id="avoid-toggle" />
              <label for="avoid-toggle" class="text-sm font-medium text-n-slate-12">
                {{ t('COMVOR_SETTINGS.INSTRUCTIONS.AVOID_TOPICS.TITLE') }}
              </label>
            </div>
            <p class="text-xs text-n-slate-11 ml-7">{{ t('COMVOR_SETTINGS.INSTRUCTIONS.AVOID_TOPICS.DESCRIPTION') }}</p>

            <template v-if="form.instruction_modules.avoid_topics.enabled">
              <div class="ml-7 flex flex-wrap gap-2">
                <button
                  v-for="chip in AVOID_CHIPS"
                  :key="chip.key"
                  class="rounded-full border px-3 py-1 text-xs transition-colors"
                  :class="form.instruction_modules.avoid_topics.chips.includes(chip.label)
                    ? 'border-n-brand bg-n-brand/10 text-n-brand'
                    : 'border-n-weak text-n-slate-11 hover:border-n-brand'"
                  @click="toggleChip(chip.label, form.instruction_modules.avoid_topics.chips)"
                >{{ chip.label }}</button>
              </div>

              <textarea
                v-model="form.instruction_modules.avoid_topics.custom"
                rows="2"
                maxlength="500"
                class="ml-7 w-[calc(100%-1.75rem)] rounded border border-n-weak bg-n-surface-1 px-2 py-1 text-sm text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
                :placeholder="t('COMVOR_SETTINGS.INSTRUCTIONS.AVOID_TOPICS.CUSTOM_PLACEHOLDER')"
              />
            </template>
          </div>

          <!-- Custom instructions -->
          <div class="flex flex-col gap-2">
            <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.INSTRUCTIONS.CUSTOM.TITLE') }}</span>
            <p class="text-xs text-n-slate-11">{{ t('COMVOR_SETTINGS.INSTRUCTIONS.CUSTOM.DESCRIPTION') }}</p>
            <textarea
              v-model="form.instruction_modules.custom_instructions"
              rows="3"
              maxlength="1000"
              class="w-full rounded border border-n-weak bg-n-surface-1 px-2 py-1 text-sm text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
              :placeholder="t('COMVOR_SETTINGS.INSTRUCTIONS.CUSTOM.PLACEHOLDER')"
            />
            <span class="text-xs text-n-slate-11 text-right">{{ form.instruction_modules.custom_instructions.length }}/1000</span>
          </div>
        </div>
      </SectionLayout>

      <!-- ── Final Save button (sections 1-2-3-5) ── -->
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
