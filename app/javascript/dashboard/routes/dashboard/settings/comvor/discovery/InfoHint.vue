<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';

defineProps({ text: { type: String, required: true } });
const open = ref(false);
const root = ref(null);

// Close the popover when the user clicks anywhere outside it (or presses
// Escape). The toggle button's own click uses .stop, and this listener is
// capture-phase + contains()-guarded, so clicking the button toggles rather
// than double-firing a close.
function onDocClick(e) {
  if (root.value && !root.value.contains(e.target)) open.value = false;
}
function onKeydown(e) {
  if (e.key === 'Escape') open.value = false;
}
watch(open, isOpen => {
  if (isOpen) {
    document.addEventListener('click', onDocClick, true);
    document.addEventListener('keydown', onKeydown);
  } else {
    document.removeEventListener('click', onDocClick, true);
    document.removeEventListener('keydown', onKeydown);
  }
});
onBeforeUnmount(() => {
  document.removeEventListener('click', onDocClick, true);
  document.removeEventListener('keydown', onKeydown);
});
</script>

<template>
  <span ref="root" class="relative inline-block">
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
