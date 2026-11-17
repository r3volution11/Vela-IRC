---
title: Privacy
description: Vela has no telemetry, analytics or accounts. Here's exactly who Vela talks to, what link previews reveal, and what's stored on your Mac.
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

## What other IRC users can see

This is how IRC works in any client, but it's worth knowing:

- **Your host or IP address**, unless your network gives you a cloak or you connect through a bouncer.
- **CTCP replies.** Like most IRC clients, Vela answers `VERSION` (with "Vela" and its version), `TIME` (your local time) and `PING` requests automatically.
- **Typing indicators**, on servers that support them. Turn off **Settings → Advanced → Send typing indicators** to keep your typing private.

## What's stored on your Mac

Everything stays on your Mac, inside Vela's sandbox container:

- **Message history** in a local database, kept forever unless you set **Settings → Advanced → Keep messages**.
- **Link previews** you've loaded. Page previews are refreshed after a week, and cached previews older than 30 days are deleted when Vela starts.
- **Settings, networks and themes** as plain files you can read.
- **Passwords, channel keys and client certificates** in your macOS Keychain, never in plain files.

Vela is sandboxed: it can only reach its own container and files you choose to open, such as a theme you import. See [where files live](/help/troubleshooting#where-files-live) and [how to remove everything](/guide/install#uninstalling).

## This website

velairc.app is a static site hosted on GitHub Pages. It sets no cookies and has no analytics or trackers; search runs entirely in your browser. GitHub may log visits as described in the [GitHub Privacy Statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement). The **Download** buttons link to Vela's releases on GitHub.

## Open source

You don't have to take our word for any of this: Vela's [source code](https://github.com/r3volution11/Vela-IRC) is public.
