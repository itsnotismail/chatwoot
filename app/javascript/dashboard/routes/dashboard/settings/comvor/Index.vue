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
const selectedTab = ref(0);

// Single source of truth for Ewity permissions shown in the Connector tab.
// To add a future optional permission (e.g. create_sale): add an entry here
// with required: false — it renders as a toggleable checkbox automatically.
// Required permissions are locked on and always sent on save; the backend
// (internal/connectors/ewity/ewity.go AllPermissions) enforces this
// independently and is the source of truth for validation.
const EWITY_PERMISSIONS = [
  { key: 'search_products', labelKey: 'PERM_SEARCH_PRODUCTS', required: true },
  { key: 'get_product', labelKey: 'PERM_GET_PRODUCT', required: true },
];
const EWITY_REQUIRED_PERMISSIONS = EWITY_PERMISSIONS.filter(p => p.required).map(p => p.key);

const connectorType = ref('none');
const ewityToken = ref('');
const ewityTokenHint = ref('');
const ewityOptionalPermissions = ref([]);
const isSavingConnector = ref(false);
const permissionTestState = ref({});
const permissionTestMessage = ref({});

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

const POLICY_LIMITS = {
  purchasing_info: 800,
  payment_methods: 400,
  shipping_delivery: 800,
  promotions: 1000,
  returns_exchanges: 1000,
};

const form = ref({
  agent_name: '',
  brand_voice: 'warm_friendly',
  business_name: '',
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

    const data = await accRes.json();
    form.value = {
      agent_name:          data.agent_name || '',
      brand_voice:         data.brand_voice || 'warm_friendly',
      business_name:       data.business_name || '',
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

    if (cardsRes.ok) knowledgeCards.value = await cardsRes.json();

    connectorType.value = data.connector_type || 'none';
    if (connectorType.value === 'ewity') {
      try {
        const ewityRes = await fetch(
          `${engineURL()}/api/accounts/${accountId}/connectors/ewity`,
          { headers: authHeaders() }
        );
        if (ewityRes.ok) {
          const ewityData = await ewityRes.json();
          ewityTokenHint.value = ewityData.token_hint || '';
          const saved = ewityData.permissions || [];
          ewityOptionalPermissions.value = EWITY_PERMISSIONS
            .filter(p => !p.required && saved.includes(p.key))
            .map(p => p.key);
        }
      } catch (_) { /* non-fatal */ }
    }
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

async function saveConnector() {
  if (!engineURL()) return;
  isSavingConnector.value = true;
  try {
    // Send the full form alongside connector_type — this PUT endpoint does a
    // full-replace of profile fields, so a connector_type-only body would
    // wipe agent_name, business_name, etc. back to empty.
    const res = await fetch(`${engineURL()}/api/accounts/${accountId}`, {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({ ...form.value, connector_type: connectorType.value }),
    });
    if (!res.ok) {
      const msg = await res.text();
      throw new Error(msg || `HTTP ${res.status}`);
    }
    if (connectorType.value === 'ewity') {
      const body = { permissions: [...EWITY_REQUIRED_PERMISSIONS, ...ewityOptionalPermissions.value] };
      if (ewityToken.value) body.api_token = ewityToken.value;
      const res = await fetch(`${engineURL()}/api/accounts/${accountId}/connectors/ewity`, {
        method: 'PUT',
        headers: authHeaders(),
        body: JSON.stringify(body),
      });
      if (res.ok) {
        const refreshed = await fetch(
          `${engineURL()}/api/accounts/${accountId}/connectors/ewity`,
          { headers: authHeaders() }
        );
        if (refreshed.ok) {
          ewityTokenHint.value = (await refreshed.json()).token_hint || '';
          ewityToken.value = '';
        }
      }
    }
    useAlert(t('COMVOR_SETTINGS.CONNECTOR.EWITY.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('COMVOR_SETTINGS.CONNECTOR.EWITY.SAVE_ERROR'));
  } finally {
    isSavingConnector.value = false;
  }
}

async function testPermission(permission) {
  if (!engineURL()) return;
  permissionTestState.value[permission] = 'testing';
  permissionTestMessage.value[permission] = '';
  try {
    const body = { permission };
    if (ewityToken.value) body.api_token = ewityToken.value;
    const res = await fetch(
      `${engineURL()}/api/accounts/${accountId}/connectors/ewity/test`,
      {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify(body),
      }
    );
    const data = await res.json();
    if (data.ok) {
      permissionTestState.value[permission] = 'ok';
    } else {
      permissionTestState.value[permission] = 'error';
      const reasonKey = {
        permission_denied: 'TEST_PERMISSION_DENIED',
        invalid_token: 'TEST_INVALID_TOKEN',
        unreachable: 'TEST_UNREACHABLE',
      }[data.reason] || 'TEST_UNREACHABLE';
      permissionTestMessage.value[permission] = t(`COMVOR_SETTINGS.CONNECTOR.EWITY.${reasonKey}`);
    }
  } catch (_) {
    permissionTestState.value[permission] = 'error';
    permissionTestMessage.value[permission] = t('COMVOR_SETTINGS.CONNECTOR.EWITY.TEST_UNREACHABLE');
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
      <woot-tabs
        class="[&_ul]:p-0"
        :index="selectedTab"
        :border="false"
        @change="selectedTab = $event"
      >
        <woot-tabs-item :index="0" :name="t('COMVOR_SETTINGS.TABS.PROFILE')" :show-badge="false" is-compact />
        <woot-tabs-item :index="1" :name="t('COMVOR_SETTINGS.TABS.POLICIES')" :show-badge="false" is-compact />
        <woot-tabs-item :index="2" :name="t('COMVOR_SETTINGS.TABS.KNOWLEDGE')" :show-badge="false" is-compact />
        <woot-tabs-item :index="3" :name="t('COMVOR_SETTINGS.TABS.INSTRUCTIONS')" :show-badge="false" is-compact />
        <woot-tabs-item :index="4" :name="t('COMVOR_SETTINGS.TABS.CONNECTOR')" :show-badge="false" is-compact />
      </woot-tabs>
    </template>

    <template #body>

      <!-- ── Tab 0: Profile ── -->
      <template v-if="selectedTab === 0">
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

        <SectionLayout
          :title="t('COMVOR_SETTINGS.SECTION.BUSINESS.TITLE')"
          :description="t('COMVOR_SETTINGS.SECTION.BUSINESS.DESCRIPTION')"
          with-border
        >
          <div class="flex flex-col gap-4">
            <label class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.BUSINESS_NAME.LABEL') }}</span>
              <input v-model="form.business_name" type="text" maxlength="255"
                class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                :placeholder="t('COMVOR_SETTINGS.FIELDS.BUSINESS_NAME.PLACEHOLDER')" />
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.FIELDS.BUSINESS_DESCRIPTION.LABEL') }}</span>
              <textarea
                v-model="form.business_description"
                rows="3"
                maxlength="300"
                class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                :placeholder="t('COMVOR_SETTINGS.FIELDS.BUSINESS_DESCRIPTION.PLACEHOLDER')"
              />
              <span class="text-xs text-n-slate-11">{{ (form.business_description || '').length }}/300 — {{ t('COMVOR_SETTINGS.FIELDS.BUSINESS_DESCRIPTION.HINT') }}</span>
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
                <input v-model="form.currency" type="text" maxlength="10"
                  class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                  :placeholder="t('COMVOR_SETTINGS.FIELDS.CURRENCY.PLACEHOLDER')" />
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

      <!-- ── Tab 1: Policies ── -->
      <template v-else-if="selectedTab === 1">
        <SectionLayout
          :title="t('COMVOR_SETTINGS.SECTION.POLICIES.TITLE')"
          :description="t('COMVOR_SETTINGS.SECTION.POLICIES.DESCRIPTION')"
        >
          <div class="flex flex-col gap-4">
            <label v-for="(policy, key) in form.policies" :key="key" class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t(`COMVOR_SETTINGS.FIELDS.POLICIES.${key.toUpperCase()}.LABEL`) }}
              </span>
              <textarea
                v-model="form.policies[key]"
                rows="3"
                :maxlength="POLICY_LIMITS[key]"
                class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                :placeholder="t(`COMVOR_SETTINGS.FIELDS.POLICIES.${key.toUpperCase()}.PLACEHOLDER`)"
              />
            </label>
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

      <!-- ── Tab 2: Knowledge Cards ── -->
      <template v-else-if="selectedTab === 2">
        <SectionLayout
          :title="t('COMVOR_SETTINGS.SECTION.KNOWLEDGE.TITLE')"
          :description="t('COMVOR_SETTINGS.SECTION.KNOWLEDGE.DESCRIPTION')"
        >
          <div class="flex flex-col gap-3">
            <p v-if="knowledgeCards.length === 0" class="text-sm text-n-slate-11">
              {{ t('COMVOR_SETTINGS.FIELDS.KNOWLEDGE_CARDS.EMPTY_STATE') }}
            </p>
            <div
              v-for="(card, index) in knowledgeCards"
              :key="card.id || index"
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
                <button class="text-n-slate-10 hover:text-n-red-9 text-xs px-2 py-1" @click="removeCard(index)">✕</button>
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
              <span v-else class="text-xs text-n-slate-11">{{ t('COMVOR_SETTINGS.FIELDS.KNOWLEDGE_CARDS.MAX_CARDS_REACHED') }}</span>
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
      </template>

      <!-- ── Tab 3: Instructions ── -->
      <template v-else-if="selectedTab === 3">
        <SectionLayout
          :title="t('COMVOR_SETTINGS.SECTION.INSTRUCTIONS.TITLE')"
          :description="t('COMVOR_SETTINGS.SECTION.INSTRUCTIONS.DESCRIPTION')"
        >
          <div class="flex flex-col gap-6">
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
                    v-for="chip in LEAD_CHIPS" :key="chip.key"
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
                  rows="2" maxlength="500"
                  class="ml-7 w-[calc(100%-1.75rem)] rounded border border-n-weak bg-n-surface-1 px-2 py-1 text-sm text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
                  :placeholder="t('COMVOR_SETTINGS.INSTRUCTIONS.LEAD_COLLECTION.CUSTOM_PLACEHOLDER')"
                />
              </template>
            </div>

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
                    v-for="chip in AVOID_CHIPS" :key="chip.key"
                    class="rounded-full border px-3 py-1 text-xs transition-colors"
                    :class="form.instruction_modules.avoid_topics.chips.includes(chip.label)
                      ? 'border-n-brand bg-n-brand/10 text-n-brand'
                      : 'border-n-weak text-n-slate-11 hover:border-n-brand'"
                    @click="toggleChip(chip.label, form.instruction_modules.avoid_topics.chips)"
                  >{{ chip.label }}</button>
                </div>
                <textarea
                  v-model="form.instruction_modules.avoid_topics.custom"
                  rows="2" maxlength="500"
                  class="ml-7 w-[calc(100%-1.75rem)] rounded border border-n-weak bg-n-surface-1 px-2 py-1 text-sm text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
                  :placeholder="t('COMVOR_SETTINGS.INSTRUCTIONS.AVOID_TOPICS.CUSTOM_PLACEHOLDER')"
                />
              </template>
            </div>

            <div class="flex flex-col gap-2">
              <span class="text-sm font-medium text-n-slate-12">{{ t('COMVOR_SETTINGS.INSTRUCTIONS.CUSTOM.TITLE') }}</span>
              <p class="text-xs text-n-slate-11">{{ t('COMVOR_SETTINGS.INSTRUCTIONS.CUSTOM.DESCRIPTION') }}</p>
              <textarea
                v-model="form.instruction_modules.custom_instructions"
                rows="3" maxlength="1000"
                class="w-full rounded border border-n-weak bg-n-surface-1 px-2 py-1 text-sm text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
                :placeholder="t('COMVOR_SETTINGS.INSTRUCTIONS.CUSTOM.PLACEHOLDER')"
              />
              <span class="text-xs text-n-slate-11 text-right">{{ (form.instruction_modules.custom_instructions || '').length }}/1000</span>
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

      <!-- ── Tab 4: Connector ── -->
      <template v-else-if="selectedTab === 4">
        <SectionLayout
          :title="t('COMVOR_SETTINGS.SECTION.CONNECTOR.TITLE')"
          :description="t('COMVOR_SETTINGS.SECTION.CONNECTOR.DESCRIPTION')"
        >
          <div class="flex flex-col gap-6">
            <div>
              <label class="text-sm font-medium text-n-slate-12 block mb-1">
                {{ t('COMVOR_SETTINGS.CONNECTOR.TYPE_LABEL') }}
              </label>
              <select
                v-model="connectorType"
                class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              >
                <option value="none">{{ t('COMVOR_SETTINGS.CONNECTOR.TYPE_NONE') }}</option>
                <option value="ewity">{{ t('COMVOR_SETTINGS.CONNECTOR.TYPE_EWITY') }}</option>
              </select>
            </div>

            <template v-if="connectorType === 'ewity'">
              <div>
                <label class="text-sm font-medium text-n-slate-12 block mb-1">
                  {{ t('COMVOR_SETTINGS.CONNECTOR.EWITY.TOKEN_LABEL') }}
                </label>
                <input
                  v-model="ewityToken"
                  type="password"
                  :placeholder="t('COMVOR_SETTINGS.CONNECTOR.EWITY.TOKEN_PLACEHOLDER')"
                  class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                />
                <p v-if="ewityTokenHint && !ewityToken" class="mt-1 text-xs text-n-slate-11 font-mono">
                  {{ ewityTokenHint }}
                </p>
                <p v-else class="mt-1 text-xs text-n-slate-11">
                  {{ t('COMVOR_SETTINGS.CONNECTOR.EWITY.TOKEN_HINT') }}
                </p>
              </div>

              <div>
                <p class="text-sm font-medium text-n-slate-12 mb-2">
                  {{ t('COMVOR_SETTINGS.CONNECTOR.EWITY.PERMISSIONS_LABEL') }}
                </p>
                <p v-if="!ewityTokenHint" class="text-xs text-n-slate-11 mb-3">
                  {{ t('COMVOR_SETTINGS.CONNECTOR.EWITY.TEST_REQUIRES_SAVE') }}
                </p>

                <div v-for="(perm, index) in EWITY_PERMISSIONS" :key="perm.key" :class="{ 'mb-3': index < EWITY_PERMISSIONS.length - 1 }">
                  <div class="flex items-start gap-2">
                    <input
                      type="checkbox"
                      :checked="perm.required || ewityOptionalPermissions.includes(perm.key)"
                      :disabled="perm.required"
                      class="mt-0.5 w-4 h-4 accent-n-brand"
                      @change="toggleChip(perm.key, ewityOptionalPermissions.value)"
                    />
                    <span class="text-sm text-n-slate-12 flex-1">
                      {{ t(`COMVOR_SETTINGS.CONNECTOR.EWITY.${perm.labelKey}`) }}
                    </span>
                    <button
                      type="button"
                      :disabled="!ewityTokenHint || permissionTestState[perm.key] === 'testing'"
                      class="text-xs px-2 py-0.5 rounded border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50 shrink-0"
                      @click="testPermission(perm.key)"
                    >
                      {{ permissionTestState[perm.key] === 'testing'
                          ? t('COMVOR_SETTINGS.CONNECTOR.EWITY.TESTING')
                          : t('COMVOR_SETTINGS.CONNECTOR.EWITY.TEST') }}
                    </button>
                  </div>
                  <p v-if="permissionTestState[perm.key] === 'ok'"
                     class="mt-1 ml-6 text-xs text-green-600">
                    ✓ {{ t('COMVOR_SETTINGS.CONNECTOR.EWITY.TEST_OK') }}
                  </p>
                  <p v-else-if="permissionTestState[perm.key] === 'error'"
                     class="mt-1 ml-6 text-xs text-red-600">
                    {{ permissionTestMessage[perm.key] }}
                  </p>
                </div>
              </div>
            </template>
          </div>
        </SectionLayout>

        <div class="flex justify-end px-6 py-4">
          <button
            class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white hover:bg-n-brand/90 disabled:opacity-50"
            :disabled="isSavingConnector"
            @click="saveConnector"
          >
            {{ isSavingConnector
                ? t('COMVOR_SETTINGS.CONNECTOR.EWITY.SAVING')
                : t('COMVOR_SETTINGS.CONNECTOR.EWITY.SAVE') }}
          </button>
        </div>
      </template>

    </template>
  </SettingsLayout>
</template>
