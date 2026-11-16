---
title: Joining channels
description: Join IRC channels in Vela with Join Channel (⌘J) or /join, use channel keys, auto-join channels on connect, start private conversations, and leave or close channels.
---

# Joining channels

## Join a channel

- **Join Channel…** (<kbd>⌘J</kbd>, or **File → Join Channel…**) asks for a channel name and an optional key on the selected network. It's also in the sidebar's **+** menu and a network's right-click menu.
- **Type `/join #channel`** in the message field. You can join several at once with `/join #one,#two` and pass keys with `/join #secret hunter2`.

Vela selects the channel as soon as you join. Channel names start with `#` on almost every network; Vela adds it in the Join Channel sheet if you leave it out.

## Join automatically

To join a channel every time you connect, add it to the network's **Channels** list: right-click the network, choose **Edit Network…** and add it under **Channels**, with its key if it has one. Keys are stored in your Keychain.

Vela also remembers channels you had open and rejoins them after a reconnect. Leaving a channel with `/part` (or **Leave Channel**) stops that.

Through a bouncer, the bouncer rejoins your channels for you. See [Connecting through a bouncer](/guide/bouncers).

## Private conversations

To message someone privately:

- Type `/query nick` (or `/query nick hello!` to say something straight away), or `/msg nick hello!`.
- Double-click their name in the [member list](/guide/member-list), or right-click it and choose **Message**.
- Hover one of their messages, click **…** and choose **Message nick**.

Conversations appear under the network in the sidebar, after its channels.

## Leave or close

Right-click a channel in the sidebar or tabs:

- **Leave Channel** parts the channel but keeps it in the sidebar, greyed out, with its history. **Join Channel** rejoins it.
- **Close Channel** leaves and removes it. Its messages stay in your history on disk.

You can also type `/part` (optionally with a reason), `/close`, or hover a tab and click its **×**.

## The server console

Each network has a console (click the network's name in the sidebar) showing server messages, `/whois` replies and errors. You can type commands there, but not chat, because there's no channel to send to. Anything unrecognized is sent to the server as typed, so commands like `/list` and `/motd` work.
