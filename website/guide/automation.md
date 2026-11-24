---
title: Links & AppleScript
description: Open channels, drafts, Catch me up, Recap and message search with vela:// links, and script Vela from Alfred, Raycast or the terminal with its AppleScript dictionary.
---

# Links & AppleScript

Vela can be driven from outside the app in two ways:

- **`vela://` links** open things in Vela: a channel, a private conversation, Catch me up, a Recap, message search, or a message box with text filled in. A link only ever *shows* things, so it's safe to put one anywhere: on a web page, in your notes, in an Alfred or Raycast quicklink.
- **The AppleScript dictionary** lets a script read your networks and conversations and act: send a message, join a channel, mark things read, set yourself away. macOS asks you first, once for each app that wants to script Vela.

For Siri, the Shortcuts app and Spotlight, see [Siri, Shortcuts & Spotlight](/guide/siri-shortcuts). Vela's own Alfred workflow and Raycast extension, built on both, are in [Alfred & Raycast](/guide/alfred-and-raycast). **Settings → [Integrations](/guide/integrations)** has all of them, with a few links to try.

## vela:// links {#links}

Open one from the terminal with `open`, from a browser, or from any app that opens links:

```sh
open "vela://open?network=Libera.Chat&channel=%23vela"
```

| Link | What it does |
| --- | --- |
| `vela://` or `vela://show` | Brings Vela to the front. |
| `vela://open?network=Libera.Chat&channel=%23vela` | Shows a channel. |
| `vela://open?network=Libera.Chat&nick=marisol` | Shows your private conversation with someone, starting one if there isn't one yet (as `/query` does: nothing is sent). |
| `vela://open?id=…` | Shows a conversation by its id (the `id` AppleScript gives it). |
| `vela://join?network=Libera.Chat&channel=%23vela` | Shows the channel if you're in it. Otherwise it opens **Join Channel** with the channel filled in, and you click **Join**. |
| `vela://join/%23vela` | The same, on the network you're looking at. Channel names in messages are links like this. |
| `vela://catchup?network=Libera.Chat&channel=%23vela` | Opens the conversation with its [Catch me up](/guide/apple-intelligence#catch-me-up) card. Without a conversation, the unmuted one with the most unread messages; with nothing unread, Vela says you're all caught up. If Catch me up is turned off or can't run, it shows the conversation with a note saying why. |
| `vela://recap?network=Libera.Chat&channel=%23vela&span=today` | Opens a [Recap](/guide/recap). Every parameter is optional: `vela://recap` is every network since your first unread message. |
| `vela://draft?network=Libera.Chat&channel=%23vela&text=Hello%20all` | Puts the text in the conversation's message box. You press <kbd>Return</kbd> to send it. |
| `vela://search?q=release%20notes` | Opens [message search](#message-search) with the words. |

### Parameters

- **`network`**: the network's name as Vela shows it (`Libera.Chat`; capitals don't matter) or its id. Leave it out and Vela looks on the network you're looking at first, then on the others. If the name is on more than one of the others, the link says so and does nothing.
- **`channel`**: `#vela`. Written without its `#`, Vela adds one.
- **`nick`**: someone's nick, for a private conversation. `open` and `draft` start one if there isn't one yet; the others need one that's open.
- **`id`**: a conversation's id, `<network id>/<name in lowercase>`, as AppleScript's `id of conversation` gives it.
- **`span`** (Recap): `unread` (the default), `30m`, `1h`, `4h`, `today`, `1d`, `3d` or `1w`.
- **`person`** (Recap): one person's nick: their messages, messages that name them, and your private conversation with them. With a `channel`, the Recap covers that channel's whole network, so it can include your private conversation.
- **`text`** (draft): up to 4,000 characters. Lines are kept.
- **`q`** (search): the words to find, up to 500 characters. Add `network`, or a `channel` or `nick`, to search only there.

Give each conversation one way only: `channel`, `nick` or `id`. Names, nicks and networks can be up to 200 characters.

Encode what a URL can't hold as it is: `#` as `%23`, a space as `%20`, `&` as `%26`. A `+` is a plus sign, not a space. If you type `#` as it is (`vela://join/#vela`), Vela understands that too.

### What links can't do {#link-safety}

Any web page can open a `vela://` link, so links are limited to showing things:

- **A link never sends a message.** `draft` only fills the message box. It goes after anything you'd already typed there (it never replaces it), and text that starts with `/` is put in as `//…`, so pressing <kbd>Return</kbd> sends it as text rather than running a command. If you're in the middle of typing a command, the text isn't added at all.
- **A link never joins a channel by itself.** `join` opens **Join Channel**, filled in, for you to confirm. (A channel name you click in a message, inside Vela, still joins straight away.)
- **A link never hands anything back** to the page or app that opened it.
- **A link Vela can't follow does nothing** but bring Vela forward with a short note saying why: an unknown channel, a name on several networks, a parameter it doesn't know (such as a tracking tag a site added) or one given twice, or a value that's too long or has control characters in it.
- **The same link opened again within a second is ignored,** so a page can't pile up windows by opening it over and over.

Text from a link loses anything that could hide what you'd be sending: IRC formatting codes, other control characters and direction overrides.

::: tip Vela Dev
Development builds of Vela answer `vela-dev://` links instead, so a `vela://` link always opens the Vela you use every day.
:::

## AppleScript {#applescript}

Vela has an AppleScript dictionary: click **Open Dictionary** in **Settings → Integrations**, or open **Script Editor**, choose **File → Open Dictionary…** and pick Vela, to browse it. Scripts can run from Script Editor, the terminal (`osascript`), the Shortcuts app's **Run AppleScript** action, Alfred workflows and Raycast script commands.

The first time an app sends Vela a command, macOS asks: "“Raycast” wants access to control “Vela”." Click **Allow**. You can change your mind in **System Settings → Privacy & Security → Automation**. Because you're asked, scripts can do things links can't, like sending messages.

### Networks and conversations

```sh
osascript -e 'tell application "Vela" to get name of every network'
# Libera.Chat, OFTC

osascript -e 'tell application "Vela" to get name of every conversation of network "Libera.Chat"'
# #vela, #swift, marisol
```

The **application** has:

| Term | What it is |
| --- | --- |
| `networks` | Your networks, in sidebar order. |
| `conversations` | Every channel and private conversation, in sidebar order. |
| `unread conversations` | The ones with something unread (muted ones only when they mention you). |
| `current conversation` | The channel or private conversation you're looking at, or `missing value` (a network console, or nothing). |
| `scripting version` | The dictionary's version, an integer (now 1). It goes up only when a change could break scripts, the Alfred workflow or the Raycast extension; new terms never change it. |
| `version` | Vela's own version, such as `"1.5.0"`. |

A **network** has `id` (its UUID, which never changes), `name`, `connected` (true or false), `nickname` (your nick there) and its `conversations`.

A **conversation** has:

| Property | What it is |
| --- | --- |
| `id` | Its id, `<network id>/<name in lowercase>`. It never changes, and `vela://open?id=` takes it. |
| `name` | `#vela`, or the other person's nick. |
| `network name`, `network` | Its network, by name and as an object. |
| `kind` | `channel` or `private conversation`. |
| `unread count`, `mention count` | What you haven't read, counted from where you last read, as Siri counts it. In a private conversation every new message is a mention. |
| `joined` | Whether you're in the channel (private conversations always are). |
| `muted`, `topic` | Whether it's muted, and the channel's topic. |

Name a conversation by its name, with or without its `#` (`conversation "#vela"`), by its name on a network (`conversation "#vela" of network "Libera.Chat"`) or by its id (`conversation id "…"`). A name alone means the one on the network you're looking at, or else on the first network in the sidebar that has it, so name the network when you're in channels with the same name on several. AppleScript's own filters work too:

```applescript
tell application "Vela"
    -- What's waiting, as "name (network): count" lines.
    set report to {}
    repeat with c in (get unread conversations)
        set end of report to (name of c) & " (" & (network name of c) & "): " & (unread count of c)
    end repeat
    return report
end tell
```

```sh
osascript -e 'tell application "Vela" to get name of conversations whose mention count > 0'
osascript -e 'tell application "Vela" to get {id, name} of current conversation'
```

### Commands

| Command | What it does |
| --- | --- |
| `show` *conversation* | Brings Vela to the front, showing the conversation. |
| `send message` *text* `to` *conversation* | Sends the text. [More below](#sending). |
| `draft message` *text* `to` *conversation* | Shows the conversation with the text added to its message box, after anything already there, as a [`draft` link](#link-safety) does: up to 4,000 characters, and text that starts with `/` goes in as `//…`. Nothing is sent. |
| `join` *text* [`on` *network*] [`key` *text*] | Joins a channel (adding `#` if you leave it out) without switching to it, and returns it once the server says you're in, or after a few seconds. Without a network: the one you're looking at, or the only one you're connected to. |
| `catch up` [*conversation*] | Brings Vela to the front with the conversation's Catch me up card. Without one, the unmuted conversation with the most unread messages; with nothing unread, it does nothing. |
| `open recap` [*conversation or network*] [`person` *text*] [`span` *span*] | Opens a Recap: the conversation, else the network, else every network. With a `person`, a conversation's Recap covers its whole network. Spans: `since unread` (the default), `last half hour`, `last hour`, `last four hours`, `today`, `last day`, `last three days`, `last week`. |
| `mark read` *conversation* | Marks everything in it read. |
| `mark all read` | Marks every channel and conversation read, and returns how many had something unread. |
| `search` *text* [`on` *conversation or network*] | Brings Vela to the front with message search open on the words. |
| `set away` [*text*] | Marks you away on every network you're connected to, like `/away`, and returns their names. Without text, your away message is "Away". |
| `set back` | Marks you back, like `/back`, and returns the networks' names. |

```sh
osascript -e 'tell application "Vela" to show conversation "#vela" of network "Libera.Chat"'
osascript -e 'tell application "Vela" to draft message "Back in 5" to conversation "#vela"'
osascript -e 'tell application "Vela" to join "#swift" on network "Libera.Chat"'
osascript -e 'tell application "Vela" to catch up conversation "#vela"'
osascript -e 'tell application "Vela" to open recap network "Libera.Chat" person "marisol" span today'
osascript -e 'tell application "Vela" to mark read conversation "#vela"'
osascript -e 'tell application "Vela" to mark all read'
osascript -e 'tell application "Vela" to search "release notes" on network "Libera.Chat"'
osascript -e 'tell application "Vela" to set away "In a meeting"'
osascript -e 'tell application "Vela" to set back'
```

### Sending messages {#sending}

```sh
osascript -e 'tell application "Vela" to send message "Deploy finished ✅" to conversation "#ops" of network "Libera.Chat"'
```

`send message` follows the message box's rules:

- **Plain text only.** Text that starts with `/` is sent as it is; it's never run as a command.
- **Only to a channel you're in, or a private conversation you have open.** It never joins a channel or starts a conversation by itself.
- **Long text is split** into IRC messages the way the message box splits it, and goes out at the network's pace, like everything you send.
- **More than 3 lines needs saying so**, as the message box asks before sending a paste that long: add `allowing multiple lines true`. Blank lines don't count. One command sends at most 50 IRC messages.
- If the network is still connecting (the script just opened Vela, say), Vela waits up to 10 seconds for it.

### Errors

When a command can't do what it's asked, the script gets an error with a message saying why and one of these numbers:

| Number | Meaning |
| --- | --- |
| -1728 | There's no such network or conversation. |
| 1001 | More than one network has that name, you have several networks and didn't say which, or the command was given more than one conversation. |
| 1002 | You're not connected to the network (or to any). |
| 1003 | You're not in that channel. |
| 1004 | There's nothing to send (or search for). |
| 1005 | Too many lines without `allowing multiple lines true`, or more than 50 IRC messages. |
| 1006 | A network console takes commands, not messages. |
| 1007 | Catch me up or Recap is turned off in Settings. |
| 1008 | Apple Intelligence isn't available. |
| 1009 | That isn't a channel name. |
| 1010 | Vela isn't ready yet. Try again in a moment. |

Anything else comes back with AppleScript's usual numbers. A command sent while Vela is still opening waits until your networks and conversations are back, then runs.

```applescript
tell application "Vela"
    try
        send message "hi" to conversation "#vela"
    on error message number code
        if code is 1003 then join "#vela"
    end try
end tell
```

### For Alfred and Raycast {#alfred-raycast}

Vela has its own [Alfred workflow and Raycast extension](/guide/alfred-and-raycast). If you're writing your own, or a script command:

- **Keep ids, not names.** A conversation's `id` never changes, works in `conversation id "…"` and in `vela://open?id=`, and can't be ambiguous.
- **Use links to show, AppleScript to act.** A quicklink like `vela://open?network=Libera.Chat&channel=%23{query}` needs no permission. Sending, joining and reading lists need AppleScript.
- **Asking is cheap.** Reading networks, conversations and their counts goes through what Vela has open, never its database, so a script filter can ask on every keystroke.
- **Check `scripting version`** if you share your script. It's 1 today, and it only goes up when a term your script uses might be renamed, removed or behave differently, so a script can say "Update Vela" or "Update this script" instead of failing halfway.

## Message search {#message-search}

Vela can search your messages. **Go: Search Messages…** in the [command palette](/guide/command-palette) (<kbd>⇧⌘P</kbd>), `vela://search`, AppleScript's `search`, the [Search Messages](/guide/siri-shortcuts#shortcuts) action, Alfred's [`vsearch`](/guide/alfred-and-raycast#alfred-keywords) and Spotlight's [Search in Vela](/guide/siri-shortcuts#spotlight-actions) all open the same search at the top of the window.

- **Type some words.** It finds messages that have all of them (capitals and accents don't matter), in your [saved history](/guide/messages-and-layouts#scrollback-and-history) and in what your open channels and conversations have in memory, newest first, up to 100. Without saved history, it searches what's in memory.
- **Each result** shows who said it and what, then the channel or conversation, the network and when.
- **Move** with <kbd>↑</kbd> <kbd>↓</kbd> (or <kbd>Page Up</kbd> <kbd>Page Down</kbd>), and press <kbd>Return</kbd> or click to show the message in its conversation, loading older history to reach it. <kbd>Esc</kbd> closes the search.
- **A link or a script can search one network or conversation.** The search field then says where, such as "Search messages in #vela".

Network consoles and deleted messages aren't searched. A message whose conversation you've since closed or removed can't be shown; Vela says so.

## Privacy

- Links and scripts run inside Vela, on your Mac. Nothing goes anywhere but the IRC networks you send messages to.
- Links can't send, join, run commands or read anything back. Only apps you've allowed in **Privacy & Security → Automation** can script Vela.
