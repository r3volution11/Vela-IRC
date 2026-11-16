// A markdown-it plugin for content included from the repository root, such
// as CHANGELOG.md (<!--@include: ../CHANGELOG.md-->). Its relative links
// ("ROADMAP.md", "docs/THEMES.md") are written for GitHub, so on the site
// they would point at pages that don't exist and fail the dead-link check.
//
// A relative link that doesn't resolve inside the website but does resolve
// from the repository root goes to the matching site page when there is one,
// and to the file on GitHub otherwise.

import { existsSync } from 'node:fs'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'
import type MarkdownIt from 'markdown-it'

const website = join(dirname(fileURLToPath(import.meta.url)), '..')
const repo = join(website, '..')
const GITHUB_BLOB = 'https://github.com/r3volution11/Vela-IRC/blob/main/'

/** Repository files that have a page of their own on the site. */
const sitePages: Record<string, string> = {
  'CHANGELOG.md': '/changelog',
  'docs/THEMES.md': '/customize/creating-themes',
  'docs/THEME-CREDITS.md': '/help/license#theme-credits',
  'THIRD_PARTY_NOTICES.md': '/help/license',
}

export function repoLinks(md: MarkdownIt) {
  md.core.ruler.after('inline', 'vela-repo-links', (state) => {
    const pagePath: string | undefined = (state.env as { relativePath?: string }).relativePath
    if (!pagePath) return
    const pageDir = dirname(join(website, pagePath))

    for (const block of state.tokens) {
      for (const token of block.children ?? []) {
        if (token.type !== 'link_open') continue
        const href = token.attrGet('href')
        if (!href || /^([a-z][a-z0-9+.-]*:|\/|#)/i.test(href)) continue

        const [path, hash = ''] = href.split('#')
        const decoded = decodeURIComponent(path)
        if (existsSync(join(pageDir, decoded)) || existsSync(join(pageDir, `${decoded}.md`))) continue
        if (!existsSync(join(repo, decoded))) continue

        const repoPath = relative(repo, join(repo, decoded))
        const target = sitePages[repoPath] ?? `${GITHUB_BLOB}${repoPath}`
        token.attrSet('href', hash ? `${target}${target.includes('#') ? '' : `#${hash}`}` : target)
      }
    }
  })
}
