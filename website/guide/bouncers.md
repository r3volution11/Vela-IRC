---
title: Connecting through a bouncer
description: Connect Vela to a ZNC or soju IRC bouncer, including the ZNC password format, TLS and self-signed certificates, soju network discovery, chat history, and leaving channels on the bouncer, detached.
---

# Connecting through a bouncer

A bouncer stays connected to IRC for you, so you keep receiving messages while your Mac is asleep. Vela has first-class support for the two most popular ones, **[ZNC](https://znc.in)** and **[soju](https://soju.im)**.

Add the bouncer like any other network (<kbd>⇧⌘N</kbd>), with your bouncer's address and port, and set **Bouncer → Type** to ZNC or soju.

## ZNC

ZNC uses **one connection per IRC network**, so add one Vela network for each network on your ZNC (for example "Libera via ZNC" and "OFTC via ZNC").

### Logging in

Use either method. Both tell ZNC which user and which network you want.

- **Server password** (the classic way): set **Authentication → Method** to **Server password** and enter

  ```text
  username/network:password
  ```

  For example `doug/libera:hunter2`, where `libera` is the network's name in ZNC.
- **SASL PLAIN**: set **Account** to `username/network` (for example `doug/libera`) and **Password** to your ZNC password.

### TLS and certificates

Match Vela's settings to your ZNC listener:

- **Your listener uses SSL/TLS** (`SSL = true` in ZNC): leave **Use TLS** on.
- **ZNC uses a self-signed certificate** (the default when ZNC generates its own `znc.pem`): also turn on **Allow invalid certificates**. Otherwise the connection fails certificate validation.
- **Your listener is plain text**: turn **Use TLS** off. Only do this on a network you trust, because your password is then sent unencrypted.

The port is whatever you configured for the listener in ZNC; it's often not 6697.

### What Vela does with ZNC

- **Playback.** If ZNC's `playback` module is loaded, Vela asks for only the messages it hasn't seen yet each time it connects, so nothing is shown twice. After a restart with **Save message history** off (the default for new installs), that's everything ZNC has kept, since Vela keeps messages only in memory.
- **What you missed counts as unread.** Messages ZNC replays that are newer than where you stopped reading count in the unread and mention badges, put the **New** line above them, and can be summarized with [Catch me up](/guide/apple-intelligence#catch-me-up). They never pop up notifications or play sounds. A channel Vela has never had open starts counting from when it first joins it, so its older history stays read. The same goes for history from soju or any server with chat history.
- **Your own messages from other clients.** With `self-message`, messages you send from another client connected to the same ZNC appear in Vela too. Vela and your other clients can stay connected at the same time.
- **Accurate timestamps** with `server-time`.
- **Channels.** ZNC rejoins your channels itself, so Vela doesn't send its own joins. The **Channels** list in the network editor is only used for direct connections.
- **Leaving a channel detaches it.** **Leave Channel**, a tab's **×** and a middle-click send `/msg *status detach #channel`: ZNC stays in the channel and keeps buffering it, and Vela shows it dimmed. **Join Channel** reattaches it, and Vela asks the `playback` module for what you missed. See [Leaving channels through a bouncer](#leaving-channels-through-a-bouncer).
- **Talking to ZNC.** Send commands to ZNC's modules as usual, for example `/msg *status help`.

::: info Reactions, replies and typing
These need IRCv3 message tags. Some bouncers, including older ZNC versions, don't pass them through. Vela notices and hides the reaction and reply buttons on those connections.
:::

## soju

soju uses **one connection for all your networks**. Add it once:

1. Enter your soju server's address and port.
2. Set **Authentication → Method** to **SASL PLAIN**, with your soju username as the **Account** and your soju password.
3. Set **Bouncer → Type** to **soju** and click **Add Network**.

Vela connects, asks soju for your networks, and adds each one under the bouncer in the sidebar, with its own channels and history. Networks you add or remove on soju (for example with `/msg BouncerServ network create`) appear and disappear in Vela automatically. The bouncer entry itself only shows its server console.

The bouncer's networks always stay under it. Drag them to change their order there, or drag the bouncer to move it and its networks together. See [Arranging networks and channels](/guide/the-window#arranging-networks-and-channels).

Each network provided by soju uses the bouncer's server, identity and login. You can still rename it and give it its own perform commands, highlight words, ignore list and auto-connect setting; edit the bouncer to change everything else.

### History

soju supports `chathistory`, so Vela fetches the messages you missed when it connects, and scrolling up past the oldest message Vela has loads older history from the bouncer.

With **Save message history** off (the default for new installs), Vela keeps messages only in memory, so after a restart soju fills your channels in again with what it has kept. See [Scrollback and history](/guide/messages-and-layouts#scrollback-and-history).

### Leaving a channel detaches it

**Leave Channel**, a tab's **×** and a middle-click send `/msg BouncerServ channel update #channel -detached true`: soju stays in the channel and keeps its history, and Vela shows it dimmed. **Join Channel** reattaches it, and Vela fetches what you missed. When soju detaches a channel itself (with `-detach-after`), Vela shows it detached too. By default soju passes on mentions from detached channels; they appear in the network's console.

## Leaving channels through a bouncer

On a ZNC or soju network, Vela keeps your channels on the bouncer unless you ask it not to:

| You | Vela | The bouncer |
| --- | --- | --- |
| **Leave Channel**, a tab's **×**, a middle-click or <kbd>⌘W</kbd> | Shows the channel dimmed, "detached" | Stays in it, keeps its history, stops sending it to Vela |
| **Join Channel** on a detached channel | Joins it and catches up | Reattaches it and plays back what you missed |
| **Hide Channel**, or **×** or <kbd>⌘W</kbd> on a detached channel | Takes it out of the list | Stays in it, detached |
| **Remove Channel…**, `/close` or `/part` | Parts it (`/part` keeps it in the list, dimmed) | Leaves it and forgets it |

- Leaving asks first, while **Ask before leaving a channel** is on: "Leave #vela? Your bouncer stays in the channel and keeps its history; join it again to catch up."
- A detached channel stays detached when you quit and reopen Vela, and so does a hidden one.
- To get a hidden channel back, right-click the network, choose **Edit Network…** and click **Show** or **Join** under **Hidden channels**, or choose **Show #channel (Network)** in the command palette (<kbd>⇧⌘P</kbd>). <kbd>⌘Z</kbd> and **File → Reopen Closed Channel** (<kbd>⇧⌘T</kbd>) bring back one you just hid.
- A message the bouncer passes on from a detached channel counts as unread, or as a mention, and leaves the channel detached. One from a hidden channel never brings it back; if you [save message history](/guide/messages-and-layouts#scrollback-and-history), it's kept for when you show it.
- If the bouncer doesn't confirm a detach within a few seconds, Vela says so in the network's console and keeps you in the channel. It never parts the channel instead.
- Detached or removed while you weren't connected to the bouncer? Vela tells the bouncer after your next connection, even if you quit Vela in between.
- To make a tab's **×**, a middle-click and <kbd>⌘W</kbd> remove channels from the bouncer instead, turn on **Settings → Networks → Channels → Closing a channel removes it from the bouncer** (`channels.bouncerCloseRemoves`).

Vela knows a network is a bouncer from **Bouncer → Type** in the network editor. For a network set up without one, it goes by what the server offers when you connect: soju's `soju.im/bouncer-networks`, or ZNC's `znc.in/…` capabilities.

See [Leave or remove](/guide/joining-channels#leave-or-remove) for networks without a bouncer.

## Troubleshooting

See [Can't connect](/help/troubleshooting#cant-connect) for the common causes: TLS on a plain-text port (or the other way around), a self-signed certificate, the ZNC password format, and firewalls.
