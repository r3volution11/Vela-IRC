<script setup lang="ts">
// One feature row on the home page: copy on one side, a screenshot (or a
// mosaic of theme screenshots) on the other.
//
//   <ShowcaseRow eyebrow="Themes" title="…" src="/screenshots/…" alt="…" link="/customize/themes">
//   Markdown body…
//   </ShowcaseRow>
import { computed } from 'vue'
import { withBase } from 'vitepress'
import { imageSize } from '../imageSizes'
import themeNames from '../../../_generated/theme-names.json'

const props = defineProps<{
  eyebrow?: string
  title: string
  src?: string
  light?: string
  alt?: string
  /** Built-in theme ids, shown as a grid of small screenshots instead of `src`. */
  themes?: string
  reverse?: boolean
  link?: string
  linkText?: string
}>()

const mosaic = computed(() =>
  (props.themes ?? '')
    .split(',')
    .map((id) => id.trim())
    .filter(Boolean)
    .map((id) => ({ id, src: `/screenshots/theme-${id}.webp` })),
)
const themeName = (id: string) => (themeNames as Record<string, string>)[id] ?? id
</script>

<template>
  <section class="showcase-row" :class="{ 'showcase-row--reverse': reverse }">
    <div class="showcase-row__copy">
      <p v-if="eyebrow" class="showcase-row__eyebrow">{{ eyebrow }}</p>
      <h2 class="showcase-row__title">{{ title }}</h2>
      <div class="showcase-row__body"><slot /></div>
      <a v-if="link" class="showcase-row__link" :href="withBase(link)">{{ linkText || 'Learn more' }} <span aria-hidden="true">→</span></a>
    </div>
    <div class="showcase-row__media">
      <div v-if="mosaic.length" class="theme-mosaic">
        <figure v-for="item in mosaic" :key="item.id" class="theme-mosaic__item">
          <img
            :src="withBase(item.src)"
            :alt="`Vela in the ${themeName(item.id)} theme`"
            :width="imageSize(item.src)?.width"
            :height="imageSize(item.src)?.height"
            loading="lazy"
            decoding="async"
          />
          <figcaption>{{ themeName(item.id) }}</figcaption>
        </figure>
      </div>
      <figure v-else-if="src" class="vela-shot vela-shot--showcase">
        <img
          :src="withBase(src)"
          :alt="alt"
          :width="imageSize(src)?.width"
          :height="imageSize(src)?.height"
          loading="lazy"
          decoding="async"
          :class="{ 'dark-only': light }"
        />
        <img
          v-if="light"
          :src="withBase(light)"
          :alt="alt"
          :width="imageSize(light)?.width"
          :height="imageSize(light)?.height"
          loading="lazy"
          decoding="async"
          class="light-only"
        />
      </figure>
    </div>
  </section>
</template>
