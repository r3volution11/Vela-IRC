// Checks the website's analytics rules (who is asked, which links count).
//   npm test
import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  asksForConsent,
  codeLanguage,
  decide,
  eventForLink,
  searchTerm,
} from '../.vitepress/theme/analyticsRules.ts'

const BASE = 'https://velairc.app/guide/install'

test('European time zones are asked first', () => {
  for (const zone of ['Europe/Berlin', 'Europe/London', 'Europe/Zurich', 'Europe/Dublin', 'Atlantic/Reykjavik', 'Atlantic/Canary', 'Atlantic/Azores', 'Africa/Ceuta', 'Arctic/Longyearbyen']) {
    assert.equal(asksForConsent(zone), true, zone)
  }
  for (const zone of ['America/Chicago', 'America/New_York', 'Asia/Tokyo', 'Australia/Sydney', 'Atlantic/Bermuda', 'Africa/Lagos', 'UTC', '']) {
    assert.equal(asksForConsent(zone), false, zone)
  }
})

test('a stored choice wins, then Global Privacy Control, then the time zone', () => {
  const us = 'America/Chicago'
  const eu = 'Europe/Paris'
  assert.deepEqual(decide({ choice: null, timeZone: us, globalPrivacyControl: false }), { load: true, ask: false })
  assert.deepEqual(decide({ choice: null, timeZone: eu, globalPrivacyControl: false }), { load: false, ask: true })
  assert.deepEqual(decide({ choice: 'granted', timeZone: eu, globalPrivacyControl: false }), { load: true, ask: false })
  assert.deepEqual(decide({ choice: 'denied', timeZone: us, globalPrivacyControl: false }), { load: false, ask: false })
  assert.deepEqual(decide({ choice: null, timeZone: us, globalPrivacyControl: true }), { load: false, ask: false })
  assert.deepEqual(decide({ choice: null, timeZone: eu, globalPrivacyControl: true }), { load: false, ask: false })
  // Choosing Allow on the Privacy page overrides Global Privacy Control.
  assert.deepEqual(decide({ choice: 'granted', timeZone: us, globalPrivacyControl: true }), { load: true, ask: false })
})

test('Vela.dmg links are downloads', () => {
  for (const href of [
    'https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg',
    'https://github.com/r3volution11/Vela-IRC/releases/download/v1.0.0/Vela-1.0.0.dmg',
  ]) {
    const event = eventForLink(href, BASE)
    assert.equal(event?.name, 'vela_download', href)
  }
  assert.deepEqual(eventForLink('https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg', BASE), {
    name: 'vela_download',
    params: { file_name: 'Vela.dmg' },
  })
})

test('other repository links are typed', () => {
  const cases: [string, string][] = [
    ['https://github.com/r3volution11/Vela-IRC', 'repository'],
    ['https://github.com/r3volution11/Vela-IRC#building-from-source', 'repository'],
    ['https://github.com/r3volution11/Vela-IRC/issues/new/choose', 'issues'],
    ['https://github.com/r3volution11/Vela-IRC/discussions', 'discussions'],
    ['https://github.com/r3volution11/Vela-IRC/releases', 'releases'],
    ['https://github.com/r3volution11/Vela-IRC/pulls', 'pull_requests'],
    ['https://github.com/r3volution11/Vela-IRC/edit/main/website/guide/install.md', 'edit_page'],
    ['https://github.com/r3volution11/Vela-IRC/blob/main/ROADMAP.md', 'source'],
    ['https://github.com/r3volution11/Vela-IRC/tree/main/docs', 'source'],
    ['https://github.com/r3volution11/Vela-IRC.git', 'clone'],
  ]
  for (const [href, type] of cases) {
    assert.deepEqual(eventForLink(href, BASE), { name: 'github_repo_click', params: { link_type: type } }, href)
  }
})

test('links elsewhere are left to Google’s own outbound tracking', () => {
  for (const href of [
    '/guide/first-launch',
    '#uninstalling',
    'https://github.com/r3volution11',
    'https://github.com/r3volution11/Vela-IRC-other',
    'https://github.com/someone/Vela-IRC',
    'https://code.visualstudio.com',
    'mailto:someone@example.com',
    'http://[bad',
  ]) {
    assert.equal(eventForLink(href, BASE), null, href)
  }
})

test('code languages and search terms', () => {
  assert.equal(codeLanguage('language-jsonc vp-adaptive-theme active'), 'jsonc')
  assert.equal(codeLanguage('language-sh vp-adaptive-theme'), 'sh')
  assert.equal(codeLanguage('vp-adaptive-theme'), 'unknown')
  assert.equal(searchTerm('  tab   stacks '), 'tab stacks')
  assert.equal(searchTerm('a'), null)
  assert.equal(searchTerm('   '), null)
  assert.equal(searchTerm('x'.repeat(300))?.length, 100)
})
