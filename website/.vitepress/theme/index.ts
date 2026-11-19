// The default VitePress theme, dressed in Vela's own palettes: Palenight in
// dark mode and Lighter in light mode (see vela.css). Without Inter, so text
// uses the system font, like the app.
import DefaultTheme from 'vitepress/theme-without-fonts'
import { inBrowser, type Theme } from 'vitepress'
import { h } from 'vue'
import Screenshot from './components/Screenshot.vue'
import ShowcaseRow from './components/ShowcaseRow.vue'
import HomeHeroShot from './components/HomeHeroShot.vue'
import HomeRequirements from './components/HomeRequirements.vue'
import NavDownload from './components/NavDownload.vue'
import DownloadCard from './components/DownloadCard.vue'
import ConsentBanner from './components/ConsentBanner.vue'
import AnalyticsSettings from './components/AnalyticsSettings.vue'
import { initAnalytics } from './analytics'
import './vela.css'

export default {
  extends: DefaultTheme,
  Layout() {
    return h(DefaultTheme.Layout, null, {
      'home-hero-actions-after': () => h(HomeRequirements),
      'home-hero-after': () => h(HomeHeroShot),
      'nav-bar-content-after': () => h(NavDownload),
      'layout-bottom': () => h(ConsentBanner),
    })
  },
  enhanceApp({ app, router }) {
    // Usable in any page
    app.component('Screenshot', Screenshot)
    app.component('ShowcaseRow', ShowcaseRow)
    app.component('DownloadCard', DownloadCard)
    app.component('AnalyticsSettings', AnalyticsSettings)

    // The website's analytics (never the app's: it has none). Loads only on
    // velairc.app, and only once allowed; see analytics.ts.
    if (inBrowser) initAnalytics(router)
  },
} satisfies Theme
