<script setup lang="ts">
import { useData } from 'vitepress'

const { frontmatter } = useData()
</script>

<template>
  <p v-if="frontmatter.layout === 'home'" class="home-requirements">
    <span>macOS 26 or later</span>
    <span aria-hidden="true">·</span>
    <span>Apple silicon &amp; Intel</span>
    <span aria-hidden="true">·</span>
    <span>Free and open source</span>
  </p>
</template>
