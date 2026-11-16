<script setup lang="ts">
// A compact Download button at the end of the navigation bar (wide screens).
import { DOWNLOAD_URL } from '../constants'
</script>

<template>
  <a class="nav-download" :href="DOWNLOAD_URL">Download</a>
</template>
