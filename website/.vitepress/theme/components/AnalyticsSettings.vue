<script setup lang="ts">
// The Privacy page's switch for this website's Google Analytics: shows where
// the visitor stands and lets them change it at any time.
import { onMounted, ref } from 'vue'
import { analyticsStatus, offByPrivacyControl, setChoice } from '../analytics'

const mounted = ref(false)
onMounted(() => {
  mounted.value = true
})
</script>

<template>
  <div class="analytics-settings">
    <template v-if="mounted && analyticsStatus !== 'unavailable'">
      <p class="analytics-settings__status">
        <template v-if="analyticsStatus === 'on'">Google Analytics is <strong>on</strong> for you on this website.</template>
        <template v-else-if="analyticsStatus === 'ask'">You haven't chosen yet, so nothing is being measured.</template>
        <template v-else-if="offByPrivacyControl">
          Google Analytics is <strong>off</strong> for you, because your browser sends Global Privacy Control.
        </template>
        <template v-else>Google Analytics is <strong>off</strong> for you on this website.</template>
      </p>
      <div class="analytics-settings__actions">
        <button v-if="analyticsStatus !== 'off'" type="button" class="analytics-settings__button" @click="setChoice('denied')">
          {{ analyticsStatus === 'ask' ? 'No thanks' : 'Turn off analytics' }}
        </button>
        <button v-if="analyticsStatus !== 'on'" type="button" class="analytics-settings__button analytics-settings__button--brand" @click="setChoice('granted')">
          Allow analytics
        </button>
      </div>
    </template>
    <p v-else-if="mounted" class="analytics-settings__status">
      Analytics runs only on velairc.app, so this copy of the site measures nothing.
    </p>
    <p v-else class="analytics-settings__status">Your choice is kept in this browser.</p>
  </div>
</template>

<style scoped>
.analytics-settings {
  margin: 16px 0;
  padding: 16px 20px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
  background: var(--vp-c-bg-soft);
}

.analytics-settings__status {
  margin: 0;
}

.analytics-settings__actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 12px;
}

.analytics-settings__button {
  height: 36px;
  padding: 0 16px;
  border-radius: 18px;
  font-size: 14px;
  font-weight: 600;
  background: var(--vp-button-alt-bg);
  color: var(--vp-button-alt-text);
  transition: background-color 0.2s;
}

.analytics-settings__button:hover {
  background: var(--vp-button-alt-hover-bg);
}

.analytics-settings__button--brand {
  background: var(--vp-button-brand-bg);
  color: var(--vp-button-brand-text);
}

.analytics-settings__button--brand:hover {
  background: var(--vp-button-brand-hover-bg);
}

.analytics-settings__button:focus-visible {
  outline: 2px solid var(--vp-c-brand-1);
  outline-offset: 2px;
}
</style>
