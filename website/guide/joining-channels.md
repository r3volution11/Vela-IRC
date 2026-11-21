---
title: Joining channels
description: Join IRC channels in Vela with Join Channel (⌘J) or /join, use channel keys, auto-join channels on connect, start private conversations, leave, remove, detach or hide channels, and reopen them.
---

# Joining channels

## Join a channel

- **Join Channel…** (<kbd>⌘J</kbd>, or **File → Join Channel…**) asks for a channel name and an optional key on the selected network. It's also in the sidebar's **+** menu and a network's right-click menu.
- **Type `/join #channel`** in the message field. You can join several at once with `/join #one,#two` and pass keys with `/join #secret hunter2`.

Vela selects the channel as soon as you join. Channel names start with `#` on almost every network; Vela adds it in the Join Channel sheet if you leave it out.

## Join automatically

To join a channel every time you connect, add it to the network's **Channels** list: right-click the network, choose **Edit Network…** and add it under **Channels**, with its key if it has one. Keys are stored in your Keychain.

Vela also remembers channels you had open and rejoins them after a reconnect. Leaving a channel with `/part` (or **Leave Channel**) stops that: it also takes the channel off the network's **Channels** list, and joining it again puts it back where it was, with its key. **Remove Channel…** takes it off the list for good.

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

- **Leave Channel** parts the channel but keeps it in the list, dimmed, with its history. It comes off the network's auto-join list too, so it stays left when you reconnect. **Join Channel** rejoins it and puts it back on the list where it was, with its key.
- **Remove Channel…** leaves the channel if you're in it and takes it out of the list. It also comes off the network's auto-join list, and its key comes out of your Keychain. If you [save message history](/guide/messages-and-layouts#scrollback-and-history), its messages stay in it on disk.

A tab's **×** (or a middle-click) leaves and removes a channel in one step, like **Remove Channel…**. For a private conversation, **×** and **Close Conversation** close it. <kbd>⌘W</kbd> does the same for the selected channel or conversation, with tabs or the sidebar; the **File** menu item says what it will do.

You can also type `/part` (or `/leave`, optionally with a reason) to leave, and `/close` (or `/wc`) to remove. The [command palette](/guide/command-palette) has **Leave**, **Join** and **Remove** for the selected channel.

Through a bouncer, leaving works differently: the bouncer stays in the channel. See [Through a bouncer](#through-a-bouncer) below.

### Asking first

Vela asks before you leave or remove a channel, including with a tab's **×**, and the sheet has a **Don't ask again** checkbox. To turn either question back on or off, use **Ask before leaving a channel** and **Ask before removing a channel** in **Settings → Networks → Channels**, or set `channels.confirmLeave` and `channels.confirmRemove` in [settings.json](/reference/settings#channels). `/part` and `/close` never ask, and closing a conversation or hiding a channel doesn't either.

### Changed your mind?

- **Edit → Undo** (<kbd>⌘Z</kbd>) right after leaving, removing, hiding or closing puts it back: a channel you left is joined again (and goes back on the auto-join list), and a removed or hidden channel or closed conversation returns where it was. **Redo** (<kbd>⇧⌘Z</kbd>) does it again. If you've typed since, <kbd>⌘Z</kbd> undoes the typing first.
- **File → Reopen Closed Channel** (<kbd>⇧⌘T</kbd>) brings back the channel you removed or hid, or the conversation you closed, last. When that's a conversation, the menu says **Reopen Closed Conversation**. Press it again to go further back.
- **File → Recently Closed** lists the last 20, newest first. Choose one to reopen it.

A reopened channel comes back in its old place, muted or not, with the **New** line where you left off. It goes back on the auto-join list with its key, and Vela joins it again. Offline, it's joined when you connect. A hidden channel comes back still detached. The command palette has **Reopen Closed Channel** and a **Reopen** (or **Show**) command for each one too. Vela forgets the list when you quit.

### Through a bouncer

On a network that goes through a bouncer (ZNC or soju), the bouncer stays in your channels for you, so leaving a channel in Vela doesn't have to mean leaving it on IRC:

- **Leave Channel**, a tab's **×**, a middle-click and <kbd>⌘W</kbd> **detach** the channel. The bouncer stays in it and keeps its history, but stops sending it to Vela, and Vela shows it dimmed, "detached". It stays detached when you quit and reopen Vela. Vela asks first while `channels.confirmLeave` is on: "Leave #vela? Your bouncer stays in the channel and keeps its history; join it again to catch up."
- **Join Channel** on a detached channel reattaches it, and the bouncer plays back what you missed.
- **Hide Channel** (or **×** or <kbd>⌘W</kbd> again) takes a detached channel out of the list, and the bouncer keeps it, detached. See [Hidden channels](#hidden-channels).
- **Remove Channel…** parts the channel, so the bouncer leaves it and forgets it too, and takes it out of the list.
- `/part` really parts, even through a bouncer, so the bouncer forgets the channel. To leave it only in Vela, use **Leave Channel**.

To make a tab's **×**, a middle-click and <kbd>⌘W</kbd> remove channels from the bouncer instead, turn on **Closing a channel removes it from the bouncer** in **Settings → Networks → Channels** (`channels.bouncerCloseRemoves` in [settings.json](/reference/settings#channels)). **Leave Channel** in the menu still detaches.

If the bouncer sends a message from a detached channel (soju passes on mentions, for example), it counts as unread or as a mention, and the channel stays detached. If the bouncer doesn't confirm a detach, Vela says so in the network's console and keeps you in the channel. It never parts instead.

If you're disconnected from the bouncer when you detach or remove a channel, Vela tells the bouncer after your next connection, even if you quit Vela in between. Joining a channel you left or detached sends a join to the bouncer.

### Hidden channels

A hidden channel is out of the tabs, sidebar and rail, but still on your bouncer, detached, keeping its history. Messages the bouncer passes on from it never bring it back by themselves. If you [save message history](/guide/messages-and-layouts#scrollback-and-history), they're kept for when you show it; either way, joining it again catches up from the bouncer. It stays hidden when you quit and reopen Vela. To get it back:

- **Edit → Undo** (<kbd>⌘Z</kbd>) right after hiding it, or **File → Reopen Closed Channel** (<kbd>⇧⌘T</kbd>).
- Right-click the network, choose **Edit Network…**, and under **Hidden channels** click **Show** (back in the list, still detached) or **Join** (back, and joined).
- In the command palette (<kbd>⇧⌘P</kbd>), choose **Show #channel (Network)**.
- Type `/join #channel`.

## The server console

Each network has a console (click the network's name in the sidebar) showing server messages, `/whois` replies and errors. You can type commands there, but not chat, because there's no channel to send to. Anything unrecognized is sent to the server as typed, so commands like `/list` and `/motd` work.
