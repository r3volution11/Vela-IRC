<script setup lang="ts">
// The download box on the Install page.
import { withBase } from 'vitepress'
import { DOWNLOAD_URL, RELEASES_URL } from '../constants'
</script>

<template>
  <div class="download-card">
    <img class="download-card__icon" :src="withBase('/vela-icon.webp')" alt="" width="88" height="88" />
    <div class="download-card__body">
      <p class="download-card__title">Vela for macOS</p>
      <p class="download-card__meta">macOS 26 or later · Apple silicon &amp; Intel · Signed and notarized</p>
      <div class="download-card__actions">
        <a class="download-card__button no-icon" :href="DOWNLOAD_URL">Download Vela.dmg</a>
        <a class="download-card__link no-icon" :href="RELEASES_URL">All releases</a>
      </div>
    </div>
  </div>
</template>
