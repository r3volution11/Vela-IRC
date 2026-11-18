---
title: Supported media sites
description: Every site whose links Vela plays or shows inline (YouTube, Vimeo, Twitch, Streamable, Tenor, GIPHY, Imgur, Reddit, GitHub and image and video files), the links it recognizes and what it fetches.
---

# Supported media sites

Vela recognizes links to these sites and shows what's behind them right in the conversation: a video you can play, a GIF, an image, or a preview built from the site's own information. Any other link gets an ordinary [link preview](/guide/inline-media#link-previews) with the page's title, description and image.

For each site you'll find:

- **Links:** the kinds of link Vela recognizes. `<id>` and the like stand for the part that changes from link to link.
- **Vela shows:** what appears in the conversation, and what Vela fetches to build it.
- **Site rule:** the domain to write a [site rule](/guide/inline-media#site-rules) for. One rule covers all of the site's domains listed with it.
- **Privacy:** what Vela contacts, and when. See [what Vela fetches](/guide/inline-media#what-vela-fetches-and-what-that-means-for-privacy) for the general picture.

::: info Always current
This list is generated from Vela's source code. Real links to every site on it are checked against the sites themselves every week and before each release, so if a site changes how it works, we find out.
:::

Missing a site you use? [Open an issue on GitHub](https://github.com/r3volution11/Vela-IRC/issues/new/choose) with an example link.

<!-- BEGIN MEDIA SITES -->
<!-- Generated from Packages/VelaKit/Sources/VelaMedia/MediaSites.swift by `vela-media-tool docs`. Don't edit by hand. -->

## Videos

Links to these sites show the video's title and thumbnail. Press **▶** to play it right there. **Settings → Media → Videos** chooses a full player, a compact one or a plain link preview.

| Site | Links | Vela shows | Site rule |
| --- | --- | --- | --- |
| [YouTube](https://www.youtube.com) | `youtube.com/watch?v=<id>` (also on `m.youtube.com` and `music.youtube.com`; a `t=` or `start=` time is kept)<br>`youtu.be/<id>`<br>`youtube.com/shorts/<id>` (in a portrait player)<br>`youtube.com/live/<id>`<br>`youtube.com/embed/<id>`<br>`youtube-nocookie.com/embed/<id>` | The title and thumbnail, then the site's own player when you press ▶. To get it, Vela asks the site's oEmbed service. | `youtube.com`, which also covers `youtu.be` (short links), `youtube-nocookie.com` (the player) and `ytimg.com` (thumbnails) |
| [Vimeo](https://vimeo.com) | `vimeo.com/<id>` (a `#t=` time is kept)<br>`vimeo.com/<id>/<hash>` (unlisted videos)<br>`player.vimeo.com/video/<id>`<br>`vimeo.com/channels/<name>/<id>` (also groups, albums and showcases) | The title and thumbnail, then the site's own player when you press ▶. To get it, Vela asks the site's oEmbed service. | `vimeo.com`, which also covers `vimeocdn.com` (thumbnails) |
| [Twitch](https://www.twitch.tv) | `clips.twitch.tv/<clip>`<br>`twitch.tv/<channel>/clip/<clip>`<br>`twitch.tv/videos/<id>` (past broadcasts and highlights; a `t=` time is kept) | The title and thumbnail, then the site's own player when you press ▶. To get it, Vela reads the page. | `twitch.tv`, which also covers `jtvnw.net` (thumbnails) |
| [Streamable](https://streamable.com) | `streamable.com/<id>`<br>`streamable.com/e/<id>` (also `/o/` and `/s/`) | The title and thumbnail, then the site's own player when you press ▶. To get it, Vela asks the site's oEmbed service. | `streamable.com` |

- **YouTube:** The title and thumbnail come from YouTube's oEmbed service and `ytimg.com`. The player loads from `youtube-nocookie.com`, only when you press ▶.
- **Vimeo:** The title and thumbnail come from Vimeo's oEmbed service and `vimeocdn.com`. The player loads only when you press ▶.
- **Twitch:** Twitch has no public oEmbed service, so Vela reads the clip's or video's page for its title and thumbnail (from `jtvnw.net`). The player loads only when you press ▶.
- **Streamable:** The title and thumbnail come from Streamable's oEmbed service. The player loads only when you press ▶.

## GIFs

Links to these sites play the GIF inline, even when the link is to the GIF's page. GIFs follow the image settings in **Settings → Media → Images**.

| Site | Links | Vela shows | Site rule |
| --- | --- | --- | --- |
| [Tenor](https://tenor.com) | `tenor.com/view/<title>-gif-<id>` (also with a language, as in `tenor.com/de/view/…`): reads the page<br>`tenor.com/view/<title>-sticker-<id>`: reads the page<br>`tenor.com/<code>.gif`: follows the link, then reads the page<br>`media.tenor.com/<id>/<name>.gif` (also `.mp4` and `.webp`, and on `media1.tenor.com` and `c.tenor.com`): nothing else to fetch | The GIF, played from its small video copy. Stickers, from their see-through animated image. | `tenor.com`, which also covers `media.tenor.com` (the GIFs and their video copies) |
| [GIPHY](https://giphy.com) | `giphy.com/gifs/<title>-<id>` (the page is read only for a text-only preview): nothing else to fetch<br>`giphy.com/embed/<id>`: nothing else to fetch<br>`giphy.com/stickers/<title>-<id>`: nothing else to fetch<br>`gph.is/<code>`: follows the link, then reads the page<br>`media.giphy.com/media/<id>/giphy.gif` (also `.mp4` and `.webp`, and on `media0.giphy.com` to `media4.giphy.com`): nothing else to fetch<br>`i.giphy.com/<id>.gif`: nothing else to fetch | The GIF, played from its small video copy. Stickers, from their see-through animated image. | `giphy.com`, which also covers `gph.is` (short links) |
| [Imgur](https://imgur.com) | `i.imgur.com/<id>.gifv` (also on `imgur.com`; other Imgur images, such as `i.imgur.com/<id>.jpg`, show like any image file) | The GIF, played from its small video copy. The link names the file, so Vela fetches nothing else. | Each domain's own: `i.imgur.com` (links and the video copies) and `imgur.com` (links) |

- **Tenor:** A link to a GIF file needs no page: Vela loads only the GIF's video copy from `media.tenor.com`. Pages and short links are fetched to find the GIF.
- **GIPHY:** Links that name the GIF (pages, embeds and files) need no page: Vela loads only the GIF's video copy from GIPHY's servers. `gph.is` short links are followed to find the GIF.
- **Imgur:** Vela loads the GIF's video copy (`i.imgur.com/<id>.mp4`) and never the `.gifv` page.

## Reddit

Reddit videos play in Vela's own player, and links to posts get a preview with the post's title, subreddit and author.

| Site | Links | Vela shows | Site rule |
| --- | --- | --- | --- |
| [Reddit videos](https://www.reddit.com) | `v.redd.it/<id>` (a video without sound loops like a GIF)<br>`reddit.com/video/<id>` | The title, subreddit and author, then Vela's own player when you press ▶. No picture shows before that. To get it, Vela follows the link, asks the site's oEmbed service, then reads the video's playlist. | `reddit.com`, which also covers `redd.it` (videos on `v.redd.it`) and `redditstatic.com` (Reddit's icon) |
| [Reddit posts](https://www.reddit.com) | `reddit.com/r/<subreddit>/comments/<id>/<title>`: asks the site's oEmbed service<br>`reddit.com/comments/<id>`: asks the site's oEmbed service<br>`reddit.com/user/<name>/comments/<id>`: asks the site's oEmbed service<br>`redd.it/<id>`: follows the link, then asks the site's oEmbed service<br>`reddit.com/r/<subreddit>/s/<code>` (what Reddit's Share button makes): follows the link, then asks the site's oEmbed service | A link preview with the post's title, subreddit and author. | `reddit.com`, which also covers `redd.it` (short links) and `redditstatic.com` (Reddit's icon) |
| [Reddit images](https://www.reddit.com) | `i.redd.it/<name>.jpg` (and other image files)<br>`preview.redd.it/<name>.jpg?…` | The image. GIF, APNG and WebP animate. The link names the file, so Vela fetches nothing else. | `reddit.com`, which also covers `redd.it` (images on `i.redd.it` and `preview.redd.it`) and `redditmedia.com` (older image servers) |

- **Reddit videos:** Vela follows the link to its post, reads the post's oEmbed for the title and author, and the video's playlist for its shape and sound. None of that says whether a post is NSFW, so no picture shows until you press ▶, and Reddit videos never play by themselves.
- **Reddit posts:** Reddit answers apps with a challenge page instead of the post, so Vela reads only Reddit's public oEmbed for the title and author. Short and share links are followed to the post first.
- **Reddit images:** Images load straight from Reddit's image servers, like any other image.

## Image and video files

A link to an image or video file on any site shows the file itself.

| Site | Links | Vela shows | Site rule |
| --- | --- | --- | --- |
| [GitHub](https://github.com) | `github.com/<owner>/<repo>/blob/<branch>/<path>.png` (image and video files; Vela loads the raw file) | The image. GIF, APNG and WebP animate. The link names the file, so Vela fetches nothing else. | Each domain's own: `github.com` (links) and `raw.githubusercontent.com` (the files) |
| Image and video files | `<any site>/<name>.jpg` (or `.apng`, `.avif`, `.bmp`, `.gif`, `.heic`, `.heif`, `.jpeg`, `.png`, `.tif`, `.tiff` or `.webp`): nothing else to fetch<br>`<any site>/<name>.mp4` (or `.m4v` or `.mov`): checks the file's type and size | The image. GIF, APNG and WebP animate. A still frame; the video plays when you click it. | The file's own site |

- **GitHub:** Vela loads the file from `raw.githubusercontent.com`, never the `github.com` page. A rule for either domain applies.
- **Image and video files:** Images load from the link's own site, up to your size limit. For a video file, Vela checks its type and size first and reads only enough for a still frame; the rest streams when you play it.

<!-- END MEDIA SITES -->
