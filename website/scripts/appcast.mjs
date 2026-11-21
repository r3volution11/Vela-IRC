// Vela's update feed: website/public/appcast.xml, served at
// https://velairc.app/appcast.xml, which the app's updater (Sparkle) reads.
// scripts/release.sh --publish adds each release's item with this script;
// scripts/test-update.sh makes a local feed with it; check-site.mjs, the
// release preflight and the tests check feeds with it.
//
//   node website/scripts/appcast.mjs add <appcast.xml> --version 1.1.0 --build 2 \
//       --minimum-system 26.0 --length <bytes> --signature <EdDSA signature> \
//       --notes-file <release notes, Markdown> [--url <Vela.dmg's URL>] \
//       [--date <date>] [--channel <name>] [--repository-base <URL for relative links>]
//   node website/scripts/appcast.mjs check <appcast.xml> [--local]
//   node website/scripts/appcast.mjs has <appcast.xml> --build 2
//   node website/scripts/appcast.mjs empty <appcast.xml>
//
// `add` puts the new item first and keeps every earlier one. Without --url
// the enclosure is the GitHub release asset,
// https://github.com/r3volution11/Vela-IRC/releases/download/v<version>/Vela.dmg.
// The release notes are the changelog section, as HTML in the item's
// description, so Sparkle's window shows them without loading anything
// (and the full changelog is a button away, in the browser).
//
// Channels: an item without <sparkle:channel> is for everyone. A future
// beta channel adds items with --channel beta; only apps that ask for that
// channel (SPUUpdaterDelegate's allowedChannels) see them. Build numbers
// are unique across channels.
//
// `check` exits 1 and lists the problems when the feed isn't well formed
// or an item is incomplete; --local allows enclosures that aren't GitHub
// release assets (scripts/test-update.sh's feed). `has` exits 0 when the
// feed has an item for that build. `empty` writes a feed with no items.

import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

export const SITE = 'https://velairc.app'
export const REPOSITORY = 'https://github.com/r3volution11/Vela-IRC'
export const SPARKLE_NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
export const FULL_NOTES_URL = `${SITE}/changelog`

/** The enclosure URL of a release: its Vela.dmg on GitHub. */
export const releaseAssetURL = (version) => `${REPOSITORY}/releases/download/v${version}/Vela.dmg`

// ─── Escaping ────────────────────────────────────────────────────────────

const escapeXML = (text) =>
  String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

/** HTML text, with the few tags the changelog may use (<kbd>, <br>) kept. */
const escapeHTMLText = (text) =>
  escapeXML(text).replace(/&lt;(\/?)(kbd|br)\s*(\/?)&gt;/g, '<$1$2$3>')

// ─── Release notes: Markdown → HTML ──────────────────────────────────────

/**
 * Resolves a changelog link: absolute URLs stay; `/guide/…` and `#anchor`
 * are the website's; anything else is a file in the repository.
 */
export function resolveLink(url, repositoryBase = `${REPOSITORY}/blob/main/`) {
  if (/^(https?:|mailto:)/i.test(url)) return url
  if (url.startsWith('/')) return SITE + url
  if (url.startsWith('#')) return FULL_NOTES_URL + url
  return repositoryBase + url.replace(/^\.\//, '')
}

/** Inline Markdown (code, bold, italics, links) → HTML. */
export function inlineHTML(text, repositoryBase) {
  // Code spans first, so nothing inside them is formatting.
  return text
    .split(/(`[^`]+`)/)
    .map((part, index) => {
      if (index % 2 === 1) return `<code>${escapeXML(part.slice(1, -1))}</code>`
      let html = escapeHTMLText(part)
      html = html.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_, label, url) => `<a href="${escapeXML(resolveLink(url.replace(/&amp;/g, '&'), repositoryBase))}">${label}</a>`)
      html = html.replace(/\*\*([^*]+?)\*\*/g, '<strong>$1</strong>')
      html = html.replace(/(^|[^\w*])\*([^*\s][^*]*?)\*(?=[^\w*]|$)/g, '$1<em>$2</em>')
      html = html.replace(/(^|[^\w])_([^_\s][^_]*?)_(?=[^\w]|$)/g, '$1<em>$2</em>')
      return html
    })
    .join('')
}

/**
 * The changelog's Markdown (headings, paragraphs, nested bullet and
 * numbered lists, inline formatting) → HTML.
 */
export function markdownToHTML(markdown, { repositoryBase } = {}) {
  const inline = (text) => inlineHTML(text, repositoryBase)

  // Blocks: headings, paragraphs, and runs of list items (with their indent).
  const blocks = []
  let last = null // the block a wrapped line continues
  for (const raw of markdown.replace(/\r\n?/g, '\n').split('\n')) {
    const line = raw.replace(/\s+$/, '')
    if (!line.trim()) {
      if (last?.type === 'paragraph') last = null
      continue
    }
    const heading = line.match(/^(#{1,6})\s+(.*)$/)
    const listItem = line.match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/)
    if (heading) {
      blocks.push({ type: 'heading', level: heading[1].length, text: heading[2] })
      last = null
    } else if (listItem) {
      const item = { indent: listItem[1].replace(/\t/g, '    ').length, ordered: /^\d/.test(listItem[2]), lines: [listItem[3].trim()] }
      if (blocks.at(-1)?.type !== 'list') blocks.push({ type: 'list', items: [] })
      blocks.at(-1).items.push(item)
      last = item
    } else if (last && (last.lines || last.type === 'paragraph') && (/^\s/.test(raw) || last.type === 'paragraph')) {
      // A wrapped line of the open list item or paragraph.
      last.lines.push(line.trim())
    } else {
      last = { type: 'paragraph', lines: [line.trim()] }
      blocks.push(last)
    }
  }

  // A list from items[start], at its indent; deeper items nest in the item
  // before them. Returns the HTML and the index after the list.
  const list = (items, start) => {
    const { indent, ordered } = items[start]
    const tag = ordered ? 'ol' : 'ul'
    let html = `<${tag}>`
    let i = start
    while (i < items.length && items[i].indent >= indent) {
      if (items[i].indent === indent && items[i].ordered !== ordered) break
      html += `<li>${inline(items[i].lines.join(' '))}`
      i++
      while (i < items.length && items[i].indent > indent) {
        const [nested, next] = list(items, i)
        html += nested
        i = next
      }
      html += '</li>'
    }
    return [`${html}</${tag}>`, i]
  }

  const out = []
  for (const block of blocks) {
    if (block.type === 'heading') {
      const level = Math.min(6, block.level)
      out.push(`<h${level}>${inline(block.text)}</h${level}>`)
    } else if (block.type === 'paragraph') {
      out.push(`<p>${inline(block.lines.join(' '))}</p>`)
    } else {
      for (let i = 0; i < block.items.length; ) {
        const [html, next] = list(block.items, i)
        out.push(html)
        i = next
      }
    }
  }
  return out.join('\n')
}

/** The release notes Sparkle's window shows: styled for its web view. */
export function releaseNotesHTML(markdown, options = {}) {
  const style = [
    'body { margin: 0 4px; line-height: 1.45; }',
    'h3, h4 { margin: 1.1em 0 0.4em; }',
    'h3:first-child, h4:first-child { margin-top: 0.2em; }',
    'ul, ol { padding-left: 1.3em; margin: 0.3em 0; }',
    'li { margin: 0.25em 0; }',
    'code, kbd { font-family: ui-monospace, Menlo, monospace; font-size: 0.92em; }',
    'kbd { border: 1px solid rgba(127, 127, 127, 0.45); border-radius: 4px; padding: 0 4px; }',
  ].join(' ')
  return `<style>${style}</style>\n${markdownToHTML(markdown, options)}`
}

// ─── Items ───────────────────────────────────────────────────────────────

/** `new Date()` → "Thu, 20 Nov 2026 18:04:05 +0000" (RSS's date format). */
export function rfc822(date) {
  return date.toUTCString().replace('GMT', '+0000')
}

/**
 * One release's <item>.
 * @param {object} release
 * @param {string} release.version   "1.1.0" (CFBundleShortVersionString)
 * @param {string|number} release.build  "2" (CFBundleVersion)
 * @param {string} release.minimumSystemVersion  "26.0"
 * @param {string} release.url        the DMG's URL
 * @param {number|string} release.length  the DMG's size in bytes
 * @param {string} release.signature  its EdDSA signature (sign_update)
 * @param {string} release.notesHTML  the release notes
 * @param {Date} [release.date]
 * @param {string} [release.channel]  a Sparkle channel, e.g. "beta"; none for everyone
 */
export function itemXML(release) {
  const date = release.date ?? new Date()
  if (String(release.notesHTML).includes(']]>')) throw new Error('release notes contain "]]>"')
  const lines = [
    '    <item>',
    `      <title>Vela ${escapeXML(release.version)}</title>`,
    `      <pubDate>${rfc822(date)}</pubDate>`,
    `      <sparkle:version>${escapeXML(release.build)}</sparkle:version>`,
    `      <sparkle:shortVersionString>${escapeXML(release.version)}</sparkle:shortVersionString>`,
    `      <sparkle:minimumSystemVersion>${escapeXML(release.minimumSystemVersion)}</sparkle:minimumSystemVersion>`,
  ]
  if (release.channel) lines.push(`      <sparkle:channel>${escapeXML(release.channel)}</sparkle:channel>`)
  lines.push(
    `      <sparkle:fullReleaseNotesLink>${FULL_NOTES_URL}</sparkle:fullReleaseNotesLink>`,
    `      <description><![CDATA[${release.notesHTML}]]></description>`,
    `      <enclosure url="${escapeXML(release.url)}" length="${escapeXML(release.length)}" type="application/octet-stream" sparkle:edSignature="${escapeXML(release.signature)}"/>`,
    '    </item>',
  )
  return lines.join('\n')
}

/** A feed with no items yet. */
export function emptyAppcast() {
  return `<?xml version="1.0" encoding="utf-8"?>
<!--
  Vela's update feed, read by the app's updater (Sparkle) at
  https://velairc.app/appcast.xml. Don't edit it by hand: scripts/release.sh
  adds each release's item with website/scripts/appcast.mjs (newest first),
  and docs/RELEASING.md, "Updates", explains it.
-->
<rss version="2.0" xmlns:sparkle="${SPARKLE_NS}">
  <channel>
    <title>Vela</title>
    <link>${SITE}</link>
    <description>New versions of Vela, the IRC client for macOS.</description>
    <language>en</language>
  </channel>
</rss>
`
}

/** The parts of each item that matter for checking and ordering. */
export function parseItems(xml) {
  const items = []
  for (const match of stripCDATA(xml).matchAll(/<item>([\s\S]*?)<\/item>/g)) {
    const body = match[1]
    const field = (name) => body.match(new RegExp(`<${name}>([^<]*)</${name}>`))?.[1]
    const enclosure = body.match(/<enclosure\s([^>]*)\/?>/)?.[1] ?? ''
    const attribute = (name) => enclosure.match(new RegExp(`${name}="([^"]*)"`))?.[1]
    items.push({
      title: field('title'),
      pubDate: field('pubDate'),
      build: field('sparkle:version'),
      version: field('sparkle:shortVersionString'),
      minimumSystemVersion: field('sparkle:minimumSystemVersion'),
      channel: field('sparkle:channel'),
      hasDescription: /<description>/.test(body),
      url: attribute('url')?.replace(/&amp;/g, '&'),
      length: attribute('length'),
      type: attribute('type'),
      signature: attribute('sparkle:edSignature'),
    })
  }
  return items
}

/** `xml` with each CDATA section's contents removed (so markup in release notes isn't read as the feed's). */
const stripCDATA = (xml) => xml.replace(/<!\[CDATA\[[\s\S]*?\]\]>/g, '<![CDATA[]]>')

/**
 * Adds `release`'s item to the feed `xml`, before every earlier one.
 * Refuses a build number the feed already has.
 */
export function addItem(xml, release) {
  const items = parseItems(xml)
  if (items.some((item) => item.build === String(release.build))) {
    throw new Error(`the feed already has build ${release.build}`)
  }
  if (items.some((item) => item.version === release.version && (item.channel ?? '') === (release.channel ?? ''))) {
    throw new Error(`the feed already has version ${release.version}${release.channel ? ` in the ${release.channel} channel` : ''}`)
  }
  const item = itemXML(release)
  const first = xml.search(/^\s*<item>/m)
  if (first >= 0) return `${xml.slice(0, first)}${item}\n${xml.slice(first)}`
  const end = xml.lastIndexOf('  </channel>')
  if (end < 0) throw new Error('the feed has no </channel>')
  return `${xml.slice(0, end)}${item}\n${xml.slice(end)}`
}

// ─── Checking ────────────────────────────────────────────────────────────

/** Problems with the feed's XML itself: unbalanced or misnested tags. */
export function wellFormednessProblems(xml) {
  const problems = []
  if (!xml.startsWith('<?xml ')) problems.push('it doesn\'t start with an XML declaration')
  const text = xml.replace(/<!\[CDATA\[[\s\S]*?\]\]>/g, '').replace(/<!--[\s\S]*?-->/g, '').replace(/<\?[\s\S]*?\?>/g, '')
  if (/<!\[CDATA\[|<!--/.test(text)) problems.push('a CDATA section or comment isn\'t closed')
  const stack = []
  for (const [tag, closing, name, attributes, selfClosing] of text.matchAll(/<(\/?)([A-Za-z_][\w:.-]*)([^<>]*?)(\/?)>/g)) {
    if ((attributes.match(/"/g) ?? []).length % 2) problems.push(`an attribute isn't closed in ${tag}`)
    if (closing) {
      const open = stack.pop()
      if (open !== name) problems.push(`</${name}> closes <${open ?? 'nothing'}>`)
    } else if (!selfClosing) {
      stack.push(name)
    }
  }
  if (stack.length) problems.push(`unclosed: ${stack.map((name) => `<${name}>`).join(', ')}`)
  if (/&(?!(amp|lt|gt|quot|apos|#\d+|#x[\da-fA-F]+);)/.test(text)) problems.push('a bare & (write &amp;)')
  return problems
}

/**
 * Everything wrong with a feed: its XML, and each item's fields. `local`
 * allows enclosures that aren't GitHub release assets.
 */
export function checkAppcast(xml, { local = false } = {}) {
  const problems = wellFormednessProblems(xml)
  if (!xml.includes(`xmlns:sparkle="${SPARKLE_NS}"`)) problems.push("the <rss> element doesn't declare Sparkle's namespace")
  if ((xml.match(/<channel>/g) ?? []).length !== 1) problems.push('there must be exactly one <channel>')
  const items = parseItems(xml)
  const builds = new Set()
  let previous
  for (const item of items) {
    const name = `item ${item.version ?? '?'} (${item.build ?? '?'})`
    const problem = (message) => problems.push(`${name}: ${message}`)
    if (!/^\d+$/.test(item.build ?? '')) problem('<sparkle:version> must be the build number')
    else if (builds.has(item.build)) problem('its build number is in the feed twice')
    builds.add(item.build)
    if (!/^\d+\.\d+\.\d+$/.test(item.version ?? '')) problem('<sparkle:shortVersionString> must be <major>.<minor>.<patch>')
    if (!/^\d+\.\d+(\.\d+)?$/.test(item.minimumSystemVersion ?? '')) problem('it needs <sparkle:minimumSystemVersion>')
    if (!item.pubDate || Number.isNaN(Date.parse(item.pubDate))) problem('it needs a <pubDate>')
    if (!item.title) problem('it needs a <title>')
    if (!item.hasDescription) problem('it needs release notes (<description>)')
    if (item.channel !== undefined && !/^[A-Za-z0-9_.-]+$/.test(item.channel)) problem('a channel name is letters, digits, dashes, underscores and periods')
    if (!/^\d+$/.test(item.length ?? '') || Number(item.length) <= 0) problem('the enclosure needs its length in bytes')
    if (!/^[A-Za-z0-9+/]{86}==$/.test(item.signature ?? '')) problem('the enclosure needs an EdDSA signature (sparkle:edSignature, from sign_update)')
    if (item.type !== 'application/octet-stream') problem('the enclosure\'s type must be application/octet-stream')
    if (!local && item.version && item.url !== releaseAssetURL(item.version)) problem(`the enclosure must be ${releaseAssetURL(item.version)}`)
    if (local && !/^https?:\/\//.test(item.url ?? '')) problem('the enclosure needs a URL')
    if (previous && /^\d+$/.test(item.build ?? '') && Number(item.build) > Number(previous)) problem('items must be newest first')
    previous = item.build
  }
  return problems
}

// ─── Command line ────────────────────────────────────────────────────────

function options(args) {
  const result = { _: [] }
  for (let i = 0; i < args.length; i++) {
    const arg = args[i]
    if (arg.startsWith('--')) {
      const name = arg.slice(2)
      if (name === 'local') result.local = true
      else if (i + 1 < args.length) result[name] = args[++i]
      else throw new Error(`${arg} needs a value`)
    } else {
      result._.push(arg)
    }
  }
  return result
}

function main(argv) {
  const [command, ...rest] = argv
  const opts = options(rest)
  const file = opts._[0]
  if (!file) throw new Error('usage: appcast.mjs add|check|has|empty <appcast.xml> […]')
  if (command === 'empty') {
    writeFileSync(file, emptyAppcast())
    return 0
  }
  if (command === 'check') {
    const problems = checkAppcast(readFileSync(file, 'utf8'), { local: opts.local })
    for (const problem of problems) console.error(`${file}: ${problem}`)
    return problems.length ? 1 : 0
  }
  if (command === 'has') {
    return parseItems(readFileSync(file, 'utf8')).some((item) => item.build === String(opts.build)) ? 0 : 1
  }
  if (command !== 'add') throw new Error(`unknown command ${command}`)
  for (const name of ['version', 'build', 'minimum-system', 'length', 'signature', 'notes-file']) {
    if (!opts[name]) throw new Error(`add needs --${name}`)
  }
  if (opts.channel && !/^[A-Za-z0-9_.-]+$/.test(opts.channel)) throw new Error(`bad channel name ${opts.channel}`)
  const notes = readFileSync(opts['notes-file'], 'utf8')
  const xml = addItem(readFileSync(file, 'utf8'), {
    version: opts.version,
    build: opts.build,
    minimumSystemVersion: opts['minimum-system'],
    url: opts.url ?? releaseAssetURL(opts.version),
    length: opts.length,
    signature: opts.signature,
    notesHTML: releaseNotesHTML(notes, { repositoryBase: opts['repository-base'] ?? `${REPOSITORY}/blob/v${opts.version}/` }),
    date: opts.date ? new Date(opts.date) : new Date(),
    channel: opts.channel,
  })
  const problems = checkAppcast(xml, { local: Boolean(opts.url && opts.url !== releaseAssetURL(opts.version)) })
  if (problems.length) throw new Error(`the new feed has problems:\n  ${problems.join('\n  ')}`)
  writeFileSync(file, xml)
  console.log(`${file}: added Vela ${opts.version} (${opts.build})${opts.channel ? ` to the ${opts.channel} channel` : ''}`)
  return 0
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    process.exit(main(process.argv.slice(2)))
  } catch (error) {
    console.error(`appcast: ${error.message}`)
    process.exit(2)
  }
}
