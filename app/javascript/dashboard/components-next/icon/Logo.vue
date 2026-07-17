<script setup>
import { useAttrs } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

const attrs = useAttrs();
const globalConfig = useMapGetter('globalConfig/get');
</script>

<template>
  <img
    v-if="globalConfig.logoThumbnail"
    v-bind="attrs"
    :src="globalConfig.logoThumbnail"
  />
  <svg
    v-else
    v-once
    v-bind="attrs"
    width="16"
    height="16"
    viewBox="0 0 16 16"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
  >
    <path
      d="M12.2 5.6 L8 1.4 L1.4 8 L8 14.6 L12.2 10.4 L10.9 9.1 L8 12 L4 8 L8 4 L10.9 6.9 Z"
      fill="#4f46e5"
    />
    <path d="M8 6.2 L9.8 8 L8 9.8 L6.2 8 Z" fill="#4f46e5" />
  </svg>
</template>
