---
title: Integrations
description: Settings → Integrations lists what works with Vela, from Alfred and Raycast to Siri, Shortcuts, Spotlight, AppleScript and vela:// links, with what each needs and how to set it up.
---

# Integrations

**Settings → Integrations** (<kbd>⌘,</kbd>) lists the tools that work with Vela: Alfred, Raycast, Shortcuts and Siri, Spotlight, and AppleScript and `vela://` links. Each one shows its icon, what it does, whether it's installed on your Mac, buttons to set it up, and **Learn more**, which opens its guide here.

Everything on this pane runs on your Mac. Vela checks which apps are installed when you open the pane and when you come back to Vela, and only asks macOS, so it never sends anything anywhere.

<!-- Screenshot to come: Settings → Integrations (website/scripts/screenshots.sh shoots settings-integrations). -->

You can also open the pane from the [command palette](/guide/command-palette): **Settings: Integrations**.

## Alfred {#alfred}

Vela's [Alfred workflow](/guide/alfred-and-raycast#alfred) comes with the app. Type `vela` in Alfred to jump to a channel or private conversation, send a message, or open Catch me up or a Recap. It needs **Alfred 5 or later** with the Powerpack.

- **Install Workflow…** opens the workflow in Alfred. Alfred shows its own sheet with the workflow's settings: click **Import**. If you already have it, Alfred offers to update it. The command palette's **Integrations: Install Alfred Workflow…** does the same.
- The status line says which Alfred you have and which version of the workflow comes with this Vela. With two versions of Alfred installed, Vela uses the one that's running.
- **Get Alfred** opens [alfredapp.com](https://www.alfredapp.com) when Alfred isn't installed, or is older than Alfred 5.
- **Source code** opens the workflow's repository, [vela-alfred-workflow](https://github.com/r3volution11/vela-alfred-workflow), where every release of it is published too.

## Raycast {#raycast}

Vela's [Raycast extension](/guide/alfred-and-raycast#raycast) searches your conversations, sends messages, catches you up and can show your mentions in the menu bar. Raycast installs extensions only from the Raycast Store.

- **It's coming to the Raycast Store.** Until it's there, the card says so, and **View on GitHub** opens the extension's [source code](https://github.com/r3volution11/vela-raycast-extension), which says how to add it with Node.js. See [Install the extension](/guide/alfred-and-raycast#raycast-install).
- Once it's in the Store, **Open in Raycast Store** shows it in Raycast, where you install it with one click, or opens its Store page in your browser if you don't have Raycast. The palette then has **Integrations: Open in Raycast Store** too.
- **Get Raycast** opens [raycast.com](https://www.raycast.com) when Raycast isn't installed.

## Shortcuts and Siri {#shortcuts-and-siri}

Siri and the Shortcuts app work with Vela without any setup. The card lists a few things to ask Siri and every action Vela adds to Shortcuts, and **Open Shortcuts** opens the Shortcuts app, where Vela's actions are under **Apps**. See [Siri, Shortcuts & Spotlight](/guide/siri-shortcuts).

## Spotlight {#spotlight}

Spotlight finds your channels and the people you talk to in private, runs Vela's actions, and offers **Search in Vela** to search your messages. The card has Vela's two Spotlight settings:

- **Show channels in Spotlight** ([`intelligence.spotlightChannels`](/reference/settings#intelligence.spotlightChannels)), on by default: channel names and the people you talk to in Spotlight's results. Names only, never messages.
- **Search messages in Spotlight** ([`intelligence.spotlightMessages`](/reference/settings#intelligence.spotlightMessages)), off by default: lets Spotlight search your saved messages. It needs **Save message history**, so it's dimmed until that's on.

See [Spotlight](/guide/siri-shortcuts#spotlight) and [Messages in Spotlight](/guide/siri-shortcuts#messages-in-spotlight).

## AppleScript and links {#applescript-and-links}

Scripts can read your networks and conversations and act on them, and `vela://` links open things in Vela. See [Links & AppleScript](/guide/automation).

- **Open Dictionary** opens Vela's AppleScript dictionary in Script Editor, where you can browse every term.
- **Scripting version** is the dictionary's version, which scripts can read as `scripting version`. It only goes up when a change could break scripts, the Alfred workflow or the Raycast extension.
- **Links to try** shows a few `vela://` links, with a button to copy each: show #vela on Libera.Chat, put text in its message box, open a Recap of today and search your messages. [Vela Dev](/guide/automation#links) shows its own `vela-dev://` links.

## Privacy {#privacy}

Nothing on this pane sends anything anywhere. Checking whether Alfred, Raycast or Script Editor is installed only asks macOS. **Learn more**, **Get Alfred**, **Get Raycast**, **Source code** and **View on GitHub** open web pages in your browser. The Alfred workflow and the Raycast extension have no tracking of any kind; see [their privacy](/guide/alfred-and-raycast#privacy).
