// Google Analytics for velairc.app, and only for velairc.app: the Vela app
// itself has no analytics of any kind (see /help/privacy).
//
// The Google tag loads only on the live site, and only once it's allowed:
// visitors in the EU, EEA, UK and Switzerland are asked first (judged by time
// zone, see analyticsRules.ts), a browser sending Global Privacy Control
// counts as a "no", and everyone can change their choice on the Privacy page.
// Advertising storage and signals are always off.
//
// Besides what Google's tag measures on its own (the first page view,
// scrolling, outbound clicks), this sends:
//   page_view          each page after the first, with the new page's title
//   vela_download      a click on a Vela.dmg link (file_name, placement)
//   github_repo_click  any other link into the repository (link_type, placement)
//   copy_code          a code block's copy button (code_language)
//   search             the site search, once typing pauses (search_term, result_count)
// Add ?analytics=debug to any URL to log events to the console (and
// window.__velaAnalytics) instead of sending them; it lasts for the tab.

import { nextTick, ref } from 'vue'
import type { Router } from 'vitepress'
import { ANALYTICS_HOSTS, GA_MEASUREMENT_ID, GOOGLE_TAG_ID } from './constants'
import {
  CONSENT_REGIONS,
  PLACEMENTS,
  codeLanguage,
  decide,
  eventForLink,
  searchTerm,
  type Choice,
} from './analyticsRules'

const STORAGE_KEY = 'vela-analytics'
const DEBUG_KEY = 'vela-analytics-debug'
const SEARCH_PAUSE_MS = 1200

/**
 * What the banner and the Privacy page show: `unavailable` off the live site,
 * `ask` until an EU/UK visitor chooses, then `on` or `off`.
 */
export const analyticsStatus = ref<'unavailable' | 'ask' | 'on' | 'off'>('unavailable')
/** Off because the browser sends Global Privacy Control, not by a choice made here. */
export const offByPrivacyControl = ref(false)
/** Whether the consent banner is showing. */
export const bannerOpen = ref(false)

declare global {
  interface Window {
    dataLayer: unknown[]
    __velaAnalytics?: { name: string; params: Record<string, unknown> }[]
  }
}

let mode: 'off' | 'live' | 'debug' = 'off'
let tagLoaded = false
let measuring = false

// Google's tag reads the arguments object itself, not an array.
function gtag(..._args: unknown[]): void {
  // eslint-disable-next-line prefer-rest-params
  window.dataLayer.push(arguments)
}

function storage(kind: 'local' | 'session'): Storage | null {
  try {
    return kind === 'local' ? window.localStorage : window.sessionStorage
  } catch {
    return null
  }
}

function readChoice(): Choice {
  try {
    const value = storage('local')?.getItem(STORAGE_KEY)
    return value === 'granted' || value === 'denied' ? value : null
  } catch {
    return null
  }
}

function track(name: string, params: Record<string, unknown> = {}): void {
  if (!measuring) return
  if (mode === 'debug') {
    ;(window.__velaAnalytics ??= []).push({ name, params })
    console.info('[analytics]', name, params)
    return
  }
  gtag('event', name, params)
}

function loadTag(): void {
  measuring = true
  if (mode === 'live') (window as unknown as Record<string, boolean>)[`ga-disable-${GA_MEASUREMENT_ID}`] = false
  if (tagLoaded) return
  tagLoaded = true
  if (mode === 'debug') {
    ;(window.__velaAnalytics ??= []).push({ name: 'page_view', params: { initial: true, page_title: document.title } })
    return
  }
  // The install code Google gives for this tag.
  gtag('js', new Date())
  const script = document.createElement('script')
  script.async = true
  script.src = `https://www.googletagmanager.com/gtm.js?id=${GOOGLE_TAG_ID}`
  document.head.appendChild(script)
}

/** Google Analytics' own cookies: _ga and _ga_<property>. */
function deleteCookies(): void {
  const host = location.hostname
  const domains = ['', `; domain=${host}`, `; domain=.${host.replace(/^www\./, '')}`]
  for (const part of document.cookie.split(';')) {
    const name = part.split('=')[0].trim()
    if (!/^_ga(_|$)/.test(name)) continue
    for (const domain of domains) document.cookie = `${name}=; Max-Age=0; path=/${domain}`
  }
}

/** Records the visitor's choice, from the banner or the Privacy page. */
export function setChoice(choice: 'granted' | 'denied'): void {
  try {
    storage('local')?.setItem(STORAGE_KEY, choice)
  } catch {
    // Private browsing can refuse storage; the choice still holds for this visit.
  }
  bannerOpen.value = false
  offByPrivacyControl.value = false
  if (mode === 'off') return
  if (choice === 'granted') {
    gtag('consent', 'update', { analytics_storage: 'granted' })
    analyticsStatus.value = 'on'
    loadTag()
  } else {
    measuring = false
    gtag('consent', 'update', { analytics_storage: 'denied' })
    if (mode === 'live') (window as unknown as Record<string, boolean>)[`ga-disable-${GA_MEASUREMENT_ID}`] = true
    deleteCookies()
    analyticsStatus.value = 'off'
  }
}

function placementOf(element: Element): string {
  for (const [selector, placement] of PLACEMENTS) {
    if (element.closest(selector)) return placement
  }
  return 'other'
}

function onClick(event: MouseEvent): void {
  if (event.type === 'auxclick' && event.button !== 1) return
  const target = event.target
  if (!(target instanceof Element)) return

  const copy = target.closest('button.copy')
  if (copy) {
    track('copy_code', { code_language: codeLanguage(copy.closest('div[class*="language-"]')?.className ?? '') })
    return
  }

  if (target.closest('.VPLocalSearchBox .result')) flushSearch()

  const link = target.closest('a')
  const href = link?.getAttribute('href')
  if (!link || !href) return
  const linkEvent = eventForLink(href, location.href)
  if (!linkEvent) return
  track(linkEvent.name, {
    ...linkEvent.params,
    link_url: link.href,
    link_text: (link.textContent ?? '').trim().replace(/\s+/g, ' ').slice(0, 100) || link.getAttribute('aria-label') || '',
    placement: placementOf(link),
  })
}

// Site search: count a term once typing pauses, or as soon as a result is picked.
let pendingTerm: string | null = null
let searchTimer: ReturnType<typeof setTimeout> | undefined
let lastSearch = ''

function flushSearch(): void {
  clearTimeout(searchTimer)
  const term = pendingTerm
  pendingTerm = null
  if (!term || term === lastSearch) return
  lastSearch = term
  track('search', {
    search_term: term,
    result_count: document.querySelectorAll('.VPLocalSearchBox .result').length,
  })
}

function onInput(event: Event): void {
  const target = event.target
  if (!(target instanceof HTMLInputElement) || target.id !== 'localsearch-input') return
  pendingTerm = searchTerm(target.value)
  clearTimeout(searchTimer)
  searchTimer = setTimeout(flushSearch, SEARCH_PAUSE_MS)
}

/** Called once, from the theme's enhanceApp, in the browser. */
export function initAnalytics(router: Router): void {
  if (typeof window === 'undefined' || mode !== 'off') return

  const session = storage('session')
  try {
    if (new URLSearchParams(location.search).get('analytics') === 'debug') session?.setItem(DEBUG_KEY, '1')
  } catch {
    // Storage refused: debug lasts for this page only.
  }
  let debug = false
  try {
    debug = session?.getItem(DEBUG_KEY) === '1' || new URLSearchParams(location.search).get('analytics') === 'debug'
  } catch {
    debug = false
  }
  if (!debug && !ANALYTICS_HOSTS.includes(location.hostname)) return
  mode = debug ? 'debug' : 'live'

  window.dataLayer = window.dataLayer || []
  const off = { ad_storage: 'denied', ad_user_data: 'denied', ad_personalization: 'denied' }
  // By the visitor's IP address, Google's tag waits for consent in these
  // countries even if the time-zone check below let it load.
  gtag('consent', 'default', { ...off, analytics_storage: 'denied', region: CONSENT_REGIONS })
  gtag('consent', 'default', { ...off, analytics_storage: 'granted' })
  gtag('set', 'ads_data_redaction', true)
  gtag('set', { allow_google_signals: false, allow_ad_personalization_signals: false })

  let timeZone = ''
  try {
    timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone ?? ''
  } catch {
    timeZone = ''
  }
  const choice = readChoice()
  const globalPrivacyControl = (navigator as Navigator & { globalPrivacyControl?: boolean }).globalPrivacyControl === true
  const { load, ask } = decide({ choice, timeZone, globalPrivacyControl })

  offByPrivacyControl.value = !load && !ask && choice === null
  analyticsStatus.value = load ? 'on' : ask ? 'ask' : 'off'
  bannerOpen.value = ask
  if (choice === 'granted') gtag('consent', 'update', { analytics_storage: 'granted' })
  if (load) loadTag()

  document.addEventListener('click', onClick, true)
  document.addEventListener('auxclick', onClick, true)
  document.addEventListener('input', onInput, true)

  // Google's tag counts the first page itself. For the pages after it,
  // VitePress changes the address before the title, so its own history
  // tracking would file each page under the previous page's title; this
  // sends them once the new title is in place instead.
  const previous = router.onAfterRouteChange ?? router.onAfterRouteChanged
  let first = true
  let lastUrl = location.href
  router.onAfterRouteChange = async (to: string) => {
    await previous?.(to)
    if (first) {
      first = false
      lastUrl = location.href
      return
    }
    await nextTick()
    if (location.href === lastUrl) return
    track('page_view', { page_location: location.href, page_title: document.title, page_referrer: lastUrl })
    lastUrl = location.href
  }
}
