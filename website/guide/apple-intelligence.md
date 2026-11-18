---
title: Apple Intelligence & translation
description: Catch up on busy IRC channels with on-device Apple Intelligence summaries, translate messages from other languages, and proofread with Writing Tools in Vela.
---

# Apple Intelligence & translation

Vela uses Apple's built-in intelligence to help with busy channels and other languages:

- **[Catch me up](#catch-me-up)** summarizes what you missed in a channel.
- **[Translate](#translate-messages)** shows messages from other languages in yours.
- **[Writing Tools](#writing-tools)** proofreads and rewrites what you type.

Summaries and translations are made on your Mac. Vela doesn't send your conversations to Apple, to a server of its own or anywhere else. See [Privacy](#privacy) for the details.

## What you need {#requirements}

Catch me up and Writing Tools use **Apple Intelligence**, so they need:

- a Mac with Apple silicon;
- Apple Intelligence turned on in **System Settings → Apple Intelligence & Siri**, with its model downloaded (macOS downloads it after you turn Apple Intelligence on);
- a language Apple Intelligence supports.

**Translation doesn't need Apple Intelligence**, so it also works on Macs that can't run it.

## The Settings pane {#settings}

<Screenshot src="/screenshots/settings-intelligence.webp" alt="Settings → Apple Intelligence: a green “Apple Intelligence is on” box, then the Catch me up and Translation sections" caption="Settings → Apple Intelligence." />

**Settings → Apple Intelligence** has a section each for Catch me up, Translation, Writing Tools and [Siri & Shortcuts](/guide/siri-shortcuts). At the top, a box says whether Apple Intelligence is ready:

| Status | What it means |
| --- | --- |
| **Apple Intelligence is on** | Everything's ready. |
| **Apple Intelligence is off** | Click **Open System Settings** and turn it on in **Apple Intelligence & Siri**. |
| **Not available on this Mac** | Apple Intelligence needs a Mac with Apple silicon. Translation still works. |
| **Apple Intelligence is getting ready** | macOS is still downloading the model. Try again in a little while. |
| **Language not supported yet** | Apple Intelligence doesn't support your Mac's language yet. **Open System Settings** takes you there. |

While Apple Intelligence isn't available, the Catch me up settings are dimmed.

## Catch me up

<Screenshot src="/screenshots/ai-catch-up.webp" alt="A Catch me up card under the New marker in #swift: “While you were away · 4 messages”, a one-line overview, a topic with who took part, and a note that it was summarized on this Mac" caption="Catch me up in #swift." />

Come back to a busy channel and a **Catch me up** button appears at the end of the **New** marker, the line that shows where you stopped reading. Click it, and a card opens right there, under the marker:

- **An overview** of what happened, written as you watch.
- **Topics**, each with a title, who took part and a one-line summary. Click a topic to jump to its first message, which is briefly highlighted.
- **You were mentioned**, when people said something to you.

The buttons at the top of the card copy the summary (**Copy Summary**), write a new one (**Regenerate**) and close the card (**Dismiss**). The card stays put while you're in the channel, even if you switch to another app, and closes when you go to another channel.

### When the button appears

The **Catch me up** button shows when all of these are true:

- **Offer Catch me up in busy channels** is on in **Settings → Apple Intelligence**. It's on by default.
- Apple Intelligence is ready.
- At least **25** messages are new. Change the number with **Show the button after**: 10, 25, 50 or 100 new messages.
- The **New** line is showing. The button sits on it, so with **Show the New line** turned off in **Settings → Messages → Unread messages** (as the Classic IRC preset does), there's no button. See [Unread messages](/guide/messages-and-layouts#unread-messages).

You can also catch up whenever something's unread, however little, even with the button or the New line turned off:

- Right-click a channel or conversation (in the sidebar, the rail or the tabs) and choose **Catch Me Up**.
- Run **Buffer: Catch Me Up** from the [command palette](/guide/command-palette).
- Ask Siri, "Catch me up in Vela". See [Siri, Shortcuts & Spotlight](/guide/siri-shortcuts).

Without the New line, the card opens where the new messages start, just above the first one.

In settings.json, the switch is [`intelligence.catchUp`](/reference/settings#intelligence.catchUp) and the number is [`intelligence.catchUpThreshold`](/reference/settings#intelligence.catchUpThreshold), which takes any number.

### What it reads, and how long it takes {#catch-up-limits}

- **The new messages, actions and notices** after the New marker (or where it would be, with the New line off). Joins, parts, other events and deleted messages are left out, and links are reduced to the site they point to.
- **At most the latest 600.** For a longer stretch, the card says "Covers the latest 600 messages."
- **It takes a moment.** About 10 seconds for a few dozen messages, and up to about a minute for 600. Until the first words arrive, the card says "Reading 250 messages…".
- **A summary is kept until new messages arrive**, so opening the card again shows it straight away. **Regenerate** writes a fresh one.

If something goes wrong, the card says why and offers **Try Again**, or **Open System Settings** when Apple Intelligence needs attention.

::: warning Summaries can contain mistakes
A summary can misread a conversation or leave out something that matters. Click a topic to read the messages behind it before you act on it.
:::

## Translate messages

<Screenshot src="/screenshots/ai-translate.webp" alt="#vela-offtopic with messages in Spanish, Japanese and German, each followed by its English translation and a “Translated from …” caption" caption="Automatic translation in #vela-offtopic." />

When someone writes in another language, right-click the message (or hover it and click **…**) and choose **Translate**. The translation appears under the original, in a quieter color, with a caption such as **Translated from Spanish**. Click the caption for **Translate Again** and **Hide Translation**. **Hide Translation** is in the message's right-click menu too, which you also get by right-clicking the translation.

**Translate** is offered for other people's messages in a language other than the one you translate into, when macOS can translate between the two. Your own messages are never translated.

While Vela works, the caption reads "Translating from Spanish…". If a translation fails, it reads "Couldn't translate from Spanish"; hover it for the reason, or click it and choose **Try Again**.

### Translate a channel automatically {#automatic}

Right-click a channel or conversation and choose **Translate Messages Automatically**, or run **Buffer: Translate Messages Automatically** from the command palette. To cover every channel on a network, right-click the network and choose the same item.

- **Messages are translated as they scroll into view**, new ones included. Vela never translates a channel's whole history at once.
- **A translation you hide stays hidden.**
- **Languages macOS can't translate**, or whose download you declined, are skipped quietly. A declined language comes back once you translate one of its messages by hand and download it.

**Settings → Apple Intelligence → Translation** counts where it's on ("Translated automatically in 2 channels"), and **Clear** turns it off everywhere. In settings.json it's [`translation.autoTranslate`](/reference/settings#translation.autoTranslate).

### Languages and downloads {#languages}

**Translate into** (in **Settings → Apple Intelligence → Translation**) starts as **Same as Mac**, your Mac's first preferred language. You can choose any language Apple supports, regional variants included. When you change it, translations on screen are redone in the new language, and the rest as they scroll back into view. In settings.json it's [`translation.language`](/reference/settings#translation.language).

The first time you translate from a language, **macOS asks to download it**. That's Apple's own prompt: macOS downloads each language once, from Apple, and translation happens on your Mac from then on.

### What can be translated {#translation-limits}

- **A message needs enough words** for its language to be clear: about a dozen letters, or a few Chinese, Japanese or Korean characters. Short replies, emoji and bare links aren't offered.
- **IRC bits are ignored** when Vela works out a message's language: nicks, links, channel names, `:emoji:` codes and code.

## Writing Tools

With Apple Intelligence on, Apple's **Writing Tools** can proofread or rewrite your message before you send it. Right-click in the message field and choose **Writing Tools**.

Writing Tools leaves commands, nicks, channel names, links and code alone, and its changes are one undo step. Turn it off with **Writing Tools** in **Settings → Messages → Typing**. See [Typing options](/guide/sending-messages#writing-tools).

## Privacy

- **Catch me up runs on your Mac,** on the Apple Intelligence model that macOS keeps on it. The messages it reads and the summary it writes never leave your Mac, and summaries are kept only in memory.
- **Translation runs on your Mac,** with Apple's Translation framework, and so does working out a message's language. Only the language downloads come from Apple, and macOS asks before each one. Translations are kept only in memory.
- **Writing Tools is Apple's.** Vela hands it the text in the message field, and Apple Intelligence handles it as it does in any app.
- **There's no Vela server.** None of these features sends anything to Vela's developers.

See [Privacy](/help/privacy) for everything else Vela does and doesn't do.
