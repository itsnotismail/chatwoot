<script setup>
import { ref } from 'vue';

defineProps({ text: { type: String, required: true } });
const open = ref(false);
</script>

<template>
  <span class="relative inline-block">
    <button
      type="button"
      data-testid="info-hint-toggle"
      :title="text"
      :aria-label="text"
      :aria-expanded="open"
      class="text-n-slate-9 cursor-help align-middle"
      @click.stop.prevent="open = !open"
    >
      ?
    </button>
    <span
      v-if="open"
      data-testid="info-hint-text"
      class="absolute left-0 top-5 z-10 w-56 rounded-md border border-n-weak bg-n-surface-1 p-2 text-xs font-normal text-n-slate-11 shadow"
    >
      {{ text }}
    </span>
  </span>
</template>
