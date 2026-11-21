// Checks the update feed tools (appcast.mjs): release notes, adding items,
// keeping earlier ones, and checking a feed.
//   npm test
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync, spawnSync } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  addItem,
  checkAppcast,
  emptyAppcast,
  markdownToHTML,
  parseItems,
  releaseAssetURL,
  releaseNotesHTML,
  wellFormednessProblems,
} from './appcast.mjs'

const here = dirname(fileURLToPath(import.meta.url))
// 64 bytes of base64, like sign_update's output.
const SIGNATURE_A = 'N9EyxoG6KK9yWmOkIG4CtoniRIMwAsxCWwBBu72lLqDaD30hI3St4ctV8JQ99eM4gueD6Z+uWYk7rKzCuoQZCg=='
const SIGNATURE_B = 'WVyVJpOx+a5+vNWJVY79TRjFKveNk+VhGJf2iti4CZtJsJewIUGvh/1AKKEAFbH1qUwx+vro1ECuzOsMmumoBA=='

const NOTES = `### Updates

- **Vela updates itself.** Choose **Vela → Check for Updates…**, or let it check
  once a day. See [Updates](/guide/updates) and the [roadmap](ROADMAP.md).
  - The ban mask stays \`*!*@host\`, and *this* is emphasis.
  - Off with \`updates.checkAutomatically\`.
- Fixed a crash ([details](https://example.com/a?b=1&c=2)).

1. First
2. Second
`

const release = (overrides = {}) => ({
  version: '1.1.0',
  build: '2',
  minimumSystemVersion: '26.0',
  url: releaseAssetURL('1.1.0'),
  length: 23456789,
  signature: SIGNATURE_A,
  notesHTML: releaseNotesHTML(NOTES, { repositoryBase: 'https://github.com/r3volution11/Vela-IRC/blob/v1.1.0/' }),
  date: new Date('2026-12-01T10:00:00Z'),
  ...overrides,
})

const hasXmllint = spawnSync('xmllint', ['--version']).status === 0

test('release notes: headings, nested lists, wrapped lines and inline formatting', () => {
  const html = markdownToHTML(NOTES, { repositoryBase: 'https://github.com/r3volution11/Vela-IRC/blob/v1.1.0/' })
  assert.equal(
    html,
    [
      '<h3>Updates</h3>',
      '<ul><li><strong>Vela updates itself.</strong> Choose <strong>Vela → Check for Updates…</strong>, or let it check once a day. ' +
        'See <a href="https://velairc.app/guide/updates">Updates</a> and the <a href="https://github.com/r3volution11/Vela-IRC/blob/v1.1.0/ROADMAP.md">roadmap</a>.' +
        '<ul><li>The ban mask stays <code>*!*@host</code>, and <em>this</em> is emphasis.</li><li>Off with <code>updates.checkAutomatically</code>.</li></ul></li>' +
        '<li>Fixed a crash (<a href="https://example.com/a?b=1&amp;c=2">details</a>).</li></ul>',
      '<ol><li>First</li><li>Second</li></ol>',
    ].join('\n'),
  )
})

test('release notes escape HTML but keep <kbd>', () => {
  assert.equal(markdownToHTML('Press <kbd>⌘</kbd><kbd>Q</kbd> & <script>x</script>'), '<p>Press <kbd>⌘</kbd><kbd>Q</kbd> &amp; &lt;script&gt;x&lt;/script&gt;</p>')
  assert.match(releaseNotesHTML('- a'), /^<style>[^<]*<\/style>\n<ul><li>a<\/li><\/ul>$/)
})

test('the first item goes into an empty feed', () => {
  const xml = addItem(emptyAppcast(), release())
  assert.deepEqual(checkAppcast(xml), [])
  const [item] = parseItems(xml)
  assert.equal(item.version, '1.1.0')
  assert.equal(item.build, '2')
  assert.equal(item.minimumSystemVersion, '26.0')
  assert.equal(item.signature, SIGNATURE_A)
  assert.equal(item.length, '23456789')
  assert.equal(item.url, 'https://github.com/r3volution11/Vela-IRC/releases/download/v1.1.0/Vela.dmg')
  assert.equal(item.type, 'application/octet-stream')
  assert.equal(item.channel, undefined)
  assert.equal(item.pubDate, 'Tue, 01 Dec 2026 10:00:00 +0000')
  assert.match(xml, /<sparkle:fullReleaseNotesLink>https:\/\/velairc\.app\/changelog<\/sparkle:fullReleaseNotesLink>/)
  assert.match(xml, /<description><!\[CDATA\[<style>/)
})

test('a new release goes first and earlier items are kept as they were', () => {
  const first = addItem(emptyAppcast(), release())
  const firstItem = first.match(/ {4}<item>[\s\S]*?<\/item>/)[0]
  const second = addItem(first, release({ version: '1.2.0', build: '3', url: releaseAssetURL('1.2.0'), length: 24000000, signature: SIGNATURE_B }))
  assert.deepEqual(checkAppcast(second), [])
  assert.deepEqual(parseItems(second).map((item) => item.build), ['3', '2'])
  assert.ok(second.includes(firstItem), 'the 1.1.0 item is unchanged')
  assert.equal(parseItems(second)[0].signature, SIGNATURE_B)
  assert.equal(parseItems(second)[0].length, '24000000')
  // The feed around the items is untouched.
  assert.ok(second.startsWith(emptyAppcast().split('  </channel>')[0]))
})

test('a build or version that is already there is refused', () => {
  const xml = addItem(emptyAppcast(), release())
  assert.throws(() => addItem(xml, release({ version: '1.1.1' })), /already has build 2/)
  assert.throws(() => addItem(xml, release({ build: '3' })), /already has version 1\.1\.0/)
})

test('a beta channel item carries <sparkle:channel>', () => {
  const xml = addItem(addItem(emptyAppcast(), release()), release({ version: '1.2.0', build: '3', url: releaseAssetURL('1.2.0'), channel: 'beta' }))
  assert.deepEqual(checkAppcast(xml), [])
  assert.deepEqual(parseItems(xml).map((item) => item.channel), ['beta', undefined])
  assert.match(xml, /<sparkle:channel>beta<\/sparkle:channel>/)
})

test('checking finds incomplete items and broken XML', () => {
  const good = addItem(emptyAppcast(), release())
  const problems = (xml, options) => checkAppcast(xml, options).join('\n')
  assert.match(problems(good.replace(SIGNATURE_A, 'abc')), /EdDSA signature/)
  assert.match(problems(good.replace('length="23456789"', 'length="0"')), /length in bytes/)
  assert.match(problems(good.replace('/v1.1.0/Vela.dmg', '/v1.0.0/Vela.dmg')), /enclosure must be/)
  assert.deepEqual(checkAppcast(good.replace(releaseAssetURL('1.1.0'), 'http://localhost:8123/Vela.dmg'), { local: true }), [])
  assert.match(problems(good.replace('<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>', '')), /minimumSystemVersion/)
  assert.match(problems(good.replace('</title>', '')), /closes|unclosed/)
  assert.match(problems(good.replace('<language>en</language>', '<language>en & more</language>')), /bare &/)
  // Oldest first is wrong: 1.0.1 (1), then 1.1.0 (2).
  const older = addItem(emptyAppcast(), release({ version: '1.0.1', build: '1', url: releaseAssetURL('1.0.1') }))
  const newerItem = good.match(/ {4}<item>[\s\S]*?<\/item>/)[0]
  assert.match(problems(older.replace('  </channel>', `${newerItem}\n  </channel>`)), /newest first/)
  assert.deepEqual(wellFormednessProblems(emptyAppcast()), [])
})

test('the published feed is valid', () => {
  const xml = readFileSync(join(here, '..', 'public', 'appcast.xml'), 'utf8')
  assert.deepEqual(checkAppcast(xml), [])
})

test('the command line adds an item, as scripts/release.sh runs it', () => {
  const dir = mkdtempSync(join(tmpdir(), 'vela-appcast-'))
  try {
    const feed = join(dir, 'appcast.xml')
    const notes = join(dir, 'notes.md')
    writeFileSync(feed, emptyAppcast())
    writeFileSync(notes, NOTES)
    const script = join(here, 'appcast.mjs')
    const add = (version, build, signature) =>
      execFileSync(process.execPath, [script, 'add', feed, '--version', version, '--build', build, '--minimum-system', '26.0',
        '--length', '1234', '--signature', signature, '--notes-file', notes], { encoding: 'utf8' })
    add('1.1.0', '2', SIGNATURE_A)
    add('1.2.0', '3', SIGNATURE_B)
    const xml = readFileSync(feed, 'utf8')
    assert.deepEqual(checkAppcast(xml), [])
    assert.deepEqual(parseItems(xml).map((item) => [item.version, item.signature]), [['1.2.0', SIGNATURE_B], ['1.1.0', SIGNATURE_A]])
    // Relative links point at the files as of the release's tag.
    assert.match(xml, /blob\/v1\.2\.0\/ROADMAP\.md/)
    assert.equal(spawnSync(process.execPath, [script, 'has', feed, '--build', '3']).status, 0)
    assert.equal(spawnSync(process.execPath, [script, 'has', feed, '--build', '4']).status, 1)
    assert.equal(spawnSync(process.execPath, [script, 'check', feed]).status, 0)
    // A second run for the same build fails and leaves the feed alone.
    const again = spawnSync(process.execPath, [script, 'add', feed, '--version', '1.2.0', '--build', '3', '--minimum-system', '26.0',
      '--length', '1', '--signature', SIGNATURE_A, '--notes-file', notes])
    assert.equal(again.status, 2)
    assert.equal(readFileSync(feed, 'utf8'), xml)
    if (hasXmllint) assert.equal(spawnSync('xmllint', ['--noout', feed]).status, 0)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})
