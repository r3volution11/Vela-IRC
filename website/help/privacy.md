---
title: Privacy
description: Vela has no telemetry, analytics or accounts. Here's who Vela talks to, what link previews reveal, how on-device AI and Siri are handled, and what's stored on your Mac.
---

# Privacy

**Vela has no telemetry, no analytics, no crash reporting service and no accounts.** There is no Vela server: the app never phones home, and nobody but you knows how you use it.

## Who Vela talks to

Vela only makes connections for things you've set up or turned on:

| Connection | When | What the other side learns |
| --- | --- | --- |
| **IRC servers and bouncers you add** | While connected, encrypted with TLS by default | What any IRC server sees: your IP address (or your bouncer's), nickname and messages. |
| **Sites behind links people post** | When a [link preview](/guide/inline-media) loads, unless you turn previews off or limit them | Your IP address and that Vela fetched the page. No cookies are sent. |
| **Video providers** (YouTube, Vimeo, Streamable, Twitch) | A video card fetches its title and thumbnail; the player itself loads only when you press play | Your IP address; once you press play, whatever the provider's player collects. YouTube plays from `youtube-nocookie.com`, and the player keeps nothing after it closes. |

Vela never fetches previews from your local network (`localhost`, private IP addresses, `.local` names), so a link in a channel can't make your Mac probe your router or other devices.

**You're in control of previews.** Turn them off, make them click-to-load, disable them per channel, hide adult sites, blur images until clicked, or set rules for individual sites. See [Inline media & privacy](/guide/inline-media#controlling-media).

## Apple Intelligence, translation and Siri {#apple-intelligence}

- **Catch me up and translation run on your Mac.** Summaries come from the Apple Intelligence model on your Mac, and translations from Apple's Translation framework. Your conversations aren't sent to Apple, to Vela's developers or anyone else, and summaries and translations are kept only in memory. See [Apple Intelligence & translation](/guide/apple-intelligence#privacy).
- **Translation languages come from Apple.** The first time you translate from a language, macOS asks to download it, and downloads it from Apple once.
- **Writing Tools is Apple's.** When you use it, Vela hands it the text in the message field, and Apple Intelligence handles it as it does in any app.
- **Spotlight gets names only:** your channel and conversation names and their networks, never messages. Turn off **Show channels in Spotlight** in **Settings → Apple Intelligence** to remove them.
- **Siri learns where you send messages.** When you send one, Vela tells Siri which channel it went to, so Siri can suggest it later; it never shares the text. What you say to Siri is handled by Siri, under Apple's privacy policy. See [Siri, Shortcuts & Spotlight](/guide/siri-shortcuts#privacy).

## What other IRC users can see

This is how IRC works in any client, but it's worth knowing:

- **Your host or IP address**, unless your network gives you a cloak or you connect through a bouncer.
- **CTCP replies.** Like most IRC clients, Vela answers `VERSION` (with "Vela" and its version), `TIME` (your local time) and `PING` requests automatically.
- **Typing indicators**, on servers that support them. Turn off **Send typing indicators** in **Settings → Messages → Typing** to keep your typing private.

## What's stored on your Mac

Everything stays on your Mac, inside Vela's sandbox container:

- **Message history** in a local database, kept forever unless you set **Settings → Advanced → Keep messages**.
- **Link previews** you've loaded. Page previews are refreshed after a week, and cached previews older than 30 days are deleted when Vela starts.
- **Settings, networks and themes** as plain files you can read.
- **Passwords, channel keys and client certificates** in your macOS Keychain, never in plain files.

Outside the container, macOS keeps your channel and conversation names in Spotlight's index (unless you turn off **Show channels in Spotlight**), and the translation languages you've downloaded.

Vela is sandboxed: it can only reach its own container and files you choose to open, such as a theme you import. See [where files live](/help/troubleshooting#where-files-live) and [how to remove everything](/guide/install#uninstalling).

## This website

velairc.app is a static site hosted on GitHub Pages. It sets no cookies and has no analytics or trackers; search runs entirely in your browser. GitHub may log visits as described in the [GitHub Privacy Statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement). The **Download** buttons link to Vela's releases on GitHub.

## Open source

You don't have to take our word for any of this: Vela's [source code](https://github.com/r3volution11/Vela-IRC) is public.
