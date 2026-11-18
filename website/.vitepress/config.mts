import { defineConfig, type DefaultTheme } from 'vitepress'
import { buildPageHead, DOWNLOAD_URL, REPO_URL, SITE } from './seo.mts'
import { repoLinks } from './repoLinks.mts'

// One sidebar for the whole site, grouped by what a page is for. seo.mts
// walks it for each page's breadcrumbs and takes the first entry that links
// a page, so list each page once (Keyboard shortcuts lives in Reference).
const sidebar: DefaultTheme.SidebarItem[] = [
  {
    text: 'Getting started',
    items: [
      { text: 'Install', link: '/guide/install' },
      { text: 'First launch', link: '/guide/first-launch' },
      { text: 'Adding a network', link: '/guide/adding-a-network' },
      { text: 'Connecting through a bouncer', link: '/guide/bouncers' },
      { text: 'Joining channels', link: '/guide/joining-channels' },
    ],
  },
  {
    text: 'Using Vela',
    items: [
      { text: 'The window', link: '/guide/the-window' },
      { text: 'Messages & layouts', link: '/guide/messages-and-layouts' },
      { text: 'Presets', link: '/guide/presets' },
      { text: 'Tab stacks', link: '/guide/tab-stacks' },
      { text: 'Sending messages', link: '/guide/sending-messages' },
      { text: 'Command palette', link: '/guide/command-palette' },
      { text: 'Inline media & privacy', link: '/guide/inline-media' },
      { text: 'Reactions, replies & typing', link: '/guide/reactions-replies-typing' },
      { text: 'Notifications & highlights', link: '/guide/notifications' },
      { text: 'Member list', link: '/guide/member-list' },
      { text: 'Chat logs', link: '/guide/chat-logs' },
      { text: 'Apple Intelligence & translation', link: '/guide/apple-intelligence' },
      { text: 'Siri, Shortcuts & Spotlight', link: '/guide/siri-shortcuts' },
    ],
  },
  {
    text: 'Customization',
    items: [
      { text: 'Choosing a theme', link: '/customize/themes' },
      { text: 'Theme editor', link: '/customize/theme-editor' },
      { text: 'Importing VS Code themes', link: '/customize/vs-code-themes' },
      { text: 'Creating themes', link: '/customize/creating-themes' },
      { text: 'App icon', link: '/customize/app-icon' },
      { text: 'Settings editor', link: '/customize/settings-editor' },
      { text: 'settings.json', link: '/customize/settings-json' },
    ],
  },
  {
    text: 'Reference',
    items: [
      { text: 'Keyboard shortcuts', link: '/reference/keyboard-shortcuts' },
      { text: 'Slash commands', link: '/reference/slash-commands' },
      { text: 'Settings keys', link: '/reference/settings' },
      { text: 'Theme tokens', link: '/reference/theme-tokens' },
      { text: 'Built-in themes', link: '/reference/built-in-themes' },
      { text: 'IRCv3 support', link: '/reference/ircv3' },
      { text: 'Supported media sites', link: '/reference/media-sites' },
    ],
  },
  {
    text: 'Help',
    items: [
      { text: 'Troubleshooting & FAQ', link: '/help/troubleshooting' },
      { text: 'Privacy', link: '/help/privacy' },
      { text: 'Changelog', link: '/changelog' },
      { text: 'License & credits', link: '/help/license' },
    ],
  },
]

export default defineConfig({
  lang: 'en-US',
  // Appended to every page title ("Presets | Vela — IRC client for macOS"),
  // so page titles never repeat the name themselves.
  title: 'Vela — IRC client for macOS',
  description: 'Vela is a free, open-source, deeply themable IRC client for macOS, with inline media, IRCv3, bouncer support and VS Code-style themes.',
  cleanUrls: true,
  lastUpdated: true,

  // Reference partials come from the app's sources (scripts/generate.mjs);
  // they're included into pages, not pages themselves.
  srcExclude: ['_generated/**', 'scripts/**', 'README.md'],

  sitemap: {
    hostname: SITE,
  },

  markdown: {
    theme: { light: 'material-theme-lighter', dark: 'material-theme-palenight' },
    image: { lazyLoading: true },
    config: (md) => md.use(repoLinks),
  },

  // Canonical URL, social tags and schema.org data for every page (seo.mts)
  transformHead: (context) => buildPageHead(context, sidebar),

  head: [
    // The favicon is Glint's V and star with no tile (scripts/export-icon.sh).
    // The SVG switches between deep blue and cyan with the browser's light or
    // dark mode, so it comes first; the PNGs and ICO are one mid blue for
    // browsers without SVG favicons. Each fallback states its sizes: without
    // them, Chrome can pick the ICO over the SVG. The touch icon is the tile.
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' }],
    ['link', { rel: 'icon', type: 'image/png', sizes: '32x32', href: '/favicon-32x32.png' }],
    ['link', { rel: 'icon', type: 'image/png', sizes: '16x16', href: '/favicon-16x16.png' }],
    ['link', { rel: 'icon', type: 'image/x-icon', sizes: '16x16 32x32 48x48', href: '/favicon.ico' }],
    ['link', { rel: 'apple-touch-icon', sizes: '180x180', href: '/apple-touch-icon.png' }],
    ['meta', { name: 'theme-color', media: '(prefers-color-scheme: dark)', content: '#292D3E' }],
    ['meta', { name: 'theme-color', media: '(prefers-color-scheme: light)', content: '#FAFAFA' }],
    ['meta', { name: 'author', content: 'Doug C. Hardester' }],
    ['meta', { property: 'og:site_name', content: 'Vela' }],
    ['meta', { property: 'og:locale', content: 'en_US' }],
    ['meta', { property: 'og:image', content: `${SITE}/og-image.jpg` }],
    ['meta', { property: 'og:image:type', content: 'image/jpeg' }],
    ['meta', { property: 'og:image:width', content: '1200' }],
    ['meta', { property: 'og:image:height', content: '630' }],
    ['meta', { property: 'og:image:alt', content: 'Vela, a modern, deeply themable IRC client for macOS, shown in the Palenight theme' }],
    ['meta', { name: 'twitter:card', content: 'summary_large_image' }],
    ['meta', { name: 'twitter:image', content: `${SITE}/og-image.jpg` }],
    ['meta', { name: 'twitter:image:alt', content: 'Vela, a modern, deeply themable IRC client for macOS, shown in the Palenight theme' }],
  ],

  themeConfig: {
    logo: { src: '/logo.png', alt: '', width: 24, height: 24 },
    siteTitle: 'Vela',

    nav: [
      { text: 'Guide', link: '/guide/install', activeMatch: '^/guide/' },
      { text: 'Customize', link: '/customize/themes', activeMatch: '^/customize/' },
      { text: 'Reference', link: '/reference/keyboard-shortcuts', activeMatch: '^/reference/' },
      { text: 'Help', link: '/help/troubleshooting', activeMatch: '^/help/' },
      { text: 'Changelog', link: '/changelog' },
    ],

    sidebar,

    outline: { level: [2, 3] },

    socialLinks: [{ icon: 'github', link: REPO_URL, ariaLabel: 'Vela on GitHub' }],

    search: { provider: 'local' },

    editLink: {
      pattern: `${REPO_URL}/edit/main/website/:path`,
      text: 'Suggest a change to this page',
    },

    lastUpdated: {
      text: 'Updated',
      formatOptions: { dateStyle: 'medium' },
    },

    footer: {
      message: `Free and open source under the <a href="/help/license">Mozilla Public License 2.0</a>. <a href="${DOWNLOAD_URL}">Download Vela</a>.`,
      copyright: `Copyright © ${new Date().getFullYear()} Doug C. Hardester`,
    },

    externalLinkIcon: true,
  },
})
