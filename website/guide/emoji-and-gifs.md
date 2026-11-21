---
title: Emoji & GIFs
description: Vela's emoji and GIF picker for the message field, opened with the smiley or ⇧⌘E. Search emoji and GIFs from KLIPY or GIPHY, pick from the keyboard, and send a GIF as a link.
---

# Emoji & GIFs

Click the **smiley** at the right end of the message field, or press <kbd>⇧⌘E</kbd>, to open the picker, with a search field that's ready for typing.

::: info GIF search is coming in a later version
This version of Vela has the **Emoji** tab. **GIF search** (the **GIFs** tab, described below) is being tested and arrives in a later version, once KLIPY, the GIF service it uses, has approved Vela. Until then, it's only in development builds.
:::

## From the keyboard {#keys}

| Key | Does |
| --- | --- |
| Type | Search |
| <kbd>↑</kbd> <kbd>↓</kbd> <kbd>←</kbd> <kbd>→</kbd> | Move through the emoji or GIFs |
| <kbd>Return</kbd> | Pick the selected one; with nothing selected, the first emoji found |
| <kbd>Tab</kbd> or <kbd>⌃Tab</kbd> | Switch between **Emoji** and **GIFs** |
| <kbd>Esc</kbd> | Close, back to the message field |
| <kbd>⇧⌘E</kbd> | Open or close the picker |

**Edit → Emoji & GIFs…** opens it too, and so does **Message Box: Emoji & GIFs…** in the [command palette](/guide/command-palette). The system's **Emoji & Symbols** viewer is still <kbd>⌃⌘Space</kbd>, and `:shortcode:` completion still works as you type (see [Tab completion](/guide/sending-messages#tab-completion)).

## Emoji

Search by name or by a familiar word: "thumbs", "+1", "lol" or "tada". With nothing typed, your frequently used emoji come first, then every category; the icons across the top jump to one. The emoji you pick here and the ones you react with share the same **Frequently Used** list.

Picking one puts it in the message field where your cursor was, and you carry on typing. The keyboard button at the bottom right opens the system's Character Viewer.

## GIFs

*In a later version of Vela (see above).* With GIFs, the picker has two tabs, **Emoji** and **GIFs**, and opens on the one you used last.

The **GIFs** tab shows what's trending until you search. Type at least two letters: the search starts once you pause, or straight away when you press <kbd>Return</kbd>. Scroll down for more.

Picking a GIF adds it to the message field as a small **GIF** chip. Add some words if you like, then press <kbd>Return</kbd>. To take the GIF out, click **×** on the chip, or press <kbd>Delete</kbd> at the start of the message.

**On IRC, a GIF is a link.** Your message goes out as your words followed by the GIF's address. People whose client shows images, Vela included, see the GIF play; everyone else sees the link.

GIF previews play while they're in view. To show still images instead, turn off **Play previews** in **Settings → Media → GIFs**. With **Reduce Motion** on in macOS, they're always still.

### Where GIFs come from {#services}

GIFs are powered by [KLIPY](https://klipy.com). Its name is under the results, and **View on KLIPY** opens your search, or what's trending, on klipy.com. You can switch to [GIPHY](https://giphy.com) in **Settings → Media → GIFs**; it needs a key of your own (see below).

Vela never mixes services or changes their results: you see them in the order the service sends them, and the GIFs load straight from it.

### Turning GIFs off {#turning-off}

Turn off **Search GIFs** in **Settings → Media → GIFs** and the **GIFs** tab goes away. Vela then never contacts a GIF service. Nothing is sent until you open the **GIFs** tab anyway: opening the picker on **Emoji** contacts nobody.

### Content rating {#rating}

**Content rating** in **Settings → Media → GIFs** sets the most explicit GIFs search shows, like a film rating: **G** (for everyone), **PG**, **PG-13** or **R** (adults). It starts at **R**, the loosest. KLIPY never returns nudity, even at **R**.

### Your own key {#own-key}

Vela has a KLIPY key built in, shared by everyone using Vela. When it's busy, the GIFs tab says **GIF search is busy right now**. **Try Again** works again after a minute, or you can use a free key of your own:

1. Sign in at [partner.klipy.com](https://partner.klipy.com).
2. Choose **Add Platform**.
3. Copy the key it shows.
4. Paste it into **Your own KLIPY key** in **Settings → Media → GIFs**, and click **Save**.

GIPHY always needs your own key: create an app on [GIPHY's developer dashboard](https://developers.giphy.com/dashboard/), choosing **API**, and paste its key the same way.

Keys are kept in your Keychain, never in settings.json. **Remove** forgets yours, and KLIPY goes back to Vela's key.

### When something goes wrong {#problems}

| The GIFs tab says | What to do |
| --- | --- |
| **GIF search is busy right now** | Wait a few minutes, or use your own KLIPY key. |
| **Can't reach KLIPY** | Check your internet connection, then click **Try Again**. |
| **KLIPY didn't accept your key** | Check the key in **Settings → Media → GIFs**. |
| **GIFs aren't set up in this build** | This copy of Vela has no KLIPY key built in. Use your own. |
| **GIPHY needs your own key** | Add a GIPHY key, or switch back to KLIPY. |

## Privacy {#privacy}

- **A search sends what you type, and your IP address, to KLIPY (or GIPHY).** So does loading the previews. Nothing else about you or your conversations goes with it.
- **Recipients load the GIF from the service** when their client shows it, as with any link. They learn nothing about you from that.
- **GIPHY's links carry a tracking token** (`cid`). Its terms don't allow removing it, so everyone who sees the GIF loads it with that token. Settings mentions this when you choose GIPHY.
- **Nothing is kept on disk.** Previews stay in memory while Vela is open.

See [Privacy](/help/privacy) for everything Vela connects to.

## Settings {#settings}

All of these are in **Settings → Media → GIFs**, and in [settings.json](/reference/settings#gifs):

| Setting | Key | Default |
| --- | --- | --- |
| **Search GIFs** | [`gifs.enabled`](/reference/settings#gifs.enabled) | On |
| **Service** | [`gifs.provider`](/reference/settings#gifs.provider) | KLIPY |
| **Content rating** | [`gifs.rating`](/reference/settings#gifs.rating) | R |
| **Play previews** | [`gifs.animatePreviews`](/reference/settings#gifs.animatePreviews) | On |
