<script setup lang="ts">
// Asks visitors in the EU, EEA, UK and Switzerland before the site uses
// Google Analytics (analytics.ts decides who is asked). Nothing loads until
// they answer; the choice can be changed later on the Privacy page.
import { onMounted, ref } from 'vue'
import { withBase } from 'vitepress'
import { bannerOpen, setChoice } from '../analytics'

// Rendered only after mounting, so the server-rendered page and the first
// client render agree.
const mounted = ref(false)
onMounted(() => {
  mounted.value = true
})
</script>

<template>
  <div v-if="mounted && bannerOpen" class="consent-banner" role="region" aria-label="Analytics on this website">
    <p class="consent-banner__text">
      May this website use Google Analytics to count visits and downloads? Nothing is measured unless you allow it,
      and the Vela app itself never collects anything.
      <a :href="withBase('/help/privacy#this-website')">Privacy</a>
    </p>
    <div class="consent-banner__actions">
      <button type="button" class="consent-banner__button" @click="setChoice('denied')">No thanks</button>
      <button type="button" class="consent-banner__button consent-banner__button--brand" @click="setChoice('granted')">
        Allow
      </button>
    </div>
  </div>
</template>

<style scoped>
.consent-banner {
  position: fixed;
  right: 16px;
  bottom: calc(16px + env(safe-area-inset-bottom, 0px));
  left: 16px;
  /* Above the page and the nav bar, below the mobile menu's backdrop. */
  z-index: var(--vp-z-index-layout-top);
  display: flex;
  flex-wrap: wrap;
  gap: 12px 20px;
  align-items: center;
  justify-content: space-between;
  max-width: 760px;
  margin: 0 auto;
  padding: 14px 18px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
  background: var(--vp-c-bg-elv);
  box-shadow: var(--vp-shadow-3);
}

.consent-banner__text {
  flex: 1 1 320px;
  margin: 0;
  font-size: 14px;
  line-height: 1.5;
  color: var(--vp-c-text-2);
}

.consent-banner__text a {
  color: var(--vp-c-brand-1);
  font-weight: 500;
  text-decoration: underline;
  text-underline-offset: 2px;
}

.consent-banner__actions {
  display: flex;
  gap: 8px;
}

.consent-banner__button {
  height: 36px;
  padding: 0 16px;
  border-radius: 18px;
  font-size: 14px;
  font-weight: 600;
  background: var(--vp-button-alt-bg);
  color: var(--vp-button-alt-text);
  transition: background-color 0.2s;
}

.consent-banner__button:hover {
  background: var(--vp-button-alt-hover-bg);
}

.consent-banner__button--brand {
  background: var(--vp-button-brand-bg);
  color: var(--vp-button-brand-text);
}

.consent-banner__button--brand:hover {
  background: var(--vp-button-brand-hover-bg);
}

.consent-banner__button:focus-visible {
  outline: 2px solid var(--vp-c-brand-1);
  outline-offset: 2px;
}
</style>
