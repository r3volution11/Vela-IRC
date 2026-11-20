---
title: Privacy
description: The Vela app has no telemetry, analytics or accounts. Who Vela talks to, what link previews reveal, how Apple Intelligence and Siri are handled, what's on your Mac, and what this site measures.
---

# Privacy

**The Vela app has no telemetry, no analytics, no crash reporting service and no accounts.** There is no Vela server: the app never phones home, and nobody but you knows how you use it. (This website is a separate matter: see [This website](#this-website).)

## Who Vela talks to

Vela only makes connections for things you've set up or turned on:

| Connection | When | What the other side learns |
| --- | --- | --- |
| **IRC servers and bouncers you add** | While connected, encrypted with TLS by default | What any IRC server sees: your IP address (or your bouncer's), nickname and messages. |
| **Sites behind links people post** | When a [link preview](/guide/inline-media) loads, unless you turn previews off or limit them | Your IP address and that Vela fetched the page. No cookies are sent. |
| **Sites that only show their page to a browser** (IMDb, for example) | When a link preview finds a bot check instead of the page, unless you turn off **Load previews from sites that need a browser** | What a visit in Safari tells them: your IP address, and whatever the page's own check script collects. It runs in a private session that's thrown away afterwards, with images, other sites and your local network blocked. See [Sites that need a browser](/guide/inline-media#sites-that-need-a-browser). |
| **Video providers** (YouTube, Vimeo, Streamable, Twitch) | A video card fetches its title and thumbnail; the player itself loads only when you press play | Your IP address; once you press play, whatever the provider's player collects. YouTube plays from `youtube-nocookie.com`, and the player keeps nothing after it closes. |
| **Apple's Private Cloud Compute** | Only if you turn on **Use Private Cloud Compute for long catch-ups** (macOS 27 or later; it's off by default), for a catch-up too long for one pass on your Mac | Nothing it keeps: the request is encrypted, used only to write the summary, and not stored or readable by Apple. See [Apple Intelligence, translation and Siri](#apple-intelligence). |

Vela never fetches previews from your local network (`localhost`, private IP addresses, `.local` names), so a link in a channel can't make your Mac probe your router or other devices.

**You're in control of previews.** Turn them off, make them click-to-load, disable them per channel, hide adult sites, blur images until clicked, or set rules for individual sites. See [Inline media & privacy](/guide/inline-media#controlling-media).

## Apple Intelligence, translation and Siri {#apple-intelligence}

- **Catch me up and translation run on your Mac.** Summaries come from the Apple Intelligence model on your Mac, and translations from Apple's Translation framework. Your conversations aren't sent to Apple (unless you turn on Private Cloud Compute, below), to Vela's developers or anyone else, and summaries and translations are kept only in memory. See [Apple Intelligence & translation](/guide/apple-intelligence#privacy).
- **Private Cloud Compute is off unless you turn it on.** On macOS 27 or later, **Use Private Cloud Compute for long catch-ups** in **Settings → Apple Intelligence** ([`intelligence.privateCloudCompute`](/reference/settings#intelligence.privateCloudCompute)) sends a catch-up that's too long for one pass on your Mac to Apple's [Private Cloud Compute](https://security.apple.com/blog/private-cloud-compute/): the messages in that stretch with their nicks, and your nick, but not the channel's or the network's name. Apple's guarantees apply: the request is encrypted on the way, used only to write the summary, not stored afterwards, and not readable by Apple. Short catch-ups, translation and everything else stay on your Mac, and Vela still sends nothing to its developers or anyone else.
- **Translation languages come from Apple.** The first time you translate from a language, macOS asks to download it, and downloads it from Apple once.
- **Writing Tools is Apple's.** When you use it, Vela hands it the text in the message field, and Apple Intelligence handles it as it does in any app.
- **Spotlight gets names only:** your channel and conversation names and their networks, never messages. Turn off **Show channels in Spotlight** in **Settings → Apple Intelligence** to remove them from Spotlight's results. On macOS 27, the same names are also kept for Siri, hidden from Spotlight's results, so Siri can find a channel or a nick when you ask it to send a message; the setting doesn't remove those. See [Spotlight](/guide/siri-shortcuts#spotlight).
- **Siri learns where you send messages.** When you send one, Vela tells Siri which channel it went to, so Siri can suggest it later; it never shares the text. What you say to Siri is handled by Siri, under Apple's privacy policy. See [Siri, Shortcuts & Spotlight](/guide/siri-shortcuts#privacy).

## What other IRC users can see

This is how IRC works in any client, but it's worth knowing:

- **Your host or IP address**, unless your network gives you a cloak or you connect through a bouncer.
- **CTCP replies.** Like most IRC clients, Vela answers `VERSION` (with "Vela" and its version), `TIME` (your local time) and `PING` requests automatically.
- **Typing indicators**, on servers that support them. Turn off **Send typing indicators** in **Settings → Messages → Typing** to keep your typing private.

## What's stored on your Mac

Everything stays on your Mac, inside Vela's sandbox container:

- **Message history, only if you turn it on.** **Save message history** in **Settings → Messages → History** is off by default: messages, reactions and link previews are kept in memory while Vela is open, and gone when it quits. A bouncer or server that keeps history fills them in again when you connect. Turned on, they're saved in a local database, kept forever unless you set **Keep messages**. See [Scrollback and history](/guide/messages-and-layouts#scrollback-and-history).
  - If you used Vela before this setting existed, your history is still being saved, as before. Turn it off whenever you like.
  - Turning it off asks whether to delete what's already saved. **Delete Saved History…**, under the setting, deletes it any time.
- **Your channels and where you stopped reading,** saved either way: each channel and conversation you have open, its read position, whether it's muted, its place in the sidebar and whether to rejoin it. That's how unread counts, the **New** line and Catch me up work after a restart. No messages are part of it.
- **Chat logs**, only if you turn them on (they're off by default). They're separate from message history: plain-text copies of your channels and conversations, unencrypted, in Vela's folder or one you choose, that Vela never loads back. Vela never sends them anywhere, but a folder you choose may sync if it's in iCloud Drive or a similar service. See [Chat logs](/guide/chat-logs#privacy).
- **Link previews and images** you've loaded, while message history is saved: page previews in the database, refreshed after a week (cached previews older than 30 days are deleted when Vela starts), and images in Vela's cache folder. With history off, they're kept in memory and loaded again after a restart.
- **Drafts** you haven't sent, in memory while Vela is open.
- **Settings, networks and themes** as plain files you can read.
- **Passwords, channel keys and client certificates** in your macOS Keychain, never in plain files.

Outside the container, macOS keeps your channel and conversation names in Spotlight's index (as search results unless you turn off **Show channels in Spotlight**, and on macOS 27 also hidden from results, for Siri), the translation languages you've downloaded, and the notifications you allow until you clear them from Notification Center.

Vela is sandboxed: it can only reach its own container and files you choose, such as a theme you import or a folder for chat logs. See [where files live](/help/troubleshooting#where-files-live) and [how to remove everything](/guide/install#uninstalling).

## This website {#this-website}

velairc.app is a static site hosted on GitHub Pages. It uses **Google Analytics** to learn which pages help people and how many download Vela. That's the website only: the Vela app never sends anything to Google, or to anyone else.

- **Visitors in the EU, EEA, UK and Switzerland are asked first.** Until you choose **Allow**, Google's code isn't loaded at all. The site judges where you are from your browser's time zone.
- **Elsewhere it's on unless you turn it off** below. If your browser sends [Global Privacy Control](https://globalprivacycontrol.org), that counts as a no, wherever you are.
- **What it counts:** the pages you view, how far you scroll, Vela downloads, links you follow to GitHub and other sites, which kind of code block you copy (its language, not the code), and the words you type into the site's search.
- **What it doesn't do:** no ads, no advertising cookies, no Google signals and no cross-site tracking. Google Analytics doesn't keep your IP address.
- **Cookies:** two first-party cookies from Google Analytics, `_ga` and `_ga_5N9PPPQBPR`, which last up to two years. Turning analytics off deletes them. Your choice itself is kept in your browser's local storage, not in a cookie.
- **Google keeps the data for up to 14 months.** See [how Google uses data from sites that use its services](https://policies.google.com/technologies/partner-sites).

<AnalyticsSettings />

The site's search runs in your browser; only the words you search for are counted, as above. GitHub may log visits as described in the [GitHub Privacy Statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement). The **Download** buttons link to Vela's releases on GitHub.

## Open source

You don't have to take our word for any of this: Vela's [source code](https://github.com/r3volution11/Vela-IRC) is public.
