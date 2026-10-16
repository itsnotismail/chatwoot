<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  isCollapsed: { type: Boolean, default: false },
});

const { t } = useI18n();

// The Comvor portal is the merchant's home and Chatwoot is the conversation
// workspace they are handed off to from it; without this link there is no way
// back. Hardcoded like the fork's other app.comvor.com links (login/Index.vue,
// the SAML password notes). /app sends an agent-only user on to /workspace by
// itself, so one URL serves owners and agents.
const COMVOR_DASHBOARD_URL = 'https://app.comvor.com/app';
</script>

<template>
  <a
    v-if="!isCollapsed"
    :href="COMVOR_DASHBOARD_URL"
    data-testid="comvor-dashboard-link"
    class="flex gap-2 items-center px-2 py-1 w-full h-7 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 transition-all duration-100 ease-out"
  >
    <span class="flex-shrink-0 i-lucide-arrow-left size-4" />
    <span class="flex-grow text-start truncate">
      {{ t('SIDEBAR_ITEMS.COMVOR_DASHBOARD') }}
    </span>
  </a>
  <a
    v-else
    :href="COMVOR_DASHBOARD_URL"
    data-testid="comvor-dashboard-link"
    :title="t('SIDEBAR_ITEMS.COMVOR_DASHBOARD')"
    :aria-label="t('SIDEBAR_ITEMS.COMVOR_DASHBOARD')"
    class="flex items-center justify-center size-8 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 transition-all duration-100 ease-out"
  >
    <span class="i-lucide-arrow-left size-4" />
  </a>
</template>
