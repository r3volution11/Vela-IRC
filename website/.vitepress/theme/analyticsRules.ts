// The decisions behind the site's analytics, kept free of the DOM and of
// VitePress so scripts/analytics.test.ts can check them with plain Node.
// analytics.ts does the wiring.

/** A visitor's stored choice, or none yet. */
export type Choice = 'granted' | 'denied' | null

/**
 * Countries where analytics waits for consent: the EU, the rest of the EEA,
 * the UK and Switzerland. Google's tag uses this list for its own consent
 * default, by the visitor's IP address.
 */
export const CONSENT_REGIONS = [
  'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', 'HU', 'IE',
  'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE',
  'IS', 'LI', 'NO',
  'GB', 'CH',
]

/**
 * Whether to ask before measuring, judged from the browser's time zone (a
 * static site can't see the visitor's country). Every Europe/ zone counts,
 * plus the Atlantic and Arctic zones of EEA countries and Spain's Ceuta.
 * Asking someone in Istanbul or Kyiv as well does no harm.
 */
export function asksForConsent(timeZone: string): boolean {
  return /^(Europe\/|Atlantic\/(Reykjavik|Canary|Madeira|Azores|Faroe)$|Africa\/Ceuta$|Arctic\/Longyearbyen$)/.test(timeZone)
}

/** Whether the analytics tag may load, and whether the banner should ask. */
export function decide(input: {
  choice: Choice
  timeZone: string
  globalPrivacyControl: boolean
}): { load: boolean; ask: boolean } {
  if (input.choice === 'granted') return { load: true, ask: false }
  if (input.choice === 'denied') return { load: false, ask: false }
  // Global Privacy Control is a standing "no": don't load, don't nag.
  if (input.globalPrivacyControl) return { load: false, ask: false }
  if (asksForConsent(input.timeZone)) return { load: false, ask: true }
  return { load: true, ask: false }
}

/** Where on the page a link sits, from the classes of its ancestors. */
export const PLACEMENTS: [selector: string, placement: string][] = [
  ['.nav-download', 'nav_download'],
  ['.VPNavScreen', 'mobile_menu'],
  ['.VPSocialLinks', 'social_links'],
  ['.VPNavBar', 'nav'],
  ['.VPHero, .VPHomeHero', 'hero'],
  ['.home-cta', 'home_cta'],
  ['.download-card', 'download_card'],
  ['.edit-link, .VPDocFooter', 'doc_footer'],
  ['.VPFooter', 'footer'],
  ['.VPSidebar', 'sidebar'],
  ['.vp-doc', 'content'],
]

const REPO_PATH = '/r3volution11/vela-irc'

export type LinkEvent =
  | { name: 'vela_download'; params: { file_name: string } }
  | { name: 'github_repo_click'; params: { link_type: string } }

/**
 * The event for a click on this link, if it's one we count: a Vela download,
 * or any other link into Vela's GitHub repository. Other outbound links are
 * left to Google's own outbound-click measurement.
 */
export function eventForLink(href: string, base: string): LinkEvent | null {
  let url: URL
  try {
    url = new URL(href, base)
  } catch {
    return null
  }
  if (url.hostname !== 'github.com') return null
  const path = url.pathname.toLowerCase()
  if (path !== REPO_PATH && !path.startsWith(`${REPO_PATH}/`) && path !== `${REPO_PATH}.git`) return null

  const rest = path.slice(REPO_PATH.length)
  if (/^\/releases\/(latest\/)?download\/.+\.dmg$/.test(rest)) {
    return { name: 'vela_download', params: { file_name: url.pathname.split('/').pop() ?? '' } }
  }

  const type =
    rest === '.git' ? 'clone'
    : rest.startsWith('/issues') ? 'issues'
    : rest.startsWith('/discussions') ? 'discussions'
    : rest.startsWith('/releases') ? 'releases'
    : rest.startsWith('/pull') ? 'pull_requests'
    : rest.startsWith('/edit/') ? 'edit_page'
    : rest.startsWith('/blob/') || rest.startsWith('/tree/') ? 'source'
    : 'repository'
  return { name: 'github_repo_click', params: { link_type: type } }
}

/** The language of a code block, from its `language-xxx` class. */
export function codeLanguage(className: string): string {
  return /(?:^|\s)language-([\w+#-]+)/.exec(className)?.[1] ?? 'unknown'
}

/** A search term worth counting: trimmed, at least two characters, capped. */
export function searchTerm(raw: string): string | null {
  const term = raw.trim().replace(/\s+/g, ' ')
  return term.length >= 2 ? term.slice(0, 100) : null
}
