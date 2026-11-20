---
title: Sending messages
description: Vela's message field, with Tab completion, history and drafts, replies, paste confirmation, slash commands, and IRC-safe spelling, autocorrect and Writing Tools.
---

# Sending messages

Type in the message field at the bottom of the window and press **Return** to send. Press <kbd>⌘L</kbd> to jump to the field from anywhere.

| Key | Does |
| --- | --- |
| <kbd>Return</kbd> | Send |
| <kbd>⇧Return</kbd> or <kbd>⌥Return</kbd> | New line |
| <kbd>Tab</kbd> | Complete the word before the cursor; press again for the next match |
| <kbd>↑</kbd> / <kbd>↓</kbd> | Previous / next message you sent here |
| <kbd>Esc</kbd> | Cancel a reply or a pending paste; with nothing to cancel, jump to the newest message |
| <kbd>Page Up</kbd> / <kbd>Page Down</kbd> | Scroll the messages a page, keeping a line or two of the last page in view |
| <kbd>Home</kbd> / <kbd>End</kbd> | Scroll to the oldest message loaded / back to the newest |

So you can read back without leaving the field: what you've typed stays put, and so does the cursor. On a laptop keyboard, <kbd>fn↑</kbd> and <kbd>fn↓</kbd> are Page Up and Page Down, and <kbd>fn←</kbd> and <kbd>fn→</kbd> are Home and End. To pick a message and act on it, press <kbd>⌥⌘2</kbd>; see [The messages](/reference/keyboard-shortcuts#the-messages).

The field grows as you type, up to eight lines, then scrolls. IRC limits how long a single message can be, so long or multi-line text is sent as several messages; a small "2 messages" label tells you before you send.

The field has a quiet border that stays the same while you type. To remove it, change its color, or have it turn the accent color while you type, see [Message box border](/customize/themes#message-box-border).

## Tab completion

Press <kbd>Tab</kbd> after typing the start of a word:

- **Nicknames.** People who spoke most recently come first. At the start of a line Vela adds `: ` (`wren: `), the IRC way of addressing someone. A leading `@`, a habit from [Slack](https://slack.com) and [Discord](https://discord.com), is dropped.
- **Channels.** Words starting with `#` complete channels on this network, joined ones first.
- **Commands.** `/jo` at the start of a line completes to `/join `.
- **Emoji.** `:thu` completes to 👍. Typing a whole shortcode such as `:tada:` turns it into 🎉 as you type. Vela knows the common Slack, GitHub and Discord names.

Press <kbd>Tab</kbd> again to cycle through the other matches.

## History and drafts

<kbd>↑</kbd> on the first line brings back the messages you've sent in this channel, newest first, and <kbd>↓</kbd> walks forward again to what you were typing. History lasts until you quit Vela.

Unsent text is kept per channel, so you can switch away mid-sentence and pick up where you left off.

## Replies

Hover a message and click the **reply** arrow (or right-click it and choose **Reply**). From the keyboard, press <kbd>⌥⌘2</kbd>, pick the message with <kbd>↑</kbd> and <kbd>↓</kbd>, and press <kbd>R</kbd>. A bar above the field shows who you're replying to; press <kbd>Esc</kbd> or click **×** to cancel.

Replies need server support (IRCv3 message tags). On servers without it, the bar says **sent as a normal message**. See [Reactions, replies & typing](/guide/reactions-replies-typing).

## Pasting several lines

On IRC, every line is a separate message, and pasting a wall of text can flood a channel (or get you kicked). When you paste more than three lines, Vela asks first: **Send 12 lines to #channel?**

- **Send** (or <kbd>Return</kbd>) sends them all.
- **Edit** puts the text in the field so you can trim it.
- **Cancel** (or <kbd>Esc</kbd>) discards the paste.

Pasted text is always sent as-is, even if a line starts with `/`.

## Slash commands

Messages that start with `/` are commands: `/me waves`, `/join #vela`, `/msg nick hi`, `/topic …` and many more. See the full list in [Slash commands](/reference/slash-commands). To send a message that starts with a slash, type two: `//shrug` sends `/shrug`.

Commands Vela doesn't know are sent to the server as typed, so commands like `/list`, `/motd` or `/names` work too.

## When you can't send

If you're offline, or you've left the channel, the field says so (**Offline — reconnect to send** or **Not in channel — /join to rejoin**) and shows a **Reconnect** or **Join** button. Commands still work.

## Typing options {#typing}

<Screenshot src="/screenshots/settings-typing.webp" alt="Settings → Messages → Typing: switches for spelling, grammar, autocorrect, text replacements, smart quotes and dashes, Writing Tools and typing indicators, some marked Same as macOS, followed by the Memory and History sections" caption="Settings → Messages → Typing." />

macOS can check and correct what you type in the message field, as it does in Mail or Notes, and Vela makes sure it never breaks IRC. The switches are in **Settings → Messages → Typing**:

| Setting | What it does | Default |
| --- | --- | --- |
| **Check spelling while typing** | Underlines misspelled words. | On |
| **Check grammar** | Underlines grammar mistakes too. It never changes anything for you. | Off |
| **Correct spelling automatically** | Fixes misspelled words as you type. | Same as macOS |
| **Use text replacements** | Expands the text replacements you set up in macOS. **Edit Text Replacements…** opens them in System Settings → Keyboard. | Same as macOS |
| **Smart quotes and dashes** | Uses curly quotes, and turns double hyphens into dashes. | Same as macOS |
| **Writing Tools** | Lets Apple Intelligence proofread and rewrite your message. See [below](#writing-tools). | On |
| **Send typing indicators** | Lets others see when you're typing, on servers that [support it](/guide/reactions-replies-typing#typing-indicators). | On |

### Following macOS {#following-macos}

Autocorrect, text replacements, and smart quotes and dashes start out following your Mac's settings in **System Settings → Keyboard → Text Input**, and change as soon as you change them there. Under each of these switches, **Same as macOS** tells you it's following.

Change one in Vela and it stays the way you set it, whatever macOS does. A **Use macOS Setting** button appears under it to go back to following macOS.

While **Smart quotes and dashes** follows macOS, quotes and dashes each follow their own macOS switch. Once you set it in Vela, it turns both on or off.

### The Edit menu {#edit-menu}

The same switches are in **Edit → Spelling and Grammar** (**Check Spelling While Typing**, **Check Grammar With Spelling**, **Correct Spelling Automatically**) and **Edit → Substitutions** (**Smart Quotes**, **Smart Dashes**, **Text Replacement**), and in the **Spelling and Grammar** and **Substitutions** submenus when you right-click the message field. Whichever you use:

- **The change is saved to your settings,** so it applies in every channel and is still set the next time you open Vela.
- **It's always an explicit on or off.** To follow macOS again, click **Use macOS Setting** in **Settings → Messages → Typing**.
- **Smart Quotes and Smart Dashes share one setting,** so switching either one switches both.

The Edit menu also has **Show Spelling and Grammar** (<kbd>⌘:</kbd>), **Check Document Now** (<kbd>⌘;</kbd>) and **Show Substitutions**. In the [command palette](/guide/command-palette), type "typing" for **Typing: Check Spelling While Typing**, **Check Grammar**, **Correct Spelling Automatically**, **Use Text Replacements**, **Use Smart Quotes and Dashes** and **Use Writing Tools**.

### What's never corrected {#irc-safe}

Autocorrect, text replacements, smart quotes and dashes, and Writing Tools leave the parts of a message that IRC depends on exactly as you typed them:

- **The command** at the start of a line, such as `/join`. A line that starts with `//` is ordinary text.
- **Who a message goes to** in `/msg`, `/notice` and `/query`, the channel you name in `/topic` and `/part`, and **everything after other commands**, such as `/join`, `/mode` and `/kick`.
- **Links, `#channels`, the nicks of people in the conversation**, and `nick:` at the start of a line.
- **`:emoji:` codes** and `` `code` ``.

What you write after `/me`, `/say`, `/msg`, `/notice`, `/away`, `/topic`, `/part` and `/quit` is a message, so it's checked like one.

Nicks, commands, channel names, links and code aren't underlined as misspelled, either. And text Vela puts in the field for you, such as a message from history (<kbd>↑</kbd>), a Tab completion or a draft, is never autocorrected.

### Writing Tools {#writing-tools}

With [Apple Intelligence](/guide/apple-intelligence#requirements) turned on, right-click in the message field and choose **Writing Tools** to proofread or rewrite your message. It opens in Apple's Writing Tools panel rather than rewriting the text in place. While it works:

- <kbd>Return</kbd> doesn't send and <kbd>Tab</kbd> doesn't complete.
- Typing indicators and `:emoji:` replacement pause.

Its changes are a single undo step, so <kbd>⌘Z</kbd> puts your message back the way it was. When Apple Intelligence isn't available, the **Writing Tools** setting says why.

### Good to know

- **Grammar checking only underlines.** Right-click an underlined word for suggestions.
- **Return sends exactly what you typed.** It doesn't autocorrect the last word first.
- **Perform on connect** commands in the [network editor](/guide/adding-a-network#perform-on-connect) are never checked or corrected.
- All of these are keys in [settings.json](/reference/settings#input): [`input.spellCheck`](/reference/settings#input.spellCheck), [`input.grammarCheck`](/reference/settings#input.grammarCheck), [`input.autocorrect`](/reference/settings#input.autocorrect), [`input.textReplacements`](/reference/settings#input.textReplacements), [`input.smartPunctuation`](/reference/settings#input.smartPunctuation), [`input.writingTools`](/reference/settings#input.writingTools) and [`input.sendTypingIndicators`](/reference/settings#input.sendTypingIndicators). The three that can follow macOS take `true`, `false`, or `"system"` to follow it (the same as leaving them out).
