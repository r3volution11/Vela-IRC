// Checks the built site (.vitepress/dist) before it's deployed: every page
// has its own canonical URL, social tags and valid schema.org data; the home
// page offers the download; no page loads Google's tag before its consent
// check runs; the sitemap lists every page; the files GitHub Pages needs
// are present; and the app's update feed (appcast.xml) is valid.
//
//   npm run docs:build && npm run docs:check

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'
import { checkAppcast } from './appcast.mjs'

const SITE = 'https://velairc.app'
const DOWNLOAD_URL = 'https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg'
const dist = join(dirname(fileURLToPath(import.meta.url)), '..', '.vitepress', 'dist')

const problems = []
const problem = (page, message) => problems.push(`${page}: ${message}`)

if (!existsSync(dist)) {
  console.error('check-site: no build found; run `npm run docs:build` first')
  process.exit(1)
}

function htmlFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name)
    if (statSync(path).isDirectory()) return name === 'assets' ? [] : htmlFiles(path)
    return name.endsWith('.html') && name !== '404.html' ? [path] : []
  })
}

const pages = htmlFiles(dist)
const decode = (text) => text.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
const attr = (html, selector) => {
  const match = html.match(selector)
  return match ? decode(match[1]) : undefined
}

for (const file of pages) {
  const page = relative(dist, file)
  const html = readFileSync(file, 'utf8')
  const head = html.slice(0, html.indexOf('</head>'))
  const url = `${SITE}/${page.replace(/(^|\/)index\.html$/, '$1').replace(/\.html$/, '')}`

  const canonicals = [...head.matchAll(/<link rel="canonical" href="([^"]+)"/g)].map((m) => m[1])
  if (canonicals.length !== 1) problem(page, `expected 1 canonical link, found ${canonicals.length}`)
  else if (canonicals[0] !== url) problem(page, `canonical is ${canonicals[0]}, expected ${url}`)

  if (attr(head, /property="og:url" content="([^"]+)"/) !== url) problem(page, 'og:url is missing or wrong')
  for (const tag of ['og:title', 'og:description', 'og:image', 'og:type']) {
    if (!attr(head, new RegExp(`property="${tag}" content="([^"]+)"`))) problem(page, `missing ${tag}`)
  }
  for (const tag of ['twitter:card', 'twitter:title', 'twitter:description', 'twitter:image']) {
    if (!attr(head, new RegExp(`name="${tag}" content="([^"]+)"`))) problem(page, `missing ${tag}`)
  }
  const description = attr(head, /<meta name="description" content="([^"]+)"/)
  if (!description) problem(page, 'missing meta description')
  else if (description.length > 200) problem(page, `meta description is ${description.length} characters; keep it under 200`)

  const title = attr(head, /<title>([^<]+)<\/title>/)
  if (!title) problem(page, 'missing <title>')
  else if ((title.match(/Vela/g) || []).length > 1) problem(page, `title repeats the name: "${title}"`)

  const ld = head.match(/<script type="application\/ld\+json">(.*?)<\/script>/s)
  if (!ld) {
    problem(page, 'missing JSON-LD')
  } else {
    try {
      const graph = JSON.parse(ld[1])['@graph']
      const types = graph.map((node) => node['@type']).flat()
      for (const type of ['WebSite', 'SoftwareApplication', 'BreadcrumbList']) {
        if (!types.includes(type)) problem(page, `JSON-LD has no ${type}`)
      }
      const app = graph.find((node) => node['@type'] === 'SoftwareApplication')
      if (app && (app.downloadUrl !== DOWNLOAD_URL || app.offers?.price !== '0' || !app.operatingSystem)) {
        problem(page, 'SoftwareApplication needs downloadUrl, operatingSystem and a free offer')
      }
    } catch (error) {
      problem(page, `JSON-LD doesn't parse: ${error.message}`)
    }
  }

  if (page === 'index.html' && !html.includes(`href="${DOWNLOAD_URL}"`)) problem(page, 'no download link')

  // Google's tag is loaded by theme/analytics.ts once a visitor may be
  // measured. A tag written into the page itself would load for everyone,
  // EU visitors who haven't answered included.
  if (/googletagmanager\.com|google-analytics\.com/.test(html)) problem(page, "loads Google's tag directly; analytics.ts must load it after the consent check")
}

const sitemap = existsSync(join(dist, 'sitemap.xml')) ? readFileSync(join(dist, 'sitemap.xml'), 'utf8') : ''
if (!sitemap) problems.push('sitemap.xml is missing')
for (const file of pages) {
  const url = `${SITE}/${relative(dist, file).replace(/(^|\/)index\.html$/, '$1').replace(/\.html$/, '')}`
  if (sitemap && !sitemap.includes(`<loc>${url}</loc>`)) problems.push(`sitemap.xml doesn't list ${url}`)
}

if (readFileSync(join(dist, 'CNAME'), 'utf8').trim() !== 'velairc.app') problems.push('CNAME must contain velairc.app')
if (!readFileSync(join(dist, 'robots.txt'), 'utf8').includes(`Sitemap: ${SITE}/sitemap.xml`)) problems.push('robots.txt must point at the sitemap')
for (const asset of ['og-image.jpg', 'favicon.ico', 'apple-touch-icon.png', 'logo.png']) {
  if (!existsSync(join(dist, asset))) problems.push(`${asset} is missing`)
}

// The update feed Vela's updater reads at https://velairc.app/appcast.xml.
const appcast = join(dist, 'appcast.xml')
if (!existsSync(appcast)) problems.push("appcast.xml (the app's update feed) is missing")
else for (const problem of checkAppcast(readFileSync(appcast, 'utf8'))) problems.push(`appcast.xml: ${problem}`)

if (problems.length) {
  console.error(`check-site: ${problems.length} problem(s)\n  ${problems.join('\n  ')}`)
  process.exit(1)
}
console.log(`check-site: ${pages.length} pages OK`)
