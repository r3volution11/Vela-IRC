---
title: Troubleshooting & FAQ
description: Fix common Vela problems, such as connecting, TLS errors, ZNC logins, link previews, notifications, Catch me up, translation and Siri, and find or reset Vela's settings files.
---

# Troubleshooting & FAQ

## Can't connect {#cant-connect}

Start with the network's **server console**: click the network's name in the sidebar (or its first tab). Vela writes connection errors there.

**TLS turned on for a plain-text port, or off for a TLS port.** This is the most common cause. Most networks use **6697 with TLS** and **6667 without**. Bouncers use whatever port their listener was configured with, and some listeners have TLS turned off. If the connection hangs and times out, try toggling **Use TLS** in the network's settings (right-click it → **Edit Network…**).

**"The server's TLS certificate was rejected".** The server's certificate couldn't be verified. Check the address for typos first: certificates only match the right host name. If it's your own bouncer with a self-signed certificate ([ZNC](https://znc.in) makes one by default), turn on **Allow invalid certificates** for that network only.

**ZNC rejects your password.** ZNC needs to know which user and which network you mean. As a server password, use `username/network:password`, for example `doug/libera:hunter2`; with SASL PLAIN, use `username/network` as the account. See [Connecting through a bouncer](/guide/bouncers#znc).

**"SASL authentication failed".** Check the account name and password under **Authentication**. The account defaults to your nickname, which isn't always your account name. Make sure the account is registered on that network; Vela connects anyway, just without logging you in.

**Your nickname is taken.** Add a few **Alternates** in the network's settings, and Vela tries them in order.

**A firewall or VPN is in the way.** Some workplace and public networks block IRC ports, and some IRC networks block VPN and Tor addresses (they usually explain how to connect anyway on their website). If you use an outgoing firewall such as Little Snitch or LuLu, allow Vela to connect.

**It disconnects when my Mac sleeps.** That's deliberate: Vela says goodbye with "Computer going to sleep" and reconnects when your Mac wakes, as long as **Reconnect automatically** is on in **Settings → Networks** (it is by default). To stay online around the clock, use a [bouncer](/guide/bouncers).

## Link previews aren't showing

Check these, roughly in order:

- **Is media off for this channel?** Look at the picture icon in the channel header, or right-click the channel. See [Inline media & privacy](/guide/inline-media#per-channel).
- **Settings → Media.** Is **Load previews automatically** on? If it's off, click a link's **Load preview** button instead. **Show link previews** can also be off on its own, and with **Videos** set to **Off** there's no player.
- **A blocked preview.** A small chip such as "Adult site · preview blocked" or "Blocked site" says why; click **Show once** or **Always allow**. See [Blocked previews](/guide/inline-media#blocked-previews).
- **Site rules.** Does **Settings → Media → Site rules** set the site to **Nothing** or **Text only**, or is **Only load previews from sites listed here** on? See [Site rules](/guide/inline-media#site-rules).
- **Image size.** Images larger than the limit (10 MB by default) show a placeholder you can click.
- **Local addresses.** Vela never previews links to `localhost`, private IP addresses or `.local` names.
- **The site itself.** Some sites block automated requests or need a login, so there's nothing to show. A failed preview is retried after a while.

A video card that won't play may be a video its owner doesn't allow to be embedded. Right-click it and choose **Open in Browser**.

## Reactions, replies or typing indicators are missing

They need the server, and any bouncer in between, to support IRCv3 message tags. Older ZNC versions don't pass them through. See [Reactions, replies & typing](/guide/reactions-replies-typing#when-do-these-work).

## Notifications don't appear

- Check **System Settings → Notifications → Vela** and any Focus that might be filtering it.
- Check **Settings → Notifications** in Vela.
- Vela doesn't notify you about the conversation you're looking at while Vela is in front.
- Muted channels only notify you when someone mentions you.

## Spelling or autocorrect doesn't behave as expected {#typing}

- **Check Settings → Messages → Typing.** Autocorrect, text replacements, and smart quotes and dashes follow your Mac's keyboard settings until you change them in Vela (or in the **Edit** menu, or by right-clicking the message field). After that, they stay the way you set them. Click **Use macOS Setting** to follow macOS again.
- **Some words are never corrected on purpose:** commands, nicks of people in the conversation, `#channels`, links, `:emoji:` codes and `` `code` ``. See [What's never corrected](/guide/sending-messages#irc-safe).

## Catch me up doesn't appear {#catch-me-up}

- **Is Apple Intelligence ready?** The box at the top of **Settings → Apple Intelligence** says. Catch me up needs a Mac with Apple silicon, Apple Intelligence turned on in System Settings, its model downloaded, and a supported language. See [What you need](/guide/apple-intelligence#requirements).
- **Are enough messages new?** The button waits for 25 new messages by default (**Show the button after**). To catch up on fewer, right-click the channel and choose **Catch Me Up**.
- **Is Offer Catch me up in busy channels on?** It controls only the button; the right-click menu and the command palette work either way.
- **Is anything new?** The button sits on the **New** marker, so it only appears in a channel with messages you haven't read.
- **Is the New line turned off?** With **Show the New line** off (Settings → Messages → Unread messages, or the Classic IRC preset) there's no button. Right-click the channel and choose **Catch Me Up**, or use the command palette.

If a summary looks wrong, click a topic to read the messages behind it, or click **Regenerate**. Summaries can contain mistakes.

## Translate isn't offered {#translate}

- **It's for other people's messages** in a language other than the one in **Settings → Apple Intelligence → Translate into**.
- **The message needs enough words** for its language to be clear. Short replies, emoji and bare links aren't offered.
- **macOS must be able to translate between the two languages.**
- **A declined download** stops automatic translation from that language. Choose **Translate** on one of its messages to be asked again.

## Siri or Shortcuts doesn't find Vela {#siri}

Open Vela once, so macOS registers its actions. If Vela's actions still don't appear, check that there's **only one copy of Vela.app** on your Mac (an old copy in Downloads, or one you built yourself, confuses macOS about which to use), delete the others, and open Vela from Applications. See [Siri, Shortcuts & Spotlight](/guide/siri-shortcuts#troubleshooting).

## macOS asks about the Keychain

Vela keeps passwords, channel keys and client certificates in your login keychain. If macOS asks whether Vela may use confidential information stored in "io.github.r3volution11.Vela", enter your Mac password and click **Always Allow**. This can happen after Vela is updated (or when you build it yourself), because macOS checks which app is asking. If you click **Deny**, Vela can't read the password and logging in fails until you allow it.

## A theme or settings.json has a mistake

Vela never leaves you with a broken window. If a theme file can't be read, Vela keeps the last version that worked and explains the problem in **Settings → Appearance**. [Creating themes → Troubleshooting](/customize/creating-themes#troubleshooting) explains each message.

If `settings.json` can't be read, Vela keeps your last good settings and says where the problem is in **Settings → Advanced** ("settings.json is invalid; keeping previous values. Line 3, column 3: Expected a comma."). It won't write to the file until you fix it, so nothing you typed is lost. Click **Open JSON View** to fix it right there: the [JSON view](/customize/settings-editor#problems) underlines the mistake and lists every problem, and the bottom bar says how many are left.

Saved settings.json in another editor while you had unsaved changes in the JSON view? The view says **settings.json changed on disk.** Choose **Reload** to take the other version, or **Keep My Changes** to keep yours and save over it. See [Unsaved changes](/customize/settings-editor#unsaved).

## Where Vela keeps your files {#where-files-live}

Vela is sandboxed, so everything lives in its container:

```text
~/Library/Containers/io.github.r3volution11.Vela/Data/Library/Application Support/Vela/
```

| File or folder | Holds |
| --- | --- |
| `settings.json` | Your [settings](/customize/settings-json) |
| `networks.json` | Your networks (never passwords) |
| `Themes/` | Your own themes |
| `vela.sqlite` | Message history, read positions and cached link previews |

**Settings → Advanced → ⋯ → Reveal Data Folder** opens it in Finder. Passwords, channel keys and certificates are in your login keychain, under `io.github.r3volution11.Vela`.

## Resetting Vela {#reset}

- **Reset one setting**: in **Settings → Advanced**, hover it and choose **⚙ → Reset Setting**, or delete its line from `settings.json`.
- **Reset all settings** to their defaults: choose **Settings → Advanced → ⋯ → [Reset All Settings…](/customize/settings-editor#reset-all)**. Your networks, themes and history stay, and so do keys Vela doesn't know. Or quit Vela and delete `settings.json` (or move it somewhere as a backup).
- **Start completely fresh**: quit Vela, then delete the whole `Vela` folder above. This removes your networks, themes and message history. To remove saved passwords too, open **Keychain Access** and delete the items named `io.github.r3volution11.Vela`.

## FAQ

### I can't find a setting

Type what you're looking for in the **Search** field at the top of the Settings sidebar. Vela searches every setting, by name, key, description and value, and shows the matches in **Settings → Advanced**. See [Settings editor](/customize/settings-editor#search).

Two settings have moved: **Reconnect automatically** is in **Settings → Networks**, and **Keep messages** is in **Settings → Messages → History**.

### Which macOS versions does Vela support?

macOS 26 Tahoe or later, on Apple silicon and Intel Macs. Catch me up and Writing Tools need Apple Intelligence, which needs Apple silicon; [translation](/guide/apple-intelligence#translate-messages) doesn't. On macOS 27, [Siri can do more](/guide/siri-shortcuts#macos-27) with Vela.

### Does Vela send my messages to an AI service?

No. [Catch me up](/guide/apple-intelligence#catch-me-up) summaries and [translations](/guide/apple-intelligence#translate-messages) are made on your Mac by Apple's on-device models, and Vela has no server of its own. [Writing Tools](/guide/sending-messages#writing-tools), which you start yourself, is Apple's feature, and Apple Intelligence handles it as it does in any app. See [Privacy](/help/privacy#apple-intelligence).

### Is Vela free?

Yes. Vela is free and open source under the [Mozilla Public License 2.0](/help/license), with no ads, accounts or in-app purchases.

### Does Vela update itself?

Not yet. Download the latest version from the [Install](/guide/install#updating) page; automatic updates are planned.

### Can I upload images, search my history or sync between Macs?

Not yet. Image uploads, a search window, iCloud sync, DCC and scripting are on the [roadmap](https://github.com/r3volution11/Vela-IRC/blob/main/ROADMAP.md). Your history is already stored with a full-text index, ready for search.

### How do I register my nickname?

Registration is handled by each network's services, usually NickServ. On Libera.Chat, for example, `/msg NickServ REGISTER yourpassword you@example.com`. Check your network's documentation. Once registered, set **Authentication** to **SASL PLAIN** in the network's settings so Vela logs you in automatically.

### How do I report a bug or ask for a feature?

Open an issue on [GitHub](https://github.com/r3volution11/Vela-IRC/issues/new/choose). Include your macOS and Vela versions and, if it's a connection problem, which network or bouncer you use. **Never paste passwords or private logs.**
