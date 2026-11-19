// Shared with the browser bundle (seo.mts holds the same values for the
// build, where it also reads files).
export const REPO_URL = 'https://github.com/r3volution11/Vela-IRC'
/** The release workflow publishes a stable asset with exactly this name. */
export const DOWNLOAD_URL = `${REPO_URL}/releases/latest/download/Vela.dmg`
export const RELEASES_URL = `${REPO_URL}/releases`

// velairc.app's Google tag and the Google Analytics property it sends to.
// Only the website uses them: the Vela app has no analytics at all.
export const GOOGLE_TAG_ID = 'GTM-NW39HSC7'
export const GA_MEASUREMENT_ID = 'G-5N9PPPQBPR'
/** The only hosts that load the tag; local previews and forks never do. */
export const ANALYTICS_HOSTS = ['velairc.app', 'www.velairc.app']
