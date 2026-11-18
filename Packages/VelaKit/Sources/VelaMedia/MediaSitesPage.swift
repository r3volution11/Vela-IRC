// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The generated part of the website's "Supported media sites" page
/// (`website/reference/media-sites.md`), from `MediaSites.all`.
///
/// The page is committed: the website is built where Swift doesn't run.
/// `vela-media-tool docs --write <page>` rewrites the part between the
/// markers, and `MediaSitesTests` fails when it's stale.
public enum MediaSitesPage {
    public static let pagePath = "website/reference/media-sites.md"
    public static let command = "swift run --package-path Packages/VelaKit vela-media-tool docs --write \(pagePath)"
    public static let beginMarker = "<!-- BEGIN MEDIA SITES -->"
    public static let endMarker = "<!-- END MEDIA SITES -->"

    public enum PageError: Error, CustomStringConvertible {
        case missingMarkers

        public var description: String {
            "The page needs a line \(MediaSitesPage.beginMarker) and, after it, a line \(MediaSitesPage.endMarker)."
        }
    }

    /// The generated block, markers included, ending with a newline.
    public static func markdown(_ sites: [MediaSite] = MediaSites.all) -> String {
        var lines = [
            beginMarker,
            "<!-- Generated from Packages/VelaKit/Sources/VelaMedia/MediaSites.swift by `vela-media-tool docs`. Don't edit by hand. -->",
            "",
        ]
        for category in MediaSite.Category.allCases {
            let members = sites.filter { $0.category == category }
            guard !members.isEmpty else { continue }
            lines += ["## \(category.heading)", "", category.introduction, ""]
            lines += ["| Site | Links | Vela shows | Site rule |", "| --- | --- | --- | --- |"]
            lines += members.map(row)
            lines.append("")
            lines += members.map { "- **\($0.name):** \($0.privacy)" }
            lines.append("")
        }
        lines.append(endMarker)
        return lines.joined(separator: "\n") + "\n"
    }

    /// `page` with everything from its begin marker to its end marker
    /// replaced by `markdown(sites)`.
    public static func updating(_ page: String, with sites: [MediaSite] = MediaSites.all) throws -> String {
        guard let begin = page.range(of: beginMarker),
              let end = page.range(of: endMarker, range: begin.upperBound..<page.endIndex)
        else { throw PageError.missingMarkers }
        var lineEnd = end.upperBound
        if lineEnd < page.endIndex, page[lineEnd] == "\n" { lineEnd = page.index(after: lineEnd) }
        return page.replacingCharacters(in: begin.lowerBound..<lineEnd, with: markdown(sites))
    }

    // MARK: - Rows

    private static func row(_ site: MediaSite) -> String {
        let name = site.homepage.map { "[\(site.name)](\($0))" } ?? site.name
        let sharedSteps = Set(site.forms.map(\.steps)).count == 1 ? site.forms.first?.steps : nil

        let links = site.forms.map { form in
            var line = "`\(form.pattern)`"
            if let note = form.note { line += " (\(note))" }
            if sharedSteps == nil { line += ": " + phrase(form.steps) }
            return line
        }

        var shows = orderedUnique(site.forms.map(\.shows)).map(\.summary).joined(separator: " ")
        if let sharedSteps {
            shows += sharedSteps.isEmpty ? " The link names the file, so Vela fetches nothing else." : " To get it, Vela \(phrase(sharedSteps))."
        }

        let rule: String
        if let ruleDomain = site.ruleDomain {
            let others = site.domains.filter { $0.name != ruleDomain }
            rule = "`\(ruleDomain)`" + (others.isEmpty ? "" : ", which also covers " + list(others.map(describe)))
        } else if site.domains.isEmpty {
            rule = "The file's own site"
        } else {
            rule = "Each domain's own: " + list(site.domains.map(describe))
        }
        return "| " + [name, links.joined(separator: "<br>"), shows, rule].map(cell).joined(separator: " | ") + " |"
    }

    private static func describe(_ domain: MediaSite.Domain) -> String {
        "`\(domain.name)` (\(domain.purpose))"
    }

    /// What Vela fetches, as a phrase: "follows the link, then reads the page".
    private static func phrase(_ steps: [MediaSite.Step]) -> String {
        steps.isEmpty ? "nothing else to fetch" : list(steps.map(\.phrase), lastSeparator: ", then ")
    }

    private static func list(_ items: [String], lastSeparator: String = " and ") -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + lastSeparator + items[items.count - 1]
        }
    }

    private static func orderedUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }

    /// Text for a table cell: no pipes or line breaks to break the row.
    private static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}

extension MediaSite.Category {
    var heading: String {
        switch self {
        case .videos: "Videos"
        case .gifs: "GIFs"
        case .reddit: "Reddit"
        case .files: "Image and video files"
        }
    }

    var introduction: String {
        switch self {
        case .videos:
            "Links to these sites show the video's title and thumbnail. Press **▶** to play it right there. **Settings → Media → Videos** chooses a full player, a compact one or a plain link preview."
        case .gifs:
            "Links to these sites play the GIF inline, even when the link is to the GIF's page. GIFs follow the image settings in **Settings → Media → Images**."
        case .reddit:
            "Reddit videos play in Vela's own player, and links to posts get a preview with the post's title, subreddit and author."
        case .files:
            "A link to an image or video file on any site shows the file itself."
        }
    }
}

extension MediaSite.Presentation {
    /// A sentence for the docs.
    var summary: String {
        switch self {
        case .videoPlayer: "The title and thumbnail, then the site's own player when you press ▶."
        case .nativePlayer: "The title, subreddit and author, then Vela's own player when you press ▶. No picture shows before that."
        case .gif: "The GIF, played from its small video copy."
        case .sticker: "Stickers, from their see-through animated image."
        case .image: "The image. GIF, APNG and WebP animate."
        case .videoFile: "A still frame; the video plays when you click it."
        case .linkPreview: "A link preview with the post's title, subreddit and author."
        }
    }
}

extension MediaSite.Step {
    /// A phrase for the docs: "follows the link".
    var phrase: String {
        switch self {
        case .headRequest: "checks the file's type and size"
        case .redirect: "follows the link"
        case .oEmbed: "asks the site's oEmbed service"
        case .pageMetadata: "reads the page"
        case .hlsPlaylist: "reads the video's playlist"
        }
    }
}
