// The default VitePress theme, dressed in Vela's own palettes: Palenight in
// dark mode and Lighter in light mode (see vela.css). Without Inter, so text
// uses the system font, like the app.
import DefaultTheme from 'vitepress/theme-without-fonts'
import type { Theme } from 'vitepress'
import { h } from 'vue'
import Screenshot from './components/Screenshot.vue'
import ShowcaseRow from './components/ShowcaseRow.vue'
import HomeHeroShot from './components/HomeHeroShot.vue'
import HomeRequirements from './components/HomeRequirements.vue'
import NavDownload from './components/NavDownload.vue'
import DownloadCard from './components/DownloadCard.vue'
import './vela.css'

export default {
  extends: DefaultTheme,
  Layout() {
    return h(DefaultTheme.Layout, null, {
      'home-hero-actions-after': () => h(HomeRequirements),
      'home-hero-after': () => h(HomeHeroShot),
      'nav-bar-content-after': () => h(NavDownload),
    })
  },
  enhanceApp({ app }) {
    // Usable in any page
    app.component('Screenshot', Screenshot)
    app.component('ShowcaseRow', ShowcaseRow)
    app.component('DownloadCard', DownloadCard)
  },
} satisfies Theme
