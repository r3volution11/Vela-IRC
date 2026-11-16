<script setup lang="ts">
// The big window under the home page hero: Palenight in dark mode, Lighter
// in light mode, like the app's own defaults.
import { withBase } from 'vitepress'
import { imageSize } from '../imageSizes'

const dark = '/screenshots/home-palenight.webp'
const light = '/screenshots/home-lighter.webp'
const alt =
  'Vela with the Modern Chat preset: networks and channels in the sidebar, grouped messages with an inline GIF, reactions and a link card, and the member list'
</script>

<template>
  <div class="home-hero-shot">
    <div class="home-hero-shot__glow" aria-hidden="true" />
    <img
      class="home-hero-shot__img dark-only"
      :src="withBase(dark)"
      :alt="alt"
      :width="imageSize(dark)?.width"
      :height="imageSize(dark)?.height"
      fetchpriority="high"
    />
    <img
      class="home-hero-shot__img light-only"
      :src="withBase(light)"
      :alt="alt"
      :width="imageSize(light)?.width"
      :height="imageSize(light)?.height"
      loading="lazy"
    />
  </div>
</template>
