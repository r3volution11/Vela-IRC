---
title: Privacy
description: The Vela app has no telemetry, analytics or accounts. Who Vela talks to, what update checks, previews and GIFs reveal, Apple Intelligence and Siri, what's on your Mac, and this site.
---

# Privacy

**The Vela app has no telemetry, no analytics, no crash reporting service and no accounts.** There is no Vela server, and nobody but you knows how you use it. The one thing Vela does on its own is check velairc.app for a new version once a day, which sends only Vela's version and which you can turn off: see [Updates](#updates). (This website is a separate matter: see [This website](#this-website).)

## Who Vela talks to

Vela only makes connections for things you've set up or turned on:

| Connection | When | What the other side learns |
| --- | --- | --- |
| **IRC servers and bouncers you add** | While connected, encrypted with TLS by default | What any IRC server sees: your IP address (or your bouncer's), nickname and messages. |
| **velairc.app** (hosted by GitHub Pages) | Once a day, while **Check for updates automatically** is on (it's on by default), and when you choose **Check for Updates…** | Your IP address and Vela's version, as any download of a web page would. See [Updates](#updates). |
| **GitHub** | When you install an update | Your IP address and which version you download. |
| **Sites behind links people post** | When a [link preview](/guide/inline-media) loads, unless you turn previews off or limit them | Your IP address and that Vela fetched the page. No cookies are sent. |
| **Sites that only show their page to a browser** (IMDb, for example) | When a link preview finds a bot check instead of the page, unless you turn off **Load previews from sites that need a browser** | What a visit in Safari tells them: your IP address, and whatever the page's own check script collects. It runs in a private session that's thrown away afterwards, with images, other sites and your local network blocked. See [Sites that need a browser](/guide/inline-media#sites-that-need-a-browser). |
| **KLIPY, for GIF search** (or GIPHY, if you choose it) | Never in this version: GIF search comes in a later version. With it, only while the **GIFs** tab of the [emoji and GIF picker](/guide/emoji-and-gifs) is open | What you search for and your IP address. The previews load from them too. Nothing about you or your conversations goes with it, and Vela turns off their optional tracking. |
| **Video providers** (YouTube, Vimeo, Streamable, Twitch) | A video card fetches its title and thumbnail; the player itself loads only when you press play | Your IP address; once you press play, whatever the provider's player collects. YouTube plays from `youtube-nocookie.com`, and the player keeps nothing after it closes. |
| **AI providers you add** (OpenAI, Anthropic, Google Gemini, or a server such as Ollama) | Only when Catch me up or a Recap uses one of [your own models](/guide/ai-models), and only after you've agreed on the sheet that says what's sent. **Test Connection**, when you add one, asks for its list of models with your key | The messages you asked about, their nicks and your nick, never channel, network or server names; your IP address and your API key, as any request to them does. Their data policy applies, and the usage is billed to your key. A server on your Mac keeps it all on your Mac. See [AI privacy](/guide/ai-privacy). |
| **Ollama and LM Studio on your Mac** | While **Settings → AI Providers** is open (when it opens, on **Look Again** and when you come back to Vela), never on a timer | Nothing leaves your Mac: Vela asks `127.0.0.1` on ports 11434 and 1234 for their list of models, to offer **Connect**. See [Models on your Mac](/guide/ai-models#on-this-mac). |
| **Apple's Private Cloud Compute** | Never in this version: Private Cloud Compute for long catch-ups comes in a later version. With it, only if you turn on **Use Private Cloud Compute for long catch-ups** (macOS 27 or later; off by default), for a catch-up too long for one pass on your Mac | Nothing it keeps: the request is encrypted, used only to write the summary, and not stored or readable by Apple. See [Apple Intelligence, translation and Siri](#apple-intelligence). |

Vela never fetches previews from your local network (`localhost`, private IP addresses, `.local` names), so a link in a channel can't make your Mac probe your router or other devices.

**You're in control of previews.** Turn them off, make them click-to-load, disable them per channel, hide adult sites, blur images until clicked, or set rules for individual sites. See [Inline media & privacy](/guide/inline-media#controlling-media).

**This version of Vela has no GIF search,** so it never contacts KLIPY or GIPHY for one. (A GIF link someone posts is a link like any other: its preview loads from the GIF's site, under your [preview settings](/guide/inline-media#gifs).) When GIF search arrives, a GIF you send goes out as its address, and the clients of the people in the channel that show images load it from KLIPY or GIPHY, as with any link. GIPHY's links include a tracking token that its terms don't let Vela remove, so it goes to everyone who loads the GIF; KLIPY's don't. Its **Search GIFs** setting turns it off, and Vela then never contacts a GIF service. See [Emoji & GIFs](/guide/emoji-and-gifs#privacy).

## Apple Intelligence, translation and Siri {#apple-intelligence}

- **Catch me up, Recap and translation run on your Mac.** Summaries come from the Apple Intelligence model on your Mac, and translations from Apple's Translation framework. Your conversations aren't sent to Apple, to Vela's developers or anyone else, and summaries and translations are kept only in memory. See [Apple Intelligence & translation](/guide/apple-intelligence#privacy).
- **Your own AI models, only if you add them.** Catch me up and Recap can use OpenAI, Anthropic, Google Gemini or a server such as Ollama with your own key. The first time, Vela asks, and says exactly what's sent: the messages you ask about, their nicks and your nick, never a channel's, network's or server's name or your account. Keys are kept in your Keychain, never in settings.json. Translation always stays on your Mac. **Settings → AI Privacy** lists what each provider gets and where it goes, and takes your OK back. See [AI privacy](/guide/ai-privacy).
- **Private Cloud Compute comes in a later version, and will be off unless you turn it on.** This version never uses it: every catch-up is summarized on your Mac. Vela is waiting for Apple's permission to use it, so for now it's only in development builds. There, on macOS 27 or later, **Use Private Cloud Compute for long catch-ups** in **Settings → Intelligence** ([`intelligence.privateCloudCompute`](/reference/settings#intelligence.privateCloudCompute)) sends a catch-up that's too long for one pass on your Mac to Apple's [Private Cloud Compute](https://security.apple.com/blog/private-cloud-compute/): the messages in that stretch with their nicks, and your nick, but not the channel's or the network's name. Apple's guarantees apply: the request is encrypted on the way, used only to write the summary, not stored afterwards, and not readable by Apple. Short catch-ups, translation and everything else stay on your Mac, and Vela still sends nothing to its developers or anyone else.
- **Translation languages come from Apple.** The first time you translate from a language, macOS asks to download it, and downloads it from Apple once.
- **A Recap is kept only while its window is open.** It reads messages Vela already has (and, with **Save message history** on, your saved history), tells Apple Intelligence the messages and your nick but no channel, network or person's name, and is forgotten when you close it. **Copy as Markdown** and **Save as Markdown…** are the only ways to keep one. A Recap's log uses no Apple Intelligence. See [Recap](/guide/recap#privacy).
- **Writing Tools is Apple's.** When you use it, Vela hands it the text in the message field, and Apple Intelligence handles it as it does in any app.
- **Spotlight gets names only, unless you turn on messages:** your channel names, the nicks of people you talk to in private, and their networks. Turn off **Show channels in Spotlight** in **Settings → Integrations** to remove them from Spotlight's results. Your messages reach Spotlight only if you turn on **Search messages in Spotlight** (off by default, and only while message history is saved); turning it off, or deleting saved history, removes them. Spotlight's index stays on your Mac. See [Messages in Spotlight](/guide/siri-shortcuts#messages-in-spotlight). On macOS 27, the same names are also kept for Siri, hidden from Spotlight's results, so Siri can find a channel or a nick when you ask it to send a message; the setting doesn't remove those. See [Spotlight](/guide/siri-shortcuts#spotlight).
- **Siri learns where you send messages.** When you send one, Vela tells Siri which channel it went to, so Siri can suggest it later; it never shares the text. What you say to Siri is handled by Siri, under Apple's privacy policy. See [Siri, Shortcuts & Spotlight](/guide/siri-shortcuts#privacy).

## Updates {#updates}

Vela checks for new versions with [Sparkle](https://sparkle-project.org), the open-source updater many Mac apps use. See [Updates](/guide/updates).

- **What a check sends:** a request for velairc.app's update feed (`https://velairc.app/appcast.xml`). Like any web request, it carries your IP address; its User-Agent says which version of Vela and of Sparkle you have (`Vela/1.1.0 Sparkle/2.10.1`). Nothing else: Sparkle's optional system profile (your Mac's model, macOS version, language and so on) is turned off in Vela, and there's no identifier, account or usage data.
- **Who gets it:** velairc.app is hosted by GitHub Pages, so GitHub receives the request and may log it as described in the [GitHub Privacy Statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement). Vela's developers don't see it. This website's analytics (below) is never part of it: the feed is a plain file, and the app never runs the site's pages.
- **Downloads:** an update downloads `Vela.dmg` from Vela's releases on GitHub, which learns your IP address and the version, as with any download. The release notes come in the feed, so the update window loads nothing else.
- **Signed updates:** every update is signed, and Vela checks the signature before installing it, so a changed or substituted download is refused.
- **When:** once a day while **Check for updates automatically** is on (the default), and whenever you choose **Check for Updates…**. Development builds (Vela Dev) never check.
- **Turning it off:** turn off **Check for updates automatically** in **Settings → Updates** or the **About** window ([`updates.checkAutomatically`](/reference/settings#updates.checkAutomatically)). Vela then connects to velairc.app only when you choose **Check for Updates…**.

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
- **Your channels and where you stopped reading,** saved either way: each channel and conversation you have open, its read position, whether it's muted, its place in the sidebar and whether to rejoin it, and which channels you've left (on a [bouncer](/guide/bouncers), detached or hidden). That's how unread counts, the **New** line and Catch me up work after a restart. No messages are part of it.
- **Chat logs**, only if you turn them on (they're off by default). They're separate from message history: plain-text copies of your channels and conversations, unencrypted, in Vela's folder or one you choose, that Vela never loads back. Vela never sends them anywhere, but a folder you choose may sync if it's in iCloud Drive or a similar service. See [Chat logs](/guide/chat-logs#privacy).
- **Link previews and images** you've loaded, while message history is saved: page previews in the database, refreshed after a week (cached previews older than 30 days are deleted when Vela starts), and images in Vela's cache folder. With history off, they're kept in memory and loaded again after a restart.
- **Drafts** you haven't sent, in memory while Vela is open.
- **Settings, networks and themes** as plain files you can read.
- **Passwords, channel keys and client certificates** in your macOS Keychain, never in plain files.
- **GIFs from links people post** (the small video copies Vela plays), in a temporary folder that Vela empties each time it starts.
- **When Vela last checked for updates,** a version it found while you were busy, so it can offer it when you next open Vela, and the last version it showed **What's New** for. They're in Vela's preferences.

Outside the container, macOS keeps your channel and conversation names in Spotlight's index (as search results unless you turn off **Show channels in Spotlight**, and on macOS 27 also hidden from results, for Siri), your saved messages there too if you turn on **Search messages in Spotlight**, the translation languages you've downloaded, and the notifications you allow until you clear them from Notification Center.

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
