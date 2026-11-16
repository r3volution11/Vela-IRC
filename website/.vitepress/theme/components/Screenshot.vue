<script setup lang="ts">
// A screenshot of the app with rounded corners and a soft shadow.
//
//   <Screenshot src="/screenshots/preset-classic.webp" alt="…" caption="…" />
//   <Screenshot src="/screenshots/home-palenight.webp" light="/screenshots/home-lighter.webp" alt="…" />
//
// `light` is shown instead of `src` while the site is in light mode. Width
// and height come from scripts/generate.mjs, so the page doesn't jump while
// images load.
import { withBase } from 'vitepress'
import { imageSize } from '../imageSizes'

defineProps<{
  src: string
  light?: string
  alt: string
  caption?: string
  eager?: boolean
}>()
</script>

<template>
  <figure class="vela-shot">
    <img
      :src="withBase(src)"
      :alt="alt"
      :width="imageSize(src)?.width"
      :height="imageSize(src)?.height"
      :loading="eager ? 'eager' : 'lazy'"
      decoding="async"
      :class="{ 'dark-only': light }"
    />
    <img
      v-if="light"
      :src="withBase(light)"
      :alt="alt"
      :width="imageSize(light)?.width"
      :height="imageSize(light)?.height"
      :loading="eager ? 'eager' : 'lazy'"
      decoding="async"
      class="light-only"
    />
    <figcaption v-if="caption">{{ caption }}</figcaption>
  </figure>
</template>
