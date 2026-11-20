---
title: Joining channels
description: Join IRC channels in Vela with Join Channel (⌘J) or /join, use channel keys, auto-join channels on connect, start private conversations, leave or remove channels, and reopen them.
---

# Joining channels

## Join a channel

- **Join Channel…** (<kbd>⌘J</kbd>, or **File → Join Channel…**) asks for a channel name and an optional key on the selected network. It's also in the sidebar's **+** menu and a network's right-click menu.
- **Type `/join #channel`** in the message field. You can join several at once with `/join #one,#two` and pass keys with `/join #secret hunter2`.

Vela selects the channel as soon as you join. Channel names start with `#` on almost every network; Vela adds it in the Join Channel sheet if you leave it out.

## Join automatically

To join a channel every time you connect, add it to the network's **Channels** list: right-click the network, choose **Edit Network…** and add it under **Channels**, with its key if it has one. Keys are stored in your Keychain.

Vela also remembers channels you had open and rejoins them after a reconnect. Leaving a channel with `/part` (or **Leave Channel**) stops that, unless it's on the network's **Channels** list. **Remove Channel…** takes it off that list too.

Through a bouncer, the bouncer rejoins your channels for you. See [Connecting through a bouncer](/guide/bouncers).

## Private conversations

To message someone privately:

- Type `/query nick` (or `/query nick hello!` to say something straight away), or `/msg nick hello!`.
- Double-click their name in the [member list](/guide/member-list), or right-click it and choose **Message**.
- Hover one of their messages, click **…** and choose **Message nick**.

Conversations appear under the network in the sidebar, after its channels.

## Arrange channels and conversations

New channels and conversations go at the end of their network's list. Drag them into any order in the sidebar, rail or tabs: channels stay above conversations, and each moves within its own group. Moving channels also reorders the network's auto-join list. To go back to alphabetical order, right-click the network and choose **Sort Channels A–Z**. See [Arranging networks and channels](/guide/the-window#arranging-networks-and-channels).

## Leave or remove

Right-click a channel in the sidebar or tabs:

- **Leave Channel** parts the channel but keeps it in the list, dimmed, with its history. **Join Channel** rejoins it.
- **Remove Channel…** leaves the channel if you're in it and takes it out of the list. It also comes off the network's auto-join list, and its key comes out of your Keychain. Its messages stay in your history on disk.

A tab's **×** (or a middle-click) leaves a channel you're in, and removes one you've already left. For a private conversation, **×** and **Close Conversation** close it.

You can also type `/part` (or `/leave`, optionally with a reason) to leave, and `/close` (or `/wc`) to remove.

### Asking first

Vela asks before you leave or remove a channel, and the sheet has a **Don't ask again** checkbox. To turn either question back on or off, go to **Settings → Networks → Channels**, or set `channels.confirmLeave` and `channels.confirmRemove` in [settings.json](/reference/settings#channels). `/part` and `/close` never ask, and closing a conversation doesn't either.

### Changed your mind?

- **Edit → Undo** (<kbd>⌘Z</kbd>) right after leaving, removing or closing puts it back: a channel you left is joined again, and a removed channel or closed conversation returns where it was. **Redo** (<kbd>⇧⌘Z</kbd>) does it again. If you've typed since, <kbd>⌘Z</kbd> undoes the typing first.
- **File → Reopen Closed Channel** (<kbd>⇧⌘T</kbd>) brings back the channel you removed or the conversation you closed last. Press it again to go further back.
- **File → Recently Closed** lists the last 20, newest first. Choose one to reopen it.

A reopened channel comes back in its old place, muted or not, with the **New** line where you left off. It goes back on the auto-join list with its key, and Vela joins it again. Offline, it's joined when you connect. The command palette has **Reopen Closed Channel** and a **Reopen** command for each one too. Vela forgets the list when you quit.

### Through a bouncer

Leaving or removing a channel parts it, so your bouncer (ZNC or soju) leaves it too and stays in step. If you're disconnected from the bouncer at the time, Vela parts it as soon as the bouncer rejoins it on your next connection, as long as Vela is still open. Joining a channel you left sends a join to the bouncer.

## The server console

Each network has a console (click the network's name in the sidebar) showing server messages, `/whois` replies and errors. You can type commands there, but not chat, because there's no channel to send to. Anything unrecognized is sent to the server as typed, so commands like `/list` and `/motd` work.
