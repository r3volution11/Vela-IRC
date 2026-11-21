// Generates the reference partials the site includes, straight from the
// app's sources, so the website can't drift from the code:
//
//   _generated/settings.md       every settings.json key (SettingKeys.swift + NavigationSettings.swift)
//   _generated/presets.md        what each preset sets (NavigationSettings.swift)
//   _generated/theme-tokens.md   the token reference (docs/THEMES.md, between its TOKEN TABLE markers)
//   _generated/themes.md         the built-in theme gallery (BuiltInThemes/*.json, docs/THEMES.md, docs/THEME-CREDITS.md)
//
// reference/media-sites.md is generated from MediaSites.swift too, but by
// Swift (`vela-media-tool docs --write`), so it's committed; this only checks
// that its generated part is there.
//
// It also warns when a slash command or keyboard shortcut in the app isn't
// mentioned on the corresponding reference page.
//
// Runs before `vitepress dev` and `vitepress build` (see package.json). It
// fails loudly when a source file changes shape, rather than publishing a
// silently incomplete reference.

import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const website = join(dirname(fileURLToPath(import.meta.url)), '..')
const repo = join(website, '..')
const out = join(website, '_generated')
const sources = join(repo, 'Packages/VelaKit/Sources')

const read = (path) => readFileSync(join(repo, path), 'utf8')

function fail(message) {
  console.error(`generate: ${message}`)
  process.exit(1)
}

const warnings = []
const warn = (message) => warnings.push(message)

/** Escapes text for a Markdown table cell (and for Vue, which compiles the page). */
const cell = (text) =>
  String(text).replace(/\|/g, '\\|').replace(/\n/g, ' ').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\{\{/g, '{&#123;')

/** Swift string literal contents → text. */
const unescapeSwift = (text) => text.replace(/\\(["\\])/g, '$1')

/** Strips JSONC comments and trailing commas, leaving strings alone. */
function parseJSONC(text) {
  let result = ''
  let inString = false
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (inString) {
      result += c
      if (c === '\\') result += text[++i]
      else if (c === '"') inString = false
    } else if (c === '"') {
      inString = true
      result += c
    } else if (c === '/' && text[i + 1] === '/') {
      while (i < text.length && text[i] !== '\n') i++
      result += '\n'
    } else if (c === '/' && text[i + 1] === '*') {
      i = text.indexOf('*/', i + 2) + 1
      if (i === 0) break
    } else {
      result += c
    }
  }
  return JSON.parse(result.replace(/,(\s*[}\]])/g, '$1'))
}

mkdirSync(out, { recursive: true })

// ─── Settings ────────────────────────────────────────────────────────────

const settingKeysSwift = read('Packages/VelaKit/Sources/VelaStore/SettingKeys.swift')
const navigationSwift = read('Packages/VelaKit/Sources/VelaStore/NavigationSettings.swift')
const settingsSwift = settingKeysSwift + '\n' + navigationSwift

// Enums stored as strings: `public enum ChatLayout: String, … { case classic … }`.
// `enums` holds each one's values as written in settings.json; `enumCases`
// maps its Swift case names to them (`case host = "*!*@host"`).
const enums = new Map()
const enumCases = new Map()
for (const [, name, body] of settingsSwift.matchAll(/public enum (\w+): String[^{]*\{(.*?)\n\}/gs)) {
  const cases = [...body.matchAll(/^\s*case (\w+)(?:\s*=\s*"([^"]*)")?\s*$/gm)].map((m) => ({ name: m[1], value: m[2] ?? m[1] }))
  enums.set(name, cases.map((c) => c.value))
  enumCases.set(name, new Map(cases.map((c) => [c.name, c.value])))
}

// `public static var chatLayout: SettingKey<ChatLayout> { .init("chat.layout", default: .grouped, summary: "…") }`
const keyDefinitions = new Map()
const keyRE = /public static var (\w+): SettingKey<(.+?)> \{\s*\.init\(\s*"([^"]+)",\s*default:\s*(.+?),\s*summary:\s*"((?:[^"\\]|\\.)*)"\s*\)/gs
for (const [, property, type, key, rawDefault, summary] of settingsSwift.matchAll(keyRE)) {
  keyDefinitions.set(property, { property, type, key, rawDefault: rawDefault.trim(), summary: unescapeSwift(summary) })
}

// Display order: SettingsCatalog.all, then NavigationSettingsCatalog.descriptors.
const catalogBody = (swift, marker) => {
  const start = swift.indexOf(marker)
  if (start < 0) fail(`couldn't find ${marker}`)
  // The array literal ends at the first `]` after the marker's own `[…]`.
  return swift.slice(start, swift.indexOf(']', start + marker.length))
}
const order = [
  ...catalogBody(settingKeysSwift, 'public static var all: [SettingDescriptor]').matchAll(/SettingKey\.(\w+)\.descriptor/g),
  ...catalogBody(navigationSwift, 'static var descriptors: [SettingDescriptor]').matchAll(/SettingKey\.(\w+)\.descriptor/g),
].map((m) => m[1])

if (order.length < 40) fail(`only ${order.length} settings found in the catalog; has SettingKeys.swift changed shape?`)
const missing = order.filter((property) => !keyDefinitions.has(property))
if (missing.length) fail(`couldn't parse the definition of ${missing.join(', ')}`)

/** `[DockBadgeCount]` → `DockBadgeCount`: the enum a list of choices holds, if it is one. */
const listEnum = (type) => {
  const element = type.match(/^\[(\w+)\]$/)?.[1]
  return element && enums.has(element) ? element : undefined
}

function settingDefault({ rawDefault, type }) {
  if (rawDefault === '[:]') return '{}'
  if (rawDefault === '[]') return '[]'
  // A list of choices: `[.mentions, .privateMessages]`.
  const element = listEnum(type)
  if (element && rawDefault.startsWith('[')) {
    const values = rawDefault.slice(1, -1).split(',').map((item) => item.trim()).filter(Boolean)
    const written = values.map((value) => (value.startsWith('.') ? enumCases.get(element).get(value.slice(1)) : undefined))
    values.forEach((value, index) => {
      if (written[index] === undefined) fail(`unknown default ${value} for ${type}`)
    })
    return `[${written.map((value) => JSON.stringify(value)).join(', ')}]`
  }
  if (rawDefault.startsWith('.')) {
    const value = enumCases.get(type)?.get(rawDefault.slice(1))
    if (value === undefined) fail(`unknown default ${rawDefault} for ${type}`)
    return JSON.stringify(value)
  }
  if (rawDefault.startsWith('"')) return JSON.stringify(unescapeSwift(rawDefault.slice(1, -1)))
  if (/^(true|false|-?[\d.]+)$/.test(rawDefault)) return rawDefault
  fail(`can't read default value ${rawDefault}`)
}

const escapeHTML = (text) =>
  String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\{\{/g, '{&#123;').replace(/\*/g, '&#42;')

function settingType({ type }) {
  // Stored as true/false; a missing key or "system" follows macOS.
  if (type === 'SystemFollowingBool') return 'Boolean, or <code>"system"</code> to follow macOS'
  if (enums.has(type)) return `One of ${enums.get(type).map((value) => `<code>"${escapeHTML(value)}"</code>`).join(', ')}`
  const element = listEnum(type)
  if (element) return `Array of any of ${enums.get(element).map((value) => `<code>"${escapeHTML(value)}"</code>`).join(', ')}`
  return {
    String: 'String',
    Bool: 'Boolean',
    Double: 'Number',
    Int: 'Integer',
    '[String]': 'Array of strings',
    '[String: JSONValue]': 'Object',
  }[type] ?? fail(`unknown setting type ${type}`)
}

// Allowed number ranges: `"chat.fontSize": 9...28,` in SettingsMetadata.numberRanges.
const metadataSwift = read('Packages/VelaKit/Sources/VelaStore/SettingsMetadata.swift')
const rangesStart = metadataSwift.indexOf('static let numberRanges')
if (rangesStart < 0) fail("couldn't find SettingsMetadata.numberRanges")
const rangesBody = metadataSwift.slice(rangesStart, metadataSwift.indexOf(']', metadataSwift.indexOf('= [', rangesStart) + 3))
const numberRanges = new Map(
  [...rangesBody.matchAll(/"([^"]+)":\s*(-?[\d_.]+)\.\.\.(-?[\d_.]+)/g)].map(([, key, low, high]) => [
    key,
    [low, high].map((n) => Number(n.replace(/_/g, '')).toLocaleString('en-US')),
  ]),
)
if (numberRanges.size < 5) fail(`only ${numberRanges.size} number ranges found; has SettingsMetadata.swift changed shape?`)

const settings = order.map((property) => {
  const definition = keyDefinitions.get(property)
  const range = numberRanges.get(definition.key)
  const typeLabel = settingType(definition) + (range ? ` from ${range[0]} to ${range[1]}` : '')
  return { ...definition, category: definition.key.split('.')[0], default: settingDefault(definition), typeLabel }
})
for (const key of numberRanges.keys()) {
  if (!settings.some((s) => s.key === key)) fail(`SettingsMetadata.numberRanges has unknown key ${key}`)
}
const settingKeys = new Set(settings.map((s) => s.key))

const categoryNames = {
  appearance: 'Appearance',
  chat: 'Chat',
  sidebar: 'Sidebar',
  memberList: 'Member list',
  media: 'Media',
  notifications: 'Notifications',
  dock: 'Dock',
  highlight: 'Highlights',
  input: 'Input',
  connection: 'Connection',
  channels: 'Channels',
  moderation: 'Moderation',
  history: 'History',
  logging: 'Chat logs',
  navigation: 'Navigation',
  tabs: 'Tabs',
  intelligence: 'Apple Intelligence',
  translation: 'Translation',
  updates: 'Updates',
}

/** Links other settings mentioned in a summary to their rows. A `*` stays a star (ban masks like `*!*@host`), not emphasis. */
const linkKeys = (text) =>
  cell(text).replace(/\*/g, '\\*').replace(/\b([a-zA-Z]+\.[a-zA-Z]+)\b/g, (match) => (settingKeys.has(match) ? `[\`${match}\`](#${match})` : match))

const byCategory = new Map()
for (const setting of settings) {
  if (!byCategory.has(setting.category)) byCategory.set(setting.category, [])
  byCategory.get(setting.category).push(setting)
}

let settingsMd = `<!-- Generated by website/scripts/generate.mjs from SettingKeys.swift and NavigationSettings.swift. Don't edit. -->\n`
for (const [category, entries] of byCategory) {
  settingsMd += `\n## ${categoryNames[category] ?? category}\n\n| Setting | Description |\n| --- | --- |\n`
  for (const s of entries) {
    const key =
      `<a id="${s.key}" class="setting-key" href="#${s.key}"><code>${s.key}</code></a>` +
      `<br><span class="setting-default">Default <code>${escapeHTML(s.default)}</code></span>`
    settingsMd += `| ${key} | ${linkKeys(s.summary)}<br><span class="setting-type">${s.typeLabel}</span> |\n`
  }
}
writeFileSync(join(out, 'settings.md'), settingsMd)

// ─── Presets ─────────────────────────────────────────────────────────────

const presetRE = /public static let (\w+) = SettingsPreset\(\s*id: "([^"]+)",\s*name: "([^"]+)",\s*summary: "((?:[^"\\]|\\.)*)",\s*systemImage: "[^"]*",\s*values: \[(.*?)\]\s*\)/gs
const presets = [...navigationSwift.matchAll(presetRE)].map(([, , id, name, summary, body]) => ({
  id,
  name,
  summary: unescapeSwift(summary),
  values: new Map([...body.matchAll(/"([^"]+)":\s*([^,\n]+),?/g)].map(([, key, value]) => [key, value.trim()])),
}))
if (presets.length !== 4) fail(`expected 4 presets, found ${presets.length}`)

const presetRows = []
for (const preset of presets) {
  for (const key of preset.values.keys()) {
    if (!settingKeys.has(key)) fail(`preset ${preset.id} sets unknown key ${key}`)
    if (!presetRows.includes(key)) presetRows.push(key)
  }
}
let presetsMd = `<!-- Generated by website/scripts/generate.mjs from NavigationSettings.swift. Don't edit. -->\n\n`
presetsMd += `| Setting | ${presets.map((p) => p.name).join(' | ')} |\n| --- |${' --- |'.repeat(presets.length)}\n`
for (const key of presetRows) {
  const values = presets.map((p) => (p.values.has(key) ? `\`${cell(p.values.get(key))}\`` : '—'))
  presetsMd += `| [\`${key}\`](/reference/settings#${key}) | ${values.join(' | ')} |\n`
}
writeFileSync(join(out, 'presets.md'), presetsMd)
writeFileSync(join(out, 'presets.json'), JSON.stringify(presets.map((p) => ({ ...p, values: Object.fromEntries(p.values) })), null, 2))

// ─── Theme tokens ────────────────────────────────────────────────────────

const themesGuide = read('docs/THEMES.md')
const begin = themesGuide.indexOf('<!-- BEGIN TOKEN TABLE -->')
const end = themesGuide.indexOf('<!-- END TOKEN TABLE -->')
if (begin < 0 || end < begin) fail('docs/THEMES.md is missing its TOKEN TABLE markers')
const tokenTable = themesGuide
  .slice(begin + '<!-- BEGIN TOKEN TABLE -->'.length, end)
  .replace(/^### /gm, '## ')
  .trim()
if ((tokenTable.match(/^\| `/gm) || []).length < 100) fail('the token table in docs/THEMES.md looks incomplete')
writeFileSync(
  join(out, 'theme-tokens.md'),
  `<!-- Generated by website/scripts/generate.mjs from docs/THEMES.md. Don't edit. -->\n\n${tokenTable}\n`,
)

// ─── Supported media sites ───────────────────────────────────────────────

const mediaSites = readFileSync(join(website, 'reference/media-sites.md'), 'utf8')
const mediaBegin = mediaSites.indexOf('<!-- BEGIN MEDIA SITES -->')
const mediaEnd = mediaSites.indexOf('<!-- END MEDIA SITES -->')
if (mediaBegin < 0 || mediaEnd < mediaBegin) fail('reference/media-sites.md is missing its MEDIA SITES markers')
if ((mediaSites.slice(mediaBegin, mediaEnd).match(/^\| \[/gm) || []).length < 8) {
  fail('the site tables in reference/media-sites.md look incomplete; run vela-media-tool docs --write (see CONTRIBUTING.md)')
}

// ─── Built-in themes ─────────────────────────────────────────────────────

const themeDir = join(sources, 'VelaTheme/BuiltInThemes')
const themeFiles = readdirSync(themeDir).filter((f) => f.endsWith('.json'))

// The guide's "Built-in themes" table gives the order and a note for each.
const builtInSection = themesGuide.slice(themesGuide.indexOf('## Built-in themes'), themesGuide.indexOf('## Token reference'))
const guideRows = [...builtInSection.matchAll(/^\| ([^|]+) \| (dark|light) \| `([^`]+)` \| (.+) \|$/gm)].map(([, name, type, file, notes]) => ({
  name: name.trim(),
  type,
  file,
  notes: notes.trim(),
}))
if (guideRows.length !== themeFiles.length) {
  fail(`docs/THEMES.md lists ${guideRows.length} built-in themes but BuiltInThemes has ${themeFiles.length} files`)
}

// Credits for ports: "### Dracula — `dracula.json`" sections with Source and License lines.
const credits = read('docs/THEME-CREDITS.md')
const creditByFile = new Map()
for (const section of credits.split(/^### /m).slice(1)) {
  const heading = section.split('\n')[0]
  const files = [...heading.matchAll(/`([^`]+\.json)`/g)].map((m) => m[1])
  const source = section.match(/Source: (?:[^<\n]*?)<([^>]+)>/)?.[1]
  const license = section.match(/License: ([^\n]+)/)?.[1]?.replace(/&lt;[^&]*&gt;/g, '').replace(/\s*\(<[^>]+>\)/g, '').trim()
  for (const file of files) creditByFile.set(file, { source, license })
}

const hexColor = /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/
const swatch = (color, label) =>
  hexColor.test(color ?? '') ? `<span class="swatch" style="background:${color}" title="${label} ${color}"></span>` : ''

let themesMd = `<!-- Generated by website/scripts/generate.mjs from BuiltInThemes/*.json, docs/THEMES.md and docs/THEME-CREDITS.md. Don't edit. -->\n`
let lastFamily = ''
for (const row of guideRows) {
  if (!themeFiles.includes(row.file)) fail(`docs/THEMES.md lists ${row.file}, which isn't a built-in theme`)
  const theme = parseJSONC(readFileSync(join(themeDir, row.file), 'utf8'))
  const id = row.file.replace(/\.json$/, '')
  const c = theme.colors ?? {}
  const family = row.notes.includes('Inspired by Material')
    ? 'Inspired by Material Theme'
    : row.notes.includes('Vela original')
      ? 'Vela originals'
      : 'Ports of editor favorites'
  if (family !== lastFamily) {
    themesMd += `\n## ${family}\n`
    lastFamily = family
  }
  const shot = `/screenshots/theme-${id}.webp`
  if (!existsSync(join(website, 'public', shot))) warn(`no screenshot ${shot}; run website/scripts/screenshots.sh`)

  const credit = creditByFile.get(row.file)
  let creditLine
  if (credit?.license) {
    creditLine = `${row.notes.replace(/\.$/, '')} — ${credit.license}.${credit.source ? ` [Source](${credit.source})` : ''}`
  } else if (family === 'Inspired by Material Theme') {
    creditLine = `${row.notes.replace(/\*\*/g, '')} An original Vela theme; not affiliated with Material Theme.`
  } else {
    creditLine = row.notes.replace(/\*\*/g, '')
  }

  const swatches = [
    swatch(c['window.background'], 'window.background'),
    swatch(c['sidebar.background'], 'sidebar.background'),
    swatch(c['chat.foreground'] ?? c['window.foreground'], 'chat.foreground'),
    swatch(c['accent'], 'accent'),
    swatch(c['chat.link'], 'chat.link'),
    ...(theme.nickColors ?? []).slice(0, 6).map((color) => swatch(color, 'nick color')),
  ].join('')

  themesMd += `
### ${theme.name} {#${id}}

<figure class="theme-shot">
  <a href="${shot}"><img src="${shot}" alt="Vela with the ${theme.name} theme" width="1200" height="750" loading="lazy"></a>
</figure>
<p class="theme-swatches">${swatches}</p>
<p class="theme-meta"><span>${theme.type === 'dark' ? 'Dark' : 'Light'}</span> · <code>${row.file}</code></p>

${theme.description ?? ''}

<p class="theme-credit">${creditLine.replace(/\[Source\]\(([^)]+)\)/, '<a href="$1">Source</a>').replace(/`([^`]+)`/g, '<code>$1</code>')}</p>
`
}
writeFileSync(join(out, 'themes.md'), themesMd)
writeFileSync(
  join(out, 'theme-names.json'),
  JSON.stringify(Object.fromEntries(guideRows.map((row) => [row.file.replace(/\.json$/, ''), row.name])), null, 2),
)

// ─── Image sizes ─────────────────────────────────────────────────────────

/** Pixel size of a WebP or PNG file, from its header. */
function imageSize(bytes) {
  if (bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP') {
    const chunk = bytes.toString('ascii', 12, 16)
    if (chunk === 'VP8 ') return { width: bytes.readUInt16LE(26) & 0x3fff, height: bytes.readUInt16LE(28) & 0x3fff }
    if (chunk === 'VP8L') {
      const bits = bytes.readUInt32LE(21)
      return { width: (bits & 0x3fff) + 1, height: ((bits >> 14) & 0x3fff) + 1 }
    }
    if (chunk === 'VP8X') return { width: bytes.readUIntLE(24, 3) + 1, height: bytes.readUIntLE(27, 3) + 1 }
  }
  if (bytes.readUInt32BE(0) === 0x89504e47) return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) }
  return undefined
}

const imageSizes = {}
for (const dir of ['', 'screenshots']) {
  const full = join(website, 'public', dir)
  if (!existsSync(full)) continue
  for (const file of readdirSync(full).filter((f) => /\.(webp|png)$/.test(f)).sort()) {
    const size = imageSize(readFileSync(join(full, file)))
    if (size) imageSizes[dir ? `${dir}/${file}` : file] = size
  }
}
writeFileSync(join(out, 'image-sizes.json'), JSON.stringify(imageSizes, null, 2))

// ─── Coverage checks ─────────────────────────────────────────────────────

// Every slash command the parser accepts should be on the slash commands page.
const inputCommand = read('Packages/VelaKit/Sources/VelaCore/InputCommand.swift')
const parseSwitch = inputCommand.slice(inputCommand.indexOf('switch command {'))
const commandNames = new Set()
for (const [, list] of parseSwitch.matchAll(/^\s*case ((?:"[a-z]+"(?:,\s*)?)+):/gm)) {
  for (const [, name] of list.matchAll(/"([a-z]+)"/g)) commandNames.add(name)
}
if (commandNames.size < 30) fail(`only ${commandNames.size} slash commands found in InputCommand.swift`)
const slashPage = readFileSync(join(website, 'reference/slash-commands.md'), 'utf8')
for (const name of commandNames) {
  if (!new RegExp(`/${name}\\b`).test(slashPage)) warn(`/${name} isn't documented in reference/slash-commands.md`)
}

// Every shortcut in VelaCommandCatalog.Shortcuts should be on the shortcuts page.
const catalogPath = 'Packages/VelaKit/Sources/VelaUI/Commands/VelaCommandCatalog.swift'
if (existsSync(join(repo, catalogPath))) {
  const catalog = read(catalogPath)
  const keyGlyphs = { upArrow: '↑', downArrow: '↓', leftArrow: '←', rightArrow: '→', return: '↩', escape: '⎋', tab: '⇥' }
  const shortcutsPage = readFileSync(join(website, 'reference/keyboard-shortcuts.md'), 'utf8').replace(/−/g, '-')
  const shortcutRE = /static let (\w+) = KeyboardShortcut\((?:"(.)"|\.(\w+)), modifiers: \[?([^\])]*)\]?\)/g
  // Menus need a shifted character (⌘{), not ⇧ and its key; the page
  // shows the keys you press (⇧⌘[), as ShortcutGlyphs does.
  const unshifted = { '{': '[', '}': ']' }
  for (const [, name, written, special, modifiers] of catalog.matchAll(shortcutRE)) {
    const char = written && (unshifted[written] ?? written)
    const shift = modifiers.includes('.shift') || (written && written in unshifted)
    const glyphs =
      (modifiers.includes('.control') ? '⌃' : '') +
      (modifiers.includes('.option') ? '⌥' : '') +
      (shift ? '⇧' : '') +
      (modifiers.includes('.command') ? '⌘' : '') +
      (char ? char.toUpperCase() : keyGlyphs[special] ?? special)
    if (!shortcutsPage.includes(glyphs)) warn(`${glyphs} (${name}) isn't documented in reference/keyboard-shortcuts.md`)
  }
}

for (const message of warnings) console.warn(`generate: warning: ${message}`)
console.log(`generate: ${settings.length} settings, ${presets.length} presets, ${guideRows.length} themes, ${commandNames.size} slash commands`)
