---
title: Apple Intelligence & translation
description: Catch up on busy IRC channels with on-device Apple Intelligence summaries, translate messages from other languages, and proofread with Writing Tools in Vela.
---

# Apple Intelligence & translation

Vela uses Apple's built-in intelligence to help with busy channels and other languages:

- **[Catch me up](#catch-me-up)** summarizes what you missed in a channel.
- **[Recap](/guide/recap)** writes a fuller report of a channel, a network or everything, for anyone or one person, over any span, in a window of its own.
- **[Translate](#translate-messages)** shows messages from other languages in yours.
- **[Writing Tools](#writing-tools)** proofreads and rewrites what you type.

Summaries, Recaps and translations are made on your Mac. Vela doesn't send your conversations to Apple, to a server of its own or anywhere else. See [Privacy](#privacy) for the details. ([Private Cloud Compute](#private-cloud-compute) for long catch-ups, which you'll be able to turn on, comes in a later version.)

## What you need {#requirements}

Catch me up and Writing Tools use **Apple Intelligence**, so they need:

- a Mac with Apple silicon;
- Apple Intelligence turned on in **System Settings → Apple Intelligence & Siri**, with its model downloaded (macOS downloads it after you turn Apple Intelligence on);
- a language Apple Intelligence supports.

**Translation doesn't need Apple Intelligence**, so it also works on Macs that can't run it.

## The Settings pane {#settings}

<Screenshot src="/screenshots/settings-intelligence.webp" alt="Settings → Apple Intelligence: a green “Apple Intelligence is on” box, then the Catch me up section, with Offer Catch me up in busy channels on and Show the button after 25 new messages, and the Translation section" caption="Settings → Apple Intelligence." />

**Settings → Apple Intelligence** has a section each for Catch me up, [Recap](/guide/recap), Translation, Writing Tools and [Siri & Shortcuts](/guide/siri-shortcuts). At the top, a box says whether Apple Intelligence is ready:

| Status | What it means |
| --- | --- |
| **Apple Intelligence is on** | Everything's ready. |
| **Apple Intelligence is off** | Click **Open System Settings** and turn it on in **Apple Intelligence & Siri**. |
| **Not available on this Mac** | Apple Intelligence needs a Mac with Apple silicon. Translation still works. |
| **Apple Intelligence is getting ready** | macOS is still downloading the model. Catch me up is ready, and this box says so, as soon as the download finishes. |
| **Language not supported yet** | Apple Intelligence doesn't support your Mac's language yet. **Open System Settings** takes you there. |

While Apple Intelligence isn't available, the Catch me up settings are dimmed.

## Catch me up

<Screenshot src="/screenshots/ai-catch-up.webp" alt="A Catch me up card under the New marker in #swift: “While you were away · 4 messages”, a one-line overview, a topic with who took part, and a note that it was summarized on this Mac" caption="Catch me up in #swift." />

Come back to a busy channel and a **Catch me up** button appears at the end of the **New** marker, the line that shows where you stopped reading. Click it, and a card opens right there, under the marker:

- **An overview** of what happened, written as you watch.
- **Topics**, each with a title, who took part and a one-line summary. Click a topic to jump to its first message, which is briefly highlighted. A topic Apple Intelligence couldn't place in the conversation has no link.
- **You were mentioned**, when people said something to you.

The buttons at the top of the card copy the summary (**Copy Summary**), write a new one (**Regenerate**) and close the card (**Dismiss**). The card stays until you dismiss it. Go to another channel while it's being written and it keeps going: it's there, finished, when you come back.

**Open Full Recap**, under the card, opens a [Recap](/guide/recap) of the same messages: a fuller report in a window of its own, with what was decided, who said they'd do what, the links shared and **More detail** on anything. Use it when there's more than a card covers.

**Messages your bouncer replays count as new.** When Vela connects to ZNC, soju or a server with chat history, the messages it replays from while you were away count as unread once they're newer than where you stopped reading, so the New line and Catch me up cover them. See [Bouncers](/guide/bouncers).

### When the button appears

The **Catch me up** button shows when all of these are true:

- **Offer Catch me up in busy channels** is on in **Settings → Apple Intelligence**. It's on by default.
- Apple Intelligence is ready.
- At least **25** messages are new. Change the number with **Show the button after**: 10, 25, 50 or 100 new messages.
- The **New** line is showing. The button sits on it, so with **Show the New line** turned off in **Settings → Messages → Unread messages** (as the Classic IRC preset does), there's no button. See [Unread messages](/guide/messages-and-layouts#unread-messages).

You can also catch up whenever you like, however little is new, even with the button or the New line turned off:

- Right-click a channel or conversation (in the sidebar, the rail or the tabs) and choose **Catch Me Up**.
- Run **Buffer: Catch Me Up** from the [command palette](/guide/command-palette).
- Ask Siri, "Catch me up in Vela". See [Siri, Shortcuts & Spotlight](/guide/siri-shortcuts).

Without the New line, the card opens where the new messages start, just above the first one.

**With nothing new,** Catch Me Up shows the summary you made earlier in that channel, until you quit Vela, so a stretch you've since read is still one click away. If there's no earlier summary, a card at the end of the conversation says there's nothing new, and when the button will be back. In the command palette, the command says which you'll get: **earlier summary** or **nothing new**.

**Offer Catch me up in busy channels** turns Catch me up off everywhere: the button, the right-click item and the palette command go, open cards close, and Siri says it's turned off in Vela's settings.

In settings.json, the switch is [`intelligence.catchUp`](/reference/settings#intelligence.catchUp) and the number is [`intelligence.catchUpThreshold`](/reference/settings#intelligence.catchUpThreshold), which takes any number.

### What it reads, and how long it takes {#catch-up-limits}

- **The new messages, actions and notices** after the New marker (or where it would be, with the New line off). Joins, parts, other events and deleted messages are left out, and links are reduced to the site they point to.
- **At most the latest 600.** For a longer stretch, the card says "Covers the latest 600 messages." A [Recap](/guide/recap) reads up to 2,000.
- **It takes a while.** On a fast Mac, about 10 seconds for a few dozen messages and about a minute for 600, most of it spent reading the parts. A slower Mac, or one on macOS 26.0–26.3 (whose model reads less at a time), can take a few minutes for a long stretch. You can go to another channel meanwhile.
- **Long stretches are read in parts.** The card counts them ("Reading… 3 of 8"), then says "Writing the summary…" until the first words appear. Before that, a short stretch says "Reading 40 messages…".
- **One summary at a time.** Ask in several channels and they're summarized in turn, in the order you asked, so a Mac with 8 GB of memory isn't running several at once. A card waiting its turn says so ("Waiting… 1 summary ahead"); dismiss it to take it out of line. A summary [Siri](/guide/siri-shortcuts#siri) is waiting for goes next.
- **Words never disappear.** If Apple Intelligence has to redo a pass (it ran out of room, say), what it wrote stays on the card, dimmed, with "Finishing…", until the new words arrive.
- **Heated channels are summarized too, neutrally.** Politics, arguments and name-calling are described as what was said and by whom, without taking sides or repeating the insults.
- **A part it won't summarize is skipped,** which is now rare. Apple Intelligence's safety checks can still decline part of a conversation. The rest is still summarized, and the card says how many messages it skipped. Only when it declines all of it does the card say it couldn't summarize the conversation.
- **A summary is kept until new messages arrive**, so opening the card again shows it straight away. **Regenerate** writes a fresh one.

### Private Cloud Compute for long catch-ups {#private-cloud-compute}

::: info Private Cloud Compute is coming in a later version
In this version of Vela, every catch-up is summarized on your Mac, and there's no Private Cloud Compute switch. Apps need Apple's permission to use Private Cloud Compute, and Vela is waiting for it. Until then, it's only in development builds.
:::

*In a later version of Vela (see above).* On macOS 27 or later, **Use Private Cloud Compute for long catch-ups** in **Settings → Apple Intelligence** lets a long catch-up use Apple's [Private Cloud Compute](https://security.apple.com/blog/private-cloud-compute/): the larger Apple Intelligence model that runs on Apple's servers. It's **off by default**.

- **Only long catch-ups go.** A stretch the model on your Mac reads in one pass (on macOS 27, up to a couple of hundred messages of ordinary chat) is summarized on your Mac as always. One that would take several passes goes to Private Cloud Compute, which reads far more at once, so a few hundred messages are usually read in one go: quicker, and without the parts.
- **What's sent:** the messages in that stretch, with their nicks (links reduced to the site they point to, as always), and your nick, so the summary can say when you were mentioned. Not the channel's or the network's name.
- **Apple's guarantees:** the request is encrypted on its way to Private Cloud Compute, used only to write the summary, and not stored afterwards. Apple can't read it, and independent experts can check the software that runs it.
- **Everything else stays on your Mac:** short catch-ups, translation and the rest of Vela. Vela still sends nothing to its developers.
- **If it can't be used, your Mac does it.** When Private Cloud Compute isn't available, can't be reached, or you've reached its daily limit, the summary is made on your Mac instead, without asking. The card's footer says where each summary was made: "Summarized by Apple Intelligence with Private Cloud Compute", or "Summarized on this Mac by Apple Intelligence" with the reason Private Cloud Compute wasn't used. After a failure, Vela waits about 10 minutes before trying it again.
- **Siri can answer long catch-ups itself** with it on. See [Siri, Shortcuts & Spotlight](/guide/siri-shortcuts#siri).

In settings.json, it's [`intelligence.privateCloudCompute`](/reference/settings#intelligence.privateCloudCompute), which only development builds know for now. It has no effect on macOS 26.

If something goes wrong, the card says why and offers **Try Again**, or **Open System Settings** when Apple Intelligence needs attention. When people are writing in a language Apple Intelligence can't summarize yet, the card says "This conversation's language isn't supported for summaries yet." That's about the conversation, not your Mac's language, so there's nothing to change in System Settings.

::: warning Summaries can contain mistakes
A summary can misread a conversation or leave out something that matters. Click a topic to read the messages behind it before you act on it.
:::

## Translate messages

<Screenshot src="/screenshots/ai-translate.webp" alt="#vela-offtopic with messages in Spanish, Japanese and German, each followed by its English translation and a “Translated from …” caption" caption="Automatic translation in #vela-offtopic." />

When someone writes in another language, right-click the message (or hover it and click **…**) and choose **Translate**. The translation appears under the original, in a quieter color, with a caption such as **Translated from Spanish**. Click the caption for **Translate Again** and **Hide Translation**. **Hide Translation** is in the message's right-click menu too, which you also get by right-clicking the translation.

**Translate** is offered for other people's messages in a language other than the one you translate into, when macOS can translate between the two. Your own messages are never translated.

With VoiceOver, use the message's **Translate** action. It's also offered on other people's messages whose language Vela hasn't checked yet; if such a message turns out to need no translation, VoiceOver says so.

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

- **Catch me up and Recap run on your Mac,** on the Apple Intelligence model that macOS keeps on it. The messages they read and the summaries they write stay on your Mac, and summaries are kept only in memory: a Recap only as long as its window is open.
- **Apple Intelligence reads the messages and your nick,** so the summary can say what was asked of "you". It isn't told the channel's or the network's name, or who a Recap is about.
- **Private Cloud Compute comes in a later version.** In it, you'll be able to send a catch-up too long for one pass on your Mac to Apple's Private Cloud Compute (macOS 27 or later, off by default): encrypted, used only to write the summary, not stored, and not readable by Apple. See [Private Cloud Compute for long catch-ups](#private-cloud-compute).
- **Translation runs on your Mac,** with Apple's Translation framework, and so does working out a message's language. Only the language downloads come from Apple, and macOS asks before each one. Translations are kept only in memory.
- **Writing Tools is Apple's.** Vela hands it the text in the message field, and Apple Intelligence handles it as it does in any app.
- **There's no Vela server.** None of these features sends anything to Vela's developers.

See [Privacy](/help/privacy) for everything else Vela does and doesn't do.
