---
title: Inline media & privacy
description: How Vela shows images, GIFs, link previews and videos inline, what it fetches and from where, and how to limit it with site rules, the adult-site filter and blur.
---

# Inline media & privacy

When someone posts a link, Vela can show what's behind it right in the conversation: images and GIFs, a preview with the page's title and description, or a video you can play in place. Up to four links per message get a preview.

## What you'll see

- **Images** (JPEG, PNG, WebP and others) appear inline. Animated **GIF, APNG and WebP** play inline; with **Reduce Motion** turned on in macOS, they show the first frame and a play button. Click an image to open it full size (<kbd>Esc</kbd> closes it). Right-click to open it in your browser or copy it.
- **Link previews** show a page's site name and icon, title, description and image, in [three sizes](#link-previews).
- **GIFs from Tenor, GIPHY and Imgur** play inline too, even when the link is to the GIF's page rather than the GIF itself. See [GIFs](#gifs).
- **YouTube, Vimeo, Twitch, Streamable and Reddit** video links show the video's title, and (except on [Reddit](#reddit)) its thumbnail. Press **▶** to [play it right there](#videos).
- **Video files** (`.mp4`, `.mov`) show a still frame. They never play until you click.

[Supported media sites](/reference/media-sites) lists every site Vela knows, the links it recognizes on each, and what it fetches from them.

Hover a message's previews and click the chevron to hide them, or right-click a preview and choose **Hide Previews**.

The settings below are in **Settings → Media**, and most are in the [command palette](/guide/command-palette) too (type "media"). [Presets](/guide/presets) choose link, video and image sizes for you.

## Link previews

<Screenshot src="/screenshots/media-link-standard.webp" alt="A Standard link preview: the site, the title and two lines of description beside a thumbnail" caption="Standard link previews, the default." />

Pick how much a link preview shows in **Settings → Media → Link previews**:

| Size | What it shows |
| --- | --- |
| **Minimal** | One line: the site, the title and a tiny thumbnail. |
| **Standard** (default) | The title and two lines of description beside a thumbnail. In a narrow window the thumbnail drops out rather than squeezing the text. |
| **Large** | A full card with a longer description and a large image underneath, like [Discord](https://discord.com) or [Slack](https://slack.com). |

<Screenshot src="/screenshots/media-link-large.webp" alt="A Large link preview: a full card with the page's image underneath" caption="Large link previews." />

<Screenshot src="/screenshots/media-compact.webp" alt="Minimal link previews: one line per link, with a small thumbnail" caption="Minimal link previews: one line per link." />

**Click anywhere on a preview** to open the page in your browser. To copy part of it instead, select its text as you would in a message: drag across the title, the description or the site name, double-click a word or triple-click a line, then press <kbd>⌘C</kbd> or right-click the selection and choose **Copy**. Dragging never opens the page. Right-click anywhere else on the preview to open or copy the link, or for its [site rules](#from-a-preview).

Turn off **Show link previews** to show web pages as plain links. Images and videos have settings of their own.

From the command palette: **Media: Minimal Link Previews**, **Standard Link Previews**, **Large Link Previews** and **Toggle Link Previews**.

### Sites that need a browser {#sites-that-need-a-browser}

Some sites, such as [IMDb](/reference/media-sites#link-previews-behind-bot-checks), answer apps with a bot check instead of the page: a "Just a moment…" page, or an empty one that only fills in with JavaScript. A plain request finds nothing to preview there. So for those sites, and only those, Vela loads the page once more in a private Safari engine (WebKit) session, out of sight, and builds the preview from what it finds:

- **The site's own check runs**, as it would in Safari, and then Vela reads the page's title, description and image address. The session is thrown away right after: no cookies, cache or storage are kept, and none are shared with Safari or anything else.
- **Only what the check needs loads:** the page, its scripts and the check's own servers. Images, video, fonts, style sheets and requests to other sites (ads and analytics, for example) are blocked, and so is your local network. Vela stops the page as soon as its title and description are in. The preview's image then loads like any other, under your image settings and [site rules](#site-rules).
- **Nothing appears or opens.** The page is never shown, and it can't open windows, start downloads, play sound or ask for your camera or microphone. Nothing is handed to your browser.
- **Honest.** The site sees WebKit, Safari's engine, because that's what loads the page. Vela never pretends to be another app and never answers a check itself.
- **A second or two, once.** It happens only for sites that need it, one page at a time, and the preview is saved like any other, so the page isn't loaded again. On IMDb it takes a second or so and moves about 0.7 MB, mostly the check's own script and the page itself; without the blocking it would be nearly 2 MB.
- **When it doesn't work.** If a check doesn't let the engine through, the link keeps a plain preview with just the site's name (or none), and Vela doesn't try that link again until it restarts.
- **Never where your settings say no:** blocked sites, adult sites, your local network, or a link waiting for you to click **Load preview**. Sites set to **Text only** work as usual, since only text is read.

Turn it off with **Load previews from sites that need a browser** in **Settings → Media → Loading** ([`media.browserFallback`](/reference/settings#media.browserFallback)). Those sites then show just their name. Right-click a preview that was loaded this way to see **Preview Loaded with Safari's Engine** at the bottom of the menu.

## Videos

Choose how YouTube, Vimeo, Twitch, Streamable and Reddit links and video files show in **Settings → Media → Videos**:

| Style | What it shows |
| --- | --- |
| **Player** (default) | The title and a large thumbnail with **▶**. Press it and the video plays in its place. |
| **Compact** | One line with **▶**. The player opens underneath when you press it, or click anywhere on the line. |
| **Off** | No player: the link gets an ordinary link preview, or stays a plain link if link previews are off. |

<Screenshot src="/screenshots/media-videos-compact.webp" alt="Compact videos: one line per video with a play button" caption="Compact videos: the player opens underneath when you press ▶." />

Click a video's title, or the line above it, to open the video on its site. You can select and copy that text like a link preview's: dragging across it never opens or plays anything.

The video site's player loads only when you press **▶**. See [what Vela fetches](#what-vela-fetches-and-what-that-means-for-privacy) for what happens before that.

From the command palette: **Media: Play Videos Inline**, **Compact Videos** and **Videos as Links**.

### Watching a video

- **Expand** a playing video with the button in its top-right corner, or right-click it and choose **Expand Video**. It fills the Vela window and keeps playing. Press <kbd>Esc</kbd>, click outside the video or click **Return** to put it back in the conversation.
- **Full screen** still works: the player's own full-screen button uses macOS full screen.
- **One at a time.** Starting a video pauses any other one that's playing.
- **Out of sight, paused.** A video pauses when you scroll it out of view or switch to another conversation. It stays right where it was; press play to carry on. Closing the window stops every video.
- **×** (or **Stop Video** in the right-click menu) closes the player and brings the thumbnail back.

Vela keeps up to three players loaded. Starting a fourth closes the one you used least recently.

### Reddit

- **Reddit videos** (`v.redd.it` links) play in Vela's own player, with sound, in the same **Player**, **Compact** and **Off** styles as other videos. A Reddit "GIF", which is a video without sound, loops silently once you press **▶** and shows a **GIF** badge.
- **No picture until you press ▶.** Vela can't tell from Reddit's public information whether a post is NSFW, so Reddit videos show no thumbnail or still frame, just the post's title, subreddit and author, and never start by themselves. If Reddit sends Vela to its age check instead of the post, the preview is blocked like any [page marked adult](#adult-sites).
- **Links to Reddit posts** show a link preview with the post's title, subreddit and author. Reddit only lets apps see what a post holds with an account, so a post's video doesn't play from a link to the post; share the video's own `v.redd.it` link for that. Images on `i.redd.it` and `preview.redd.it` show inline like any other image.
- **When Reddit is busy** and asks apps to slow down, the preview shows the title from the link itself, and Vela asks again later.

## Images

In **Settings → Media → Images**:

- **Size.** **Full size** shows images inline, up to the **Maximum image height** (320 points by default); taller ones are scaled down. **Thumbnail** keeps them small; click one to see it full size.
- **Largest image to load automatically** (10 MB by default). Bigger images show a placeholder you can click.

Animated images play at the size they're shown, decoded in the background so scrolling stays smooth. One larger than 16 megapixels, however small its file, shows a chip that opens it in your browser instead.

GIFs follow these settings too.

From the command palette: **Media: Full-Size Images** and **Image Thumbnails**.

## GIFs

<Screenshot src="/screenshots/media-gifs.webp" alt="Two GIFs in a channel: a night rocket launch, captioned “via GIPHY · giphy.com”, and the space station above Earth, captioned “via Tenor · tenor.com”, each with a GIF badge in the corner" caption="GIFs from GIPHY and Tenor play right in the conversation." />

Links to GIFs on these sites play inline, even when the link is to the site's page rather than to the GIF itself:

| Site | Links |
| --- | --- |
| **Tenor** | Pages (`tenor.com/view/…`), short links such as `tenor.com/RaDD.gif`, and GIF files on `media.tenor.com` |
| **GIPHY** | Pages (`giphy.com/gifs/…`, `giphy.com/stickers/…`), `gph.is` short links, and files on `media.giphy.com` and `i.giphy.com` |
| **Imgur** | `.gifv` links |

Any other link to a `.gif`, `.webp` or `.apng` file plays inline as an [image](#images). For every link form, see [Supported media sites](/reference/media-sites#gifs).

- **Small and smooth.** These sites keep a video copy of every GIF, usually a tenth of its size or less, and Vela plays that copy: silent, looping and without controls, just like a GIF. Stickers, which have see-through backgrounds, play from the GIF itself. If the video copy can't be loaded, Vela plays the GIF instead.
- **Sized like images.** GIFs follow the [Images](#images) settings: **Full size**, up to the **Maximum image height**, or **Thumbnail**, which plays while the pointer is over it. A GIF bigger than **Largest image to load automatically** shows a chip that opens it in your browser.
- **Pause and play** with the **GIF** badge in the corner, or by right-clicking the GIF. A GIF starts a moment after it scrolls into view, showing its first frame until then, so scrolling quickly past GIFs stays smooth. GIFs pause while they're scrolled out of view. With **Reduce Motion** turned on in macOS, they show their first frame and a play button.
- **Click a GIF** to see it larger (<kbd>Esc</kbd> closes it). The line underneath, such as **via GIPHY · giphy.com**, says where it's from; click it to open the GIF's page in your browser, or drag across it to select it.
- **Your other settings apply** as they do to images: [blur](#blur), [site rules](#site-rules), the [adult-site filter](#adult-sites), **Load previews automatically** (a **Load GIF** button until you click it) and turning media off for a channel. On a site set to **Text only**, a GIF link gets a link preview with the GIF's title and no animation.

To find the GIF behind a page or a short link, Vela fetches the page, as it does for any [link preview](#what-vela-fetches-and-what-that-means-for-privacy). A link that already says which GIF it is, such as a GIPHY page or a file on Tenor's or GIPHY's servers, needs no page: Vela loads only the GIF.

## What Vela fetches, and what that means for privacy

To build a preview, Vela downloads the linked page or image **from your Mac**. That's how every chat app with link previews works, and it means:

- **The site learns your IP address**, and that someone opened the link at about that time.
- **Vela sends no cookies** and identifies itself honestly as Vela's link previewer. It doesn't run the page's scripts; it reads only the page's title, description and image.
- **Except for sites that need a browser.** When a site answers with a bot check instead of the page, Vela loads it in a private Safari engine session where the page's scripts run, as they would in Safari, then throws the session away. Images, other sites and your local network are blocked there. See [Sites that need a browser](#sites-that-need-a-browser), and turn it off with **Load previews from sites that need a browser**.
- **Video links contact the video site before you press play.** When previews load automatically, Vela fetches the video's title and thumbnail from the video site (from YouTube's, Vimeo's, Streamable's or Reddit's oEmbed service, or from the Twitch page), so that site sees your IP address like any other preview. For a Reddit video, Vela also follows the link to its post and reads the video's playlist, to learn its shape and whether it has sound. The player itself, with its scripts and cookies, loads only when you press **▶**. YouTube plays from `youtube-nocookie.com`, and nothing the player stores is kept after it closes.
- **GIF links contact the GIF site.** Vela fetches a Tenor page or short link (or a `gph.is` link) to find its GIF, then downloads the GIF's video copy from Tenor, GIPHY or Imgur, with the same size limit and [site rules](#site-rules) as images. Downloaded GIFs are kept in a temporary folder that Vela empties each time it starts.
- **Your local network is off-limits.** Vela never fetches previews from `localhost`, private and link-local IP addresses, or names like `router.local`, so a link in a channel can't make Vela probe devices on your network.
- **Previews are cached** on your Mac, so scrolling back doesn't fetch them again. Page previews are refreshed after a week, and cached previews older than 30 days are deleted when Vela starts.

If that's more than you want, the rest of this page shows how to turn previews off, limit them per channel or per site, hide previews of adult sites and blur images.

## Turning previews off {#controlling-media}

### Everywhere

- **Load previews automatically.** Turn this off and Vela fetches nothing until you click a link's **Load preview** button. Also in the command palette: **Media: Load Previews Automatically**.
- **Load previews from sites that need a browser** off keeps Vela from ever running a page's scripts: sites behind a bot check show just their name. See [Sites that need a browser](#sites-that-need-a-browser).
- **Show link previews** off shows web pages as plain links. With **Videos** set to **Off** as well, video links stay plain links too.

### Per channel

Click the **picture icon** in a channel's header, or right-click the channel and choose **Disable Inline Media**. That channel shows plain links from then on. **Settings → Media** counts the channels you've turned off and can turn them all back on.

To turn media off for a whole network, right-click the network in the sidebar (or its tab) and choose **Disable Inline Media on This Network**. Behind the scenes this adds `"<network id>/*"` to [`media.disabledBuffers`](/reference/settings#media.disabledBuffers) in settings.json.

## Hiding adult sites {#adult-sites}

**Hide previews of adult sites** (in **Settings → Media → Restrictions**) is on by default. Links to adult sites stay clickable, but Vela doesn't preview them: it fetches no page, image, thumbnail or player from the site. A quiet chip says why instead.

<Screenshot src="/screenshots/media-restrictions.webp" alt="Blocked previews: chips reading “Adult site · preview blocked” and “Blocked site”, each with Show once and a second button, above a link preview whose thumbnail is blurred" caption="Blocked previews show a chip saying why." />

### How it works

- **A list that comes with Vela.** Vela checks each link's site, and any site the link redirects to, against a list of about 42,000 adult domains bundled with the app, plus the adult-only `.xxx`, `.porn`, `.adult` and `.sex` domains. A listed domain covers its subdomains too.
- **Checked on your Mac, never online.** Your links aren't sent anywhere to be checked, and Vela never downloads the list. It's refreshed with each new version of Vela.
- **Pages that label themselves adult.** Many adult sites mark their pages with the RTA ("Restricted to Adults") label or a `rating` meta tag. When a page that isn't on the list says so, Vela shows the chip instead of its preview and loads none of its images. (Vela only finds the label by fetching the page, so the site itself is contacted.)
- **Where the list comes from.** It's built from the open-source [Sinfonietta/hostfiles](https://github.com/Sinfonietta/hostfiles) list (MIT license). General platforms such as Reddit, X, Imgur and Tumblr are left out as a whole, although an individual adult blog on one of them may be listed. Reddit videos never show a picture before you press **▶**; see [Reddit](#reddit).

Turn the filter off with the switch, or run **Media: Hide Adult Site Previews** from the command palette.

### When it gets it wrong

- **A site you trust is blocked.** Click **Always allow** on its chip. That gives the site an **Everything** [site rule](#site-rules), and your rules always beat the list. **Show once** shows just that preview without changing your settings.
- **An adult site gets through.** No list is complete. Right-click its preview and choose **Block Previews from ‹site›**, or [blur images](#blur) where that matters.
- **The list is wrong for everyone?** [Open an issue on GitHub](https://github.com/r3volution11/Vela-IRC/issues/new/choose) with the domain.

### Blocked previews

| Chip | Why | Buttons |
| --- | --- | --- |
| **Adult site · preview blocked** | The site is on the adult list. | Show once, Always allow |
| **Page marked adult · preview blocked** | The page labels itself adult. | Show once, Always allow |
| **Blocked site** | You set the site to **Nothing**. | Show once, Unblock |
| **Not on your allowed sites** | [Only listed sites](#only-load-previews-from-listed-sites) get previews, and this one isn't listed. | Show once, Always allow |

- **Show once** shows that one preview and changes nothing else.
- **Always allow** sets the site to **Everything**.
- **Unblock** removes your rule for the site.

Right-click a chip for the same actions, or to open or copy the link. You can also select a chip's text, such as the site's name, and copy it.

## Site rules

Site rules decide what each site may show. Add them in **Settings → Media → Site rules**: type a domain such as `example.com` (or paste a link; Vela keeps just the domain), choose what it may show, and click **Add**.

| Rule | What it means |
| --- | --- |
| **Everything** | Previews, images and players. This also lets the site past the adult-site filter. |
| **Text only** | Titles and descriptions, without any image, thumbnail, site icon or player. Vela fetches the page's text but never loads an image from the site. A video shows as a text-only link preview. |
| **Nothing** | No preview at all. Vela never contacts the site. |

Sites without a rule follow your other settings.

### Which rule applies

- **A rule covers subdomains.** A rule for `example.com` also covers `img.example.com`, but not `badexample.com`.
- **The most specific rule wins.** A rule for `i.example.com` beats one for `example.com`, so you can block a site but allow its image host, or the other way round.
- **Your rules beat the adult list.**
- **Video and GIF sites follow their main domain.** A rule for `youtube.com` also covers `youtu.be` links and YouTube's thumbnails. The same goes for `vimeo.com`, `twitch.tv` and `streamable.com`, and for `reddit.com`, whose rule also covers `redd.it` links, Reddit videos (`v.redd.it`), its images (`i.redd.it`, `preview.redd.it`) and its other media servers. Likewise `tenor.com` covers `media.tenor.com`, and `giphy.com` covers `gph.is` links and GIPHY's media servers. [Supported media sites](/reference/media-sites) lists the domains each site's rule covers.
- **Rules apply wherever a site turns up:** a link to it, a redirect to it, or an image from it in another site's preview.

### From a preview

Right-click any preview for:

- **Block Previews from ‹site›**, which sets the site to **Nothing**.
- **Previews from ‹site›**, a submenu with **Default**, **Everything**, **Text Only** and **Nothing**. **Default** removes your rule.

The menu offers the site without `www.`, and a video or GIF site's main domain for its links and media. If a rule for a broader domain already covers the link, the menu changes that rule. A new rule applies straight away to every preview from the site, including the ones on screen.

### Only load previews from listed sites

Turn on **Only load previews from sites listed here** to make your rules an allow list: only sites set to **Everything** or **Text only** get previews, and every other link shows a **Not on your allowed sites** chip. If no site is set to either yet, no previews load at all.

### In settings.json

Rules are stored in [`media.siteRules`](/reference/settings#media.siteRules), with `"allow"` for Everything, `"textOnly"` for Text only and `"block"` for Nothing:

```jsonc
"media.siteRules": {
  "example.com": "block",
  "news.example": "textOnly",
  "i.imgur.com": "allow"
}
```

**Only load previews from sites listed here** is [`media.restrictToAllowed`](/reference/settings#media.restrictToAllowed).

## Blur images until clicked {#blur}

Turn on **Blur images until clicked** (in **Settings → Media → Restrictions**) and images, GIFs, link preview images, video thumbnails and video stills stay blurred, with **Click to show**, until you click them. The first click only reveals: it doesn't open the viewer or start the video. To hide something again, right-click it and choose **Blur Again**.

<Screenshot src="/screenshots/media-blur.webp" alt="A photo of the northern lights shown blurred in the chat, with a Click to show label over it" caption="A blurred image waits for a click." />

To blur only some places, right-click a channel or conversation and choose **Blur Images**, or right-click a network and choose **Blur Images on This Network**. **Settings → Media** counts them ("Blurred in 2 channels") and can clear them all.

From the command palette: **Media: Blur Images Until Clicked** (everywhere) and **Buffer: Blur Images** (the conversation you're in).

Blurring hides images on screen, but they're still downloaded: Vela makes the blurred copy from them. To keep a site's images from loading at all, set it to **Text only** or **Nothing** with a [site rule](#site-rules).

The matching settings.json keys are listed under [Media](/reference/settings#media) in the settings reference.
