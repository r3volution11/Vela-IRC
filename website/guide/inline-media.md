---
title: Inline media & privacy
description: How Vela shows images, link previews and videos inline, what it fetches and from where, and how to limit it with site rules, the adult-site filter and blur.
---

# Inline media & privacy

When someone posts a link, Vela can show what's behind it right in the conversation: images and GIFs, a preview with the page's title and description, or a video you can play in place. Up to four links per message get a preview.

## What you'll see

- **Images** (JPEG, PNG, WebP and others) appear inline. Animated **GIF, APNG and WebP** play inline; with **Reduce Motion** turned on in macOS, they show the first frame and a play button. Click an image to open it full size (<kbd>Esc</kbd> closes it). Right-click to open it in your browser or copy it.
- **Link previews** show a page's site name and icon, title, description and image, in [three sizes](#link-previews).
- **YouTube, Vimeo, Twitch and Streamable** links show the video's title and thumbnail. Press **▶** to [play it right there](#videos).
- **Video files** (`.mp4`, `.mov`, Imgur `.gifv`) show a still frame. They never play until you click.

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

Turn off **Show link previews** to show web pages as plain links. Images and videos have settings of their own.

From the command palette: **Media: Minimal Link Previews**, **Standard Link Previews**, **Large Link Previews** and **Toggle Link Previews**.

## Videos

Choose how YouTube, Vimeo, Twitch and Streamable links and video files show in **Settings → Media → Videos**:

| Style | What it shows |
| --- | --- |
| **Player** (default) | The title and a large thumbnail with **▶**. Press it and the video plays in its place. |
| **Compact** | One line with **▶**. The player opens underneath when you press it. |
| **Off** | No player: the link gets an ordinary link preview, or stays a plain link if link previews are off. |

<Screenshot src="/screenshots/media-videos-compact.webp" alt="Compact videos: one line per video with a play button" caption="Compact videos: the player opens underneath when you press ▶." />

The video site's player loads only when you press **▶**. See [what Vela fetches](#what-vela-fetches-and-what-that-means-for-privacy) for what happens before that.

From the command palette: **Media: Play Videos Inline**, **Compact Videos** and **Videos as Links**.

### Watching a video

- **Expand** a playing video with the button in its top-right corner, or right-click it and choose **Expand Video**. It fills the Vela window and keeps playing. Press <kbd>Esc</kbd>, click outside the video or click **Return** to put it back in the conversation.
- **Full screen** still works: the player's own full-screen button uses macOS full screen.
- **One at a time.** Starting a video pauses any other one that's playing.
- **Out of sight, paused.** A video pauses when you scroll it out of view or switch to another conversation. It stays right where it was; press play to carry on. Closing the window stops every video.
- **×** (or **Stop Video** in the right-click menu) closes the player and brings the thumbnail back.

Vela keeps up to three players loaded. Starting a fourth closes the one you used least recently.

## Images

In **Settings → Media → Images**:

- **Size.** **Full size** shows images inline, up to the **Maximum image height** (320 points by default); taller ones are scaled down. **Thumbnail** keeps them small; click one to see it full size.
- **Largest image to load automatically** (10 MB by default). Bigger images show a placeholder you can click.

From the command palette: **Media: Full-Size Images** and **Image Thumbnails**.

## What Vela fetches, and what that means for privacy

To build a preview, Vela downloads the linked page or image **from your Mac**. That's how every chat app with link previews works, and it means:

- **The site learns your IP address**, and that someone opened the link at about that time.
- **Vela sends no cookies** and identifies itself honestly as Vela's link previewer. It never runs the page's scripts; it reads only the page's title, description and image.
- **Video links contact the video site before you press play.** When previews load automatically, Vela fetches the video's title and thumbnail from the video site (from YouTube's, Vimeo's or Streamable's oEmbed service, or from the Twitch page), so that site sees your IP address like any other preview. The player itself, with its scripts and cookies, loads only when you press **▶**. YouTube plays from `youtube-nocookie.com`, and nothing the player stores is kept after it closes.
- **Your local network is off-limits.** Vela never fetches previews from `localhost`, private and link-local IP addresses, or names like `router.local`, so a link in a channel can't make Vela probe devices on your network.
- **Previews are cached** on your Mac, so scrolling back doesn't fetch them again. Page previews are refreshed after a week, and cached previews older than 30 days are deleted when Vela starts.

If that's more than you want, the rest of this page shows how to turn previews off, limit them per channel or per site, hide previews of adult sites and blur images.

## Turning previews off {#controlling-media}

### Everywhere

- **Load previews automatically.** Turn this off and Vela fetches nothing until you click a link's **Load preview** button. Also in the command palette: **Media: Load Previews Automatically**.
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
- **Where the list comes from.** It's built from the open-source [Sinfonietta/hostfiles](https://github.com/Sinfonietta/hostfiles) list (MIT license). General platforms such as Reddit, X, Imgur and Tumblr are left out as a whole, although an individual adult blog on one of them may be listed.

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

Right-click a chip for the same actions, or to open or copy the link.

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
- **Video sites follow their main domain.** A rule for `youtube.com` also covers `youtu.be` links and YouTube's thumbnails. The same goes for `vimeo.com`, `twitch.tv` and `streamable.com`.
- **Rules apply wherever a site turns up:** a link to it, a redirect to it, or an image from it in another site's preview.

### From a preview

Right-click any preview for:

- **Block Previews from ‹site›**, which sets the site to **Nothing**.
- **Previews from ‹site›**, a submenu with **Default**, **Everything**, **Text Only** and **Nothing**. **Default** removes your rule.

The menu offers the site without `www.`, and a video site's main domain for videos. If a rule for a broader domain already covers the link, the menu changes that rule. A new rule applies straight away to every preview from the site, including the ones on screen.

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

::: info Upgrading from Vela 0.1
The **Blocked domains** and **Allowed domains** lists became site rules automatically: blocked domains are set to **Nothing** and allowed domains to **Everything**. Allowed domains now also get past the adult-site filter.
:::

## Blur images until clicked {#blur}

Turn on **Blur images until clicked** (in **Settings → Media → Restrictions**) and images, link preview images, video thumbnails and video stills stay blurred, with **Click to show**, until you click them. The first click only reveals: it doesn't open the viewer or start the video. To hide something again, right-click it and choose **Blur Again**.

<Screenshot src="/screenshots/media-blur.webp" alt="A photo of the northern lights shown blurred in the chat, with a Click to show label over it" caption="A blurred image waits for a click." />

To blur only some places, right-click a channel or conversation and choose **Blur Images**, or right-click a network and choose **Blur Images on This Network**. **Settings → Media** counts them ("Blurred in 2 channels") and can clear them all.

From the command palette: **Media: Blur Images Until Clicked** (everywhere) and **Buffer: Blur Images** (the conversation you're in).

Blurring hides images on screen, but they're still downloaded: Vela makes the blurred copy from them. To keep a site's images from loading at all, set it to **Text only** or **Nothing** with a [site rule](#site-rules).

The matching settings.json keys are listed under [Media](/reference/settings#media) in the settings reference.
