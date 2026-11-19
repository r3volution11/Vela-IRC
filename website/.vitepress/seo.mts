// Per-page SEO, wired in through config.mts's transformHead.
//
// Every page gets its own canonical URL, Open Graph and Twitter tags, and a
// schema.org JSON-LD @graph: the site, its author, Vela itself (a
// SoftwareApplication with its download), the page (a TechArticle, or a
// WebPage for home) and its breadcrumbs, which follow the sidebar.
//
// scripts/check-site.mjs verifies the built site against this.

import { readFileSync } from 'node:fs'
import type { DefaultTheme, HeadConfig, TransformContext } from 'vitepress'

export const SITE = 'https://velairc.app'
export const REPO_URL = 'https://github.com/r3volution11/Vela-IRC'
/** The release workflow publishes a stable asset with exactly this name. */
export const DOWNLOAD_URL = `${REPO_URL}/releases/latest/download/Vela.dmg`

const SITE_NAME = 'Vela'
const TAGLINE = 'A modern, deeply themable IRC client for macOS'
const SITE_DESCRIPTION =
  'Vela is a free, open-source, deeply themable IRC client for macOS, with inline media, IRCv3, bouncer support and VS Code-style themes.'

/** The newest version in CHANGELOG.md ("## 1.0.0 - 2026-11-18"), if any. */
function latestVersion(): string | undefined {
  try {
    const changelog = readFileSync(new URL('../../CHANGELOG.md', import.meta.url), 'utf8')
    return changelog.match(/^## \[?(\d+\.\d+\.\d+[^\]\s]*)/m)?.[1]
  } catch {
    return undefined
  }
}
const version = latestVersion()

const ids = {
  website: `${SITE}/#website`,
  author: `${SITE}/#author`,
  app: `${SITE}/#app`,
}

/** guide/install.md → https://velairc.app/guide/install (clean URLs, as in the sitemap) */
export function pageUrl(relativePath: string): string {
  const path = relativePath.replace(/(^|\/)index\.md$/, '$1').replace(/\.md$/, '')
  return `${SITE}/${path}`
}

/** The sidebar link form of a page: /guide/install */
const sidebarPath = (relativePath: string) =>
  '/' + relativePath.replace(/(^|\/)index\.md$/, '$1').replace(/\.md$/, '')

/** Sidebar groups containing the page, each linked to its first page. */
function breadcrumbTrail(sidebar: DefaultTheme.SidebarItem[], relativePath: string) {
  const target = sidebarPath(relativePath)
  const firstLink = (item: DefaultTheme.SidebarItem): string | undefined =>
    item.link || item.items?.map(firstLink).find(Boolean)

  const walk = (items: DefaultTheme.SidebarItem[] | undefined, ancestors: { name: string; path: string }[]): typeof ancestors | null => {
    for (const item of items || []) {
      if (item.link === target) return ancestors
      if (item.items) {
        const found = walk(item.items, [...ancestors, { name: item.text ?? '', path: firstLink(item) ?? '' }])
        if (found) return found
      }
    }
    return null
  }
  return (walk(sidebar, []) || []).filter((group) => group.path && group.path !== target)
}

const has = (head: HeadConfig[], attr: string, value: string) =>
  head.some(([, attrs]) => (attrs as Record<string, string>)?.[attr] === value)

export const softwareApplication = {
  '@type': 'SoftwareApplication',
  '@id': ids.app,
  name: 'Vela',
  alternateName: 'Vela IRC',
  description: SITE_DESCRIPTION,
  url: `${SITE}/`,
  applicationCategory: 'CommunicationApplication',
  applicationSubCategory: 'IRC client',
  operatingSystem: 'macOS 26 or later',
  processorRequirements: 'Apple silicon or Intel',
  ...(version ? { softwareVersion: version } : {}),
  downloadUrl: DOWNLOAD_URL,
  installUrl: `${SITE}/guide/install`,
  releaseNotes: `${SITE}/changelog`,
  screenshot: `${SITE}/screenshots/home-palenight.webp`,
  image: `${SITE}/og-image.jpg`,
  license: 'https://www.mozilla.org/MPL/2.0/',
  isAccessibleForFree: true,
  offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
  author: { '@id': ids.author },
  sameAs: [REPO_URL],
  featureList: [
    'Every surface themable with VS Code-style color tokens',
    '21 built-in themes, a live theme editor and VS Code theme import (.json and .vsix)',
    'Sidebar with a collapsible rail, or Vivaldi-style tab stacks',
    'Classic, Modern grouped and Compact columns message layouts',
    'One-click presets: Classic IRC, Modern Chat, Tabbed and Focus',
    'Inline images, GIFs, link cards and YouTube, Vimeo, Twitch and Streamable players',
    'IRCv3: server-time, chathistory, reactions, replies, typing indicators and message redaction',
    'SASL PLAIN and EXTERNAL, client certificates and TLS',
    'ZNC and soju bouncer support',
    'Command palette and quick switcher',
    'VS Code-style settings.json with live reload',
  ],
}

export function buildPageHead({ pageData }: TransformContext, sidebar: DefaultTheme.SidebarItem[]): HeadConfig[] {
  if (pageData.isNotFound) return []

  const fm = pageData.frontmatter || {}
  const url = pageUrl(pageData.relativePath)
  const isHome = pageData.relativePath === 'index.md'
  const title = isHome ? `${SITE_NAME} — ${TAGLINE}` : String(fm.title || pageData.title || SITE_NAME)
  const socialTitle = isHome ? title : `${title} · ${SITE_NAME}`
  const description = String(pageData.description || fm.description || SITE_DESCRIPTION)
  const fmHead: HeadConfig[] = fm.head || []

  const head: HeadConfig[] = []
  if (!fmHead.some(([tag, attrs]) => tag === 'link' && (attrs as Record<string, string>)?.rel === 'canonical')) {
    head.push(['link', { rel: 'canonical', href: url }])
  }
  const meta: [string, string, string][] = [
    ['property', 'og:type', isHome ? 'website' : 'article'],
    ['property', 'og:url', url],
    ['property', 'og:title', socialTitle],
    ['property', 'og:description', description],
    ['name', 'twitter:title', socialTitle],
    ['name', 'twitter:description', description],
  ]
  for (const [attr, key, content] of meta) {
    if (!has(fmHead, attr, key)) head.push(['meta', { [attr]: key, content }])
  }

  const crumbs = breadcrumbTrail(sidebar, pageData.relativePath)
  const breadcrumb = {
    '@type': 'BreadcrumbList',
    '@id': `${url}#breadcrumb`,
    itemListElement: [
      { '@type': 'ListItem', position: 1, name: 'Home', item: `${SITE}/` },
      ...crumbs.map((crumb, i) => ({ '@type': 'ListItem', position: i + 2, name: crumb.name, item: `${SITE}${crumb.path}` })),
      ...(isHome ? [] : [{ '@type': 'ListItem', position: crumbs.length + 2, name: title }]),
    ],
  }

  const page = {
    '@type': isHome ? 'WebPage' : 'TechArticle',
    '@id': `${url}#webpage`,
    url,
    name: title,
    ...(isHome ? {} : { headline: title }),
    description,
    inLanguage: 'en',
    isPartOf: { '@id': ids.website },
    about: { '@id': ids.app },
    ...(isHome ? { mainEntity: { '@id': ids.app } } : {}),
    author: { '@id': ids.author },
    publisher: { '@id': ids.author },
    breadcrumb: { '@id': `${url}#breadcrumb` },
    ...(pageData.lastUpdated ? { dateModified: new Date(pageData.lastUpdated).toISOString() } : {}),
  }

  const graph = [
    {
      '@type': 'WebSite',
      '@id': ids.website,
      url: `${SITE}/`,
      name: SITE_NAME,
      alternateName: 'Vela IRC',
      description: SITE_DESCRIPTION,
      inLanguage: 'en',
      publisher: { '@id': ids.author },
    },
    {
      '@type': 'Person',
      '@id': ids.author,
      name: 'Doug C. Hardester',
      alternateName: 'r3volution11',
      url: 'https://github.com/r3volution11',
    },
    softwareApplication,
    page,
    breadcrumb,
  ]

  head.push(['script', { type: 'application/ld+json' }, JSON.stringify({ '@context': 'https://schema.org', '@graph': graph })])
  return head
}
