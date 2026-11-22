---
title: Recap
description: A report of what was said in an IRC channel, on a network or everywhere, by anyone or one person, over any span, written by Apple Intelligence on your Mac or shown as a log.
---

# Recap

A **Recap** is a report of what was said while you were away, in a window of its own. It covers a channel, a whole network or every network, for anyone or one person, since your first unread message or over a span you pick. Apple Intelligence writes it on your Mac (or [a model of your own](/guide/ai-models)), as short as it can be: an overview, the topics, what was for you, what was decided and who said they'd do what, and the links people shared. Each item links to its message, and **More detail** looks closer at any of them.

[Catch me up](/guide/apple-intelligence#catch-me-up) is the quick version: a small card for one channel's unread messages. A Recap is for when there's more to catch up on, or you want to look back on purpose.

<Screenshot src="/screenshots/recap-palenight.webp" alt="A Recap window in the Palenight theme: “Recap of Libera.Chat”, a bar with Who, Where and When and a Summary or Log switch, then an Overview of short bullets and Topics, each with who took part, a link to where it starts and More detail" caption="A Recap of a network, in Palenight." />

## Open a Recap {#open}

- **Go → Recap…** (<kbd>⇧⌘R</kbd>) recaps the channel or conversation you're in. From a network's console, it recaps the whole network.
- **Right-click** a channel or conversation in the sidebar, the rail or the tabs and choose **Recap…**, or a network and choose **Recap Network…**.
- **Right-click a person** in the member list, or a nick in a message, and choose **Recap Conversations with alice…**.
- In the [command palette](/guide/command-palette) (<kbd>⇧⌘P</kbd>): **Buffer: Recap…**, **Buffer: Recap Conversations with…** (it asks who), **Network: Recap Libera.Chat…** and **Network: Recap All Networks…**.
- On a [Catch me up card](/guide/apple-intelligence#catch-me-up), click **Open Full Recap**.
- Ask Siri: "Recap #vela in Vela", "Recap today in Vela" or "Open a recap in Vela". See [Siri, Shortcuts & Spotlight](/guide/siri-shortcuts).

You can have several Recaps open at once. Opening the same Recap again brings its window to the front.

## What it covers {#scope}

The bar under the title says what the Recap covers. Change any of it and the Recap reads the messages again.

- **Who:** **Anyone**, or one person. A person's Recap has their messages, messages that name them or reply to them, and your private conversation with them. Pick from the people who spoke or are in the channel, or type a nick.
- **Where:** the channel or conversation you opened it for, one network, or **All Networks**. Choosing a person in a channel widens it to the network, so your private conversation with them is included; choose the channel again to narrow it.
- **When:** **Since Your First Unread** to start with: each channel from its own **New** line, so you see what you missed and nothing you've read. Or pick a span: the last 30 minutes, hour, 4 hours, **Today**, the last day, 3 days or week, or **Custom…** for any number of minutes, hours or days.

**With nothing unread, the Recap asks how far back to go**, with the same spans as buttons.

**A Recap reads what Vela has.** With **Save message history** off (the default for new installs), that's what arrived while Vela was open, plus what your [bouncer](/guide/bouncers) or server replayed. With it on, a Recap also reads your saved history for the span. When the span reaches back before Vela was open (or before the oldest messages it kept in memory) and nothing saved covers it, the Recap says how far back it goes, such as "Vela has #vela back to 2:14 PM." See [Scrollback and history](/guide/messages-and-layouts#scrollback-and-history).

## Summary or Log {#output}

The switch at the right of the bar shows the Recap two ways.

**Summary** is Apple Intelligence's report, in sections:

- **Overview:** a few short bullets on the whole stretch, the most important first.
- **Topics:** each subject people talked about, with a sentence or two on what was said or decided, who took part, and a link to where it starts.
- **For you:** messages that named you, and private messages, with what they asked of you. **No reply yet** marks a question or request you haven't answered: you didn't reply to it, name them afterwards, write back in the private conversation, or say anything in that channel within half an hour of it.
- **Decisions and follow-ups:** what was **Decided**, **Open questions** left unanswered, and **Follow-ups**: who said they'd do what.
- **Links shared:** videos, images, sites with several links, and other pages, with who shared each one and when. Titles come from link previews Vela has already loaded; nothing is fetched for a Recap.

**For you** and **Links shared** are found on your Mac, so they show at once. The rest fills in as Apple Intelligence writes it: "Reading 340 of 1,200 messages", then "Writing the Recap…". A long stretch is read in parts, and each part's topics show as **Topics so far** until they're combined.

**Log** shows every matching message as it was written, by conversation and day, in nick colors. It doesn't use Apple Intelligence, so it works on any Mac, and right away. While Apple Intelligence is off or not available, **Summary** is dimmed and says why.

## Go to the messages {#jump}

Every topic, note and link has a time link, such as **2:14 PM in #vela ↗**. Click it and the main window shows that channel, scrolls to the message and highlights it, loading older saved history first if it needs to. In a log, hover a message and click its arrow, or double-click it.

## More detail {#more-detail}

Click **More detail** under a topic, a decision, an open question or a follow-up. Apple Intelligence reads just the messages behind it and writes a few more points, in order: what was said, by whom, and what was decided or left open. It's one short pass, so it's quick. **Less detail** hides them again.

**More detail** is ready once the Recap is written.

## Copy and save {#copy-and-save}

The buttons at the top of the window:

| Button | Shortcut | What it does |
| --- | --- | --- |
| **Stop** | <kbd>⌘.</kbd> | Stops writing. What's written stays. |
| **Regenerate** | <kbd>⌘R</kbd> | Reads the messages again, new ones included, and writes a new Recap. |
| **Copy as Markdown** | | Copies the Recap (or the log) as Markdown, with any **More detail** you opened. |
| **Save as Markdown…** | <kbd>⌘S</kbd> | Saves the same as a `.md` file, wherever you choose. |

## How long it takes {#limits}

- **Up to the latest 2,000 messages are summarized.** That's a few minutes of work on a base M1. For a bigger stretch, the Recap says how many it left out; narrow it to a channel, a person or a shorter span to cover the rest.
- **Up to 10,000 messages are gathered,** the newest, for the log and for **For you** and **Links shared**.
- **A long Recap asks first,** such as "About 2 minutes on this Mac." Click **Start**, or **Show Log** to read the messages instead. The estimate gets better as Vela learns how fast your Mac is.
- **You can keep using Vela meanwhile.** A Recap runs at low priority, and you can **Stop** it any time.
- **One summary at a time.** Recaps, More detail and Catch me up take turns with Apple Intelligence, so a Mac with 8 GB of memory never runs two at once. A Recap waiting its turn says "Waiting for another summary to finish…".
- **Long lines are cut,** and links are reduced to the site they point to, as for Catch me up.
- **A part Apple Intelligence won't summarize is skipped,** and the Recap says how many messages it left out, instead of failing.
- **[Private Cloud Compute](/guide/apple-intelligence#private-cloud-compute) comes in a later version.** When it does, a long Recap will be able to use it, as a long catch-up will.

::: warning Recaps can contain mistakes
A summary can misread a conversation or leave out something that matters. Click through to the messages before you act on something.
:::

## What's sent, and what's kept {#privacy}

- **Apple Intelligence reads the messages and your nick,** so it can say what was asked of "you". It isn't told any channel's or network's name, or who the Recap is about. Several conversations are told apart by number only.
- **It runs on your Mac,** on the Apple Intelligence model that macOS keeps there.
- **Nothing is saved.** A Recap lives in its window: closing the window stops it and forgets it. Copy and Save as Markdown are the only ways to keep one.
- **A log uses no Apple Intelligence at all.**

See [Privacy](/help/privacy) for everything else.

## Turn it off {#settings}

**A model of your own.** Recap uses the **Default model** in **Settings → Intelligence → Models**, or the **Model** in its own section. The footer of a finished Recap says which model wrote it, and **Change Model** writes it again with another; **More detail** asks the same model. **Buffer: Recap With…** in the command palette picks the model first. A model of your own reads far more at once than the one on your Mac, so a long Recap usually takes one pass. See [Your own AI models](/guide/ai-models).

**Offer Recap** in **Settings → Intelligence → Recap** turns Recap off everywhere: the Go menu item, the right-click items, the palette commands, the card's **Open Full Recap** and Siri. In settings.json it's [`intelligence.recap`](/reference/settings#intelligence.recap).

<Screenshot src="/screenshots/recap-lighter.webp" alt="A Recap of #vela in the Lighter theme: Topics, with More detail open on the first one, then For you, where wren asked you to review the sidebar rail PR" caption="A Recap of #vela in Lighter, with More detail on a topic." />
