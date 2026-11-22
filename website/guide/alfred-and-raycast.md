---
title: Alfred & Raycast
description: Jump to an IRC channel or private conversation, send a message, and open Catch me up or a Recap from Alfred or Raycast, with Vela's workflow and extension.
---

# Alfred & Raycast

Vela has an **Alfred workflow** and a **Raycast extension**. From either one, jump to a channel or private conversation, see where you're mentioned and what's unread, send a message, and open [Catch me up](/guide/apple-intelligence#catch-me-up) or a [Recap](/guide/recap), without switching to Vela first.

Both need Vela 1.5 or later. They talk to Vela through its [AppleScript dictionary](/guide/automation#applescript) and its [`vela://` links](/guide/automation#links), on your Mac. Neither ever opens Vela just to list things: if Vela isn't running, they say so and offer to open it.

## Alfred {#alfred}

### Install the workflow {#alfred-install}

You need **Alfred 5 or later** with the Powerpack, which workflows need.

1. Download **Vela.alfredworkflow** from the [latest release](https://github.com/r3volution11/Vela-IRC/releases/latest), and double-click it.
2. Alfred shows the workflow's settings. The defaults are fine: the keywords `vela` and `vsearch`, and **Vela** as the app. Click **Import**.
3. Type `vela` in Alfred. The first time, macOS asks whether Alfred may control Vela: click **Allow** (see [Permissions](#permissions)).

To change a keyword later, open **Alfred Preferences → Workflows**, select **Vela** and click **Configure Workflow…**.

### Keywords {#alfred-keywords}

| Type | To |
| --- | --- |
| `vela` | List your channels and private conversations: mentions first, then what's unread, then the rest. Type to filter by name or network. |
| `vela unread` | Only the ones with something unread (`vela mentions` for mentions). |
| `vela catch` | **Catch Me Up**: open Catch me up for the unmuted conversation with the most unread messages. |
| `vela recap` | **Open Recap**: a Recap of every network since you last read. |
| `vela mark` | **Mark All Read**: mark every channel and conversation read. |
| `vsearch` *words* | Open [message search](/guide/automation#message-search) in Vela on the words. |

Select text anywhere, open Alfred's Universal Actions, and choose **Search in Vela** to search your messages for it.

Each result shows the channel's or person's name, its network, and how many mentions and unread messages it has, and says when it's muted or a channel you've left. A channel has a **#** icon and a private conversation a person; a red dot means it mentions you, and a channel you've left is dimmed.

### Modifiers {#alfred-modifiers}

| Press | On a conversation |
| --- | --- |
| <kbd>↩</kbd> | Shows it in Vela. |
| <kbd>⌘↩</kbd> | Opens it with its Catch me up card. |
| <kbd>⌥↩</kbd> | Opens a Recap of it, since your first unread message. |
| <kbd>⌃↩</kbd> | Writes a message to it: type the message, then <kbd>↩</kbd> sends it, or <kbd>⌘↩</kbd> puts it in Vela's message box instead, without sending it. Not for a channel you've left. |
| <kbd>⇧↩</kbd> | Marks it read. |
| <kbd>⌘C</kbd> | Copies its `vela://` link. |

Hold a modifier to see what it will do in the result's subtitle. Messages are sent as the message box sends them: as plain text (a message starting with `/` is sent as it is, never run as a command), split and paced like everything you send. Alfred posts a notification saying what was sent or marked read, or what went wrong.

## Raycast {#raycast}

### Install the extension {#raycast-install}

The extension isn't in the Raycast Store yet. Until it is, you can add it from Vela's source code, with [Node.js](https://nodejs.org) 22 or later:

```sh
git clone https://github.com/r3volution11/Vela-IRC.git
cd Vela-IRC/integrations/raycast
npm install
npm run dev
```

Raycast adds the extension as a development extension, and keeps it after you stop `npm run dev` (with <kbd>⌃C</kbd>).

### Commands {#raycast-commands}

| Command | What it does |
| --- | --- |
| **Search Conversations** | Every channel and private conversation, in three sections: **Mentions**, **Unread** and **All**. Each row shows its network, the unread count, mentions as a red `@` tag, and whether it's muted or a channel you've left. Type to filter by name or network. |
| **Send Message** | Pick a channel you're in or a private conversation (mentions and unread ones first), and send a message. |
| **Catch Me Up** | Opens Catch me up for the unmuted conversation with the most unread messages, or says you're all caught up. |
| **Unread Conversations** | A menu bar command, off until you turn it on in **Raycast Settings → Extensions → Vela**. It shows how many mentions you have, with the conversations that have something unread in its menu. It reads Vela every 5 minutes and when you open its menu, and never while Vela isn't running. |

### Actions in Search Conversations {#raycast-actions}

| Action | Shortcut | What it does |
| --- | --- | --- |
| **Open in Vela** | <kbd>↩</kbd> | Shows the conversation in Vela. |
| **Write Message** | <kbd>⌘↩</kbd> | A form to write a message and send it. Not for a channel you've left. |
| **Catch Me Up** | <kbd>⌘U</kbd> | Opens it with its Catch me up card. |
| **Open Recap** | <kbd>⇧⌘R</kbd> | Opens a Recap of it, since your first unread message. |
| **Draft in Vela** | <kbd>⇧⌘D</kbd> | A form whose text goes into Vela's message box; you press <kbd>Return</kbd> in Vela to send it. |
| **Mark Read** | <kbd>⇧⌘U</kbd> | Marks it read, when something's unread. |
| **Mark All Read** | <kbd>⌥⇧⌘U</kbd> | Marks every channel and conversation read. |
| **Copy Link** | <kbd>⇧⌘C</kbd> | Copies its `vela://` link, for your notes or a Raycast quicklink. |
| **Reload** | <kbd>⌘R</kbd> | Reads your conversations again. |

In the message forms, <kbd>⌘↩</kbd> sends and <kbd>⇧⌘↩</kbd> puts the text in Vela's message box instead (the other way round in **Draft in Vela**). More than 3 lines asks first: tick **Send all *N* lines**. Vela sends at most 50 IRC messages at once.

## Permissions {#permissions}

The first time Alfred or Raycast asks Vela for something, macOS asks: "“Alfred” wants access to control “Vela”." Click **Allow**. That's once for each app.

If you clicked **Don't Allow**, the workflow and the extension say so and offer to open the settings: in **System Settings → Privacy & Security → Automation**, turn on **Vela** under **Alfred** or **Raycast**.

Showing a conversation from Raycast, copying a link, and searching from Alfred use `vela://` links, which need no permission. Listing conversations, sending, Catch me up, Recap and marking read need it. See [What links can't do](/guide/automation#link-safety) for why.

## Vela Dev {#vela-dev}

If you work on Vela, both can talk to **Vela Dev**, the development build, instead of the Vela you use every day:

- **Alfred:** in the workflow's settings (**Configure Workflow…**), set **App** to **Vela Dev**.
- **Raycast:** in **Raycast Settings → Extensions → Vela**, set **App** to **Vela Dev**.

They then use Vela Dev's bundle id (`io.github.r3volution11.Vela.dev`) and its `vela-dev://` links. macOS asks for permission again, since Vela Dev is a separate app.

## Troubleshooting {#troubleshooting}

- **"Vela isn't running."** Neither opens Vela just to list your conversations. Press <kbd>↩</kbd> (Alfred) or choose **Open Vela** (Raycast), then try again.
- **"Alfred isn't allowed to control Vela"** (or Raycast). See [Permissions](#permissions).
- **"Vela didn't answer."** macOS may be waiting for you to answer its permission question, sometimes behind other windows. Click **Allow**, then try again.
- **"Vela is still starting."** Vela was just opened and is restoring your networks. Alfred asks again every second; in Raycast, press <kbd>⌘R</kbd> in a moment.
- **"This Vela can't talk to Alfred yet"** or **"Update Vela."** The workflow and the extension need Vela 1.5 or later. Choose **Vela → Check for Updates…**.
- **"You're not in #vela" or "You're not connected."** Messages go only to channels you're in and networks you're connected to. Join or reconnect in Vela, or put the text in the message box instead (<kbd>⌘↩</kbd> in Alfred, **Draft in Vela** in Raycast).
- **Catch me up or Recap says it's turned off, or that Apple Intelligence isn't available.** Turn it on in **Settings → Intelligence**, and see [Apple Intelligence](/guide/apple-intelligence#requirements) or [your own AI models](/guide/ai-models).
- **Counts look out of date.** Alfred shows the list it saw last at once, then reads it again if it's more than 5 seconds old. In Raycast, press <kbd>⌘R</kbd>.
- **No notification from Alfred.** Check that Alfred may post notifications in **System Settings → Notifications**.
- **The wrong Vela answers.** Check the **App** setting ([Vela Dev](#vela-dev)).

## Privacy {#privacy}

The workflow and the extension have no analytics or tracking of any kind. They run on your Mac and talk only to Vela: they read your conversations' names, networks and counts (never your messages), and the only thing that leaves your Mac is a message you send, which Vela sends to your IRC network. Their source is in Vela's repository, in [`integrations/alfred`](https://github.com/r3volution11/Vela-IRC/tree/main/integrations/alfred) and [`integrations/raycast`](https://github.com/r3volution11/Vela-IRC/tree/main/integrations/raycast).
