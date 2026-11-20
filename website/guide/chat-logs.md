---
title: Chat logs
description: Save plain-text logs of your channels and conversations, one folder per network, with a size limit. What's in them, where they go, how files rotate, and how to leave a channel out.
---

# Chat logs

Vela can keep a plain-text copy of your channels and private conversations: one folder for each network, with a file for each channel or conversation. Logs hold what people wrote, the way they wrote it, so you can search them, keep them or open them in any text editor.

Chat logs are **off by default**. They're separate from Vela's [message history](/guide/messages-and-layouts#scrollback-and-history) (**Save message history**), which is what Vela shows when you scroll up and is off by default too. Logs are a copy for you, in files you own; Vela writes them whether or not it saves history, and never loads them back.

## Turning logs on

Open **Settings → Messages**, scroll to **Chat logs** and turn on **Save chat logs**. Vela starts logging straight away, from the next line in each channel.

<Screenshot src="/screenshots/settings-chat-logs.webp" alt="Settings → Messages: the Chat logs section, with Save chat logs on, the folder set to Vela's folder with Choose… and Reveal in Finder buttons, Start a new file at 10 MB (recommended), Files to keep 5 files (recommended), Include channel events on and Include server messages off" caption="The Chat logs section of Settings → Messages." />

You can also run **Chat: Save Chat Logs** from the [command palette](/guide/command-palette), or set [`logging.enabled`](/reference/settings#logging.enabled) in settings.json.

## Where logs go

By default, logs go in a `Logs` folder inside Vela's data folder:

```text
~/Library/Containers/io.github.r3volution11.Vela/Data/Library/Application Support/Vela/Logs/
```

To use another folder, such as one in Documents or on an external disk, click **Choose…** next to **Folder**. Vela remembers the folder you choose, and keeps permission to use it across restarts. **Use Vela's Folder** goes back to the default. Logs already written stay where they are; Vela doesn't move them.

To open the folder, click **Reveal in Finder**, choose **File → Show Chat Logs**, or run **Chat: Show Chat Logs** from the command palette.

If the folder you chose isn't available when Vela starts (it was deleted or moved, or it's on a disk that isn't connected), Vela saves logs in its own folder instead and says so in Settings. Connect the disk and restart Vela, or click **Choose…** to pick the folder again.

## How logs are organized

Each network gets a folder named after it. Inside, each channel and private conversation has a file named after it, and full files are renamed with the dates they cover:

```text
Logs/
  Libera.Chat/
    #vela.log
    #vela 2026-10-02 – 2026-11-01.log
    #swift.log
    alice.log
    server.log
  OFTC/
    #debian.log
```

- **Names stay as you see them.** The few characters a Mac can't use in a file name, `/` and `:`, become `_`. A channel keeps one file whatever case its name arrives in: `#Vela` and `#vela` share `#Vela.log` or `#vela.log`, whichever came first.
- **Renaming a network** in its settings renames its folder too. Two networks with the same name get `Libera.Chat` and `Libera.Chat (2)`, and each keeps its folder.
- **Bouncer networks** each get their own folder, named after the network on the bouncer.
- **Server messages** go in `server.log` when **Include server messages** is on. A private conversation with someone called "server" is logged as `server (query).log`.

## What a log looks like

Logs are UTF-8 text with one line per message or event, each starting with its date and time on your Mac's clock:

```text
--- Log opened 2026-11-17 21:04:01 ---
[2026-11-17 21:04:01] -!- doug (doug@example.org) joined #vela
[2026-11-17 21:04:01] -!- Topic: Vela, a native IRC client for macOS
[2026-11-17 21:04:05] <alice> hi doug, the docs are at https://velairc.app
[2026-11-17 21:04:09] * doug waves
[2026-11-17 21:04:12] -ChanServ- Welcome to #vela
[2026-11-17 21:05:30] -!- bob deleted a message from alice sent at 2026-11-17 21:04:05 (wrong channel)
[2026-11-17 21:06:00] -!- alice quit (Ping timeout)
--- Log closed 2026-11-17 23:10:00 ---
```

| Line | Means |
| --- | --- |
| `<nick> text` | A message, yours included |
| `* nick text` | An action (`/me`) |
| `-nick- text` | A notice |
| `-!- text` | An event: a join, part, quit, nick change, kick, topic or mode change, or a deleted message |
| `--- Log opened …` | Vela started writing to this file: it opened, logging was turned on, or this is a new file |
| `--- Log closed …` | Vela stopped writing to it: it quit, logging was turned off, the folder changed, or the file was full |

## What's in a log, and what isn't

Logs hold **only what was written**:

- Messages, actions and notices, from everyone, you included.
- Links exactly as they were typed.
- Joins, parts and quits (with their reasons), nick changes, kicks (with the reason), topic changes, the topic shown when you join, and mode changes, while **Include channel events** is on (it is by default).
- A network's connection messages, MOTD and notices from services, in `server.log`, if you turn on **Include server messages**.

They never include:

- Link previews, images, GIFs and videos: only the link someone posted.
- Translations, Catch me up summaries, reactions and typing indicators.
- Colors, bold and other mIRC formatting: the text is kept, the formatting codes are removed.
- Vela's own notes in a channel, such as "Disconnected".

**Deleted messages** (on servers with IRCv3 message deletion) stay in the log as they were written. Vela adds a line saying who deleted the message, when it was sent, and why, if a reason was given. Logs are a record; Vela never rewrites them.

**Nothing is logged twice.** When a [bouncer](/guide/bouncers) or the server replays messages after you connect, Vela adds only the ones newer than what the log already had, so what was said while Vela was closed or offline fills in the gap. Messages Vela loads from its own history, at launch or when you scroll up, are never logged again. A new log starts with the first line Vela sees live, so joining a channel doesn't fill its log with what was said before you arrived.

## How big logs get

When a log reaches the size in **Start a new file at**, Vela ends it, renames it with the dates it covers (`#vela 2026-10-02 – 2026-11-01.log`) and starts a new one. **Files to keep** is how many files each channel keeps, counting the current one; when there are more, the oldest are deleted.

**We recommend 10 MB and 5 files**, the defaults. That's months of a busy channel in each file, small enough to open quickly in any editor, and at most about 50 MB per channel. Choose **Keep all** to never delete old files.

A new size applies from the next line Vela writes; a smaller number of files applies the next time a file fills up. Full files sort by date, and a channel that fills more than one file in a day gets `(2)`, `(3)` and so on.

## Leaving a channel out

To stop logging a channel or conversation, right-click it and choose **Don't Log This Channel** (or **Don't Log This Conversation**). For a whole network, right-click the network and choose **Don't Log on This Network**. These appear while chat logs are on, and choosing one again logs it again. **Buffer: Don't Log This Channel** in the command palette does the same for the channel you're in.

Settings → Messages → **Chat logs** shows how many channels and networks aren't logged, with **Clear** to log them all again. In settings.json they're listed in [`logging.excludedBuffers`](/reference/settings#logging.excludedBuffers).

## Opening logs in other apps

Logs are ordinary text files, so anything that reads text works:

- **TextEdit**, **BBEdit**, **Visual Studio Code** or any other editor. Double-click a `.log` file to open it in **Console**, or right-click it and choose **Open With**.
- **Terminal**: search every log of a network with `grep`, or watch a channel as it's written with `tail -f`:

  ```sh
  cd ~/Library/Containers/io.github.r3volution11.Vela/Data/Library/Application\ Support/Vela/Logs
  grep -ri "release" Libera.Chat/
  tail -f "Libera.Chat/#vela.log"
  ```

Vela writes new lines about once a second, and when it quits.

If Vela can't write a log, for example because the disk is full or it no longer has permission to use the folder, Settings → Messages → **Chat logs** says what went wrong. Lines it couldn't write are left out, and logging carries on once the problem is fixed.

## Privacy

Logs are plain text on your Mac, unencrypted, readable by anything that can read your files. Vela doesn't send them anywhere. Turning off **Save message history**, or deleting saved history, doesn't touch them: turn off **Save chat logs** to stop them. If you choose a folder that syncs, such as one in iCloud Drive or Dropbox, your logs sync with it. Delete a log, or the whole `Logs` folder, whenever you like.

Logs in Vela's folder are removed with Vela's data when you [uninstall](/guide/install#uninstalling) it; logs in a folder you chose stay there.

## Settings

| Setting | What it does |
| --- | --- |
| [`logging.enabled`](/reference/settings#logging.enabled) | Save chat logs. Off by default. |
| [`logging.maxFileSizeMB`](/reference/settings#logging.maxFileSizeMB) | Start a new file at this size, in megabytes. 10 by default. |
| [`logging.keepFiles`](/reference/settings#logging.keepFiles) | Files to keep per channel, the current one included. 5 by default; 0 keeps all. |
| [`logging.includeEvents`](/reference/settings#logging.includeEvents) | Log joins, parts, quits, nick changes, kicks, and topic and mode changes. On by default. |
| [`logging.includeServer`](/reference/settings#logging.includeServer) | Log each network's server messages in `server.log`. Off by default. |
| [`logging.excludedBuffers`](/reference/settings#logging.excludedBuffers) | Channels and networks that aren't logged. |

The folder you choose isn't in settings.json: Vela keeps it, and its permission to use it, on this Mac only.
