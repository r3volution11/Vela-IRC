---
title: Siri, Shortcuts & Spotlight
description: Ask Siri to catch you up, check mentions or send a message, use Vela's actions in Shortcuts and automations, and find your IRC channels, people and (if you like) messages in Spotlight.
---

# Siri, Shortcuts & Spotlight

Vela works with Siri, the Shortcuts app and Spotlight without any setup. Ask Siri what you missed, send a quick message, set yourself away from a shortcut, or open a channel from Spotlight. To drive Vela from Alfred, Raycast or a script, see [Links & AppleScript](/guide/automation).

Their settings are in **Settings → Integrations**, under **Shortcuts and Siri** and **Spotlight**, beside Alfred, Raycast and AppleScript. See [Integrations](/guide/integrations).

<!-- Screenshot to come: Settings → Integrations, scrolled to Shortcuts and Siri and Spotlight (website/scripts/screenshots.sh shoots settings-siri). -->

## Ask Siri {#siri}

These phrases work as soon as Vela is installed. Say the channel's name where the phrase has one, such as "#vela": Siri knows the names of your channels and conversations, and keeps up as you join and leave them.

If you're in channels with the same name on more than one network, add the network: "Open #vela on Libera.Chat in Vela", or just "on Libera". Without it, Siri asks which one you mean. Every phrase that names a channel works this way.

| To | Say |
| --- | --- |
| Get a summary of what you missed | "Catch me up in Vela", "Catch me up on #vela in Vela", "What did I miss in Vela", "Summarize #vela in Vela" |
| Open a [Recap](/guide/recap) | "Open a recap in Vela", "Recap my channels in Vela", "Recap #vela in Vela", "Recap today in Vela" |
| Hear who mentioned you | "Check my Vela mentions", "Check mentions in Vela", "Who mentioned me in Vela" |
| Send a message | "Send a message with Vela", "Send a message to #vela with Vela", "Message #vela in Vela" |
| Open a channel | "Open #vela in Vela", "Open #vela on Libera.Chat in Vela", "Show #vela in Vela", "Go to #vela in Vela" |
| Set yourself away | "Set me away in Vela", "Mark me away in Vela" |
| Come back | "Set me back in Vela", "I'm back in Vela" |
| Clear your unread counts | "Mark everything as read in Vela", "Mark all as read in Vela" |
| Search your messages | "Search Vela", "Search messages in Vela", "Find a message in Vela" |
| Join a channel | "Join a channel in Vela", "Join a channel with Vela" |

Siri asks for anything you leave out, such as the message. Before sending, it may read your message back and ask you to confirm.

The phrases are in English, so they work when Siri's language is English. In other languages, use Vela's actions in the [Shortcuts app](#shortcuts) instead.

**Catch me up** needs [Apple Intelligence](/guide/apple-intelligence#requirements), or uses [your own model](/guide/ai-models) when you've chosen one for it (Siri can't ask for your OK to send it messages: catch up in Vela once first). Siri reads the overview aloud and shows the topics. With nothing unread, it says "You're all caught up." Name a channel you've already caught up on and Siri gives you that summary again, until you quit Vela; with no summary to give, it says "There's nothing new in #vela." Siri never cuts a catch-up short:

- **A short stretch** (about 100 messages, which your Mac reads in one quick pass) Siri summarizes and reads out itself.
- **A longer one opens Vela.** Siri says so ("That's 412 messages in #vela. Opening Vela to catch you up."), and Vela opens to the channel with the [Catch me up card](/guide/apple-intelligence#catch-me-up) summarizing all of it. Siri may ask first whether to open Vela.
- **One longer than a card covers** (over 600 messages) opens a [Recap](/guide/recap) of the channel instead, which reads more: "That's 1240 messages in #vela. Opening a Recap in Vela." In an automation that runs in the background, or while Recap is turned off, it opens the card as above.
- **With [Private Cloud Compute](/guide/apple-intelligence#private-cloud-compute) on** (in a later version, on macOS 27 or later), Siri will summarize a long stretch itself, as long as Private Cloud Compute can read it in one pass and is expected to answer in about 15 seconds. Otherwise it will open Vela as above.
- **A summary already made** in the channel's card is used as it is, however long the stretch.
- **Siri waits about 15 seconds at most.** If the summary isn't ready by then (another channel's summary is being written first, say), Siri opens Vela, where the card carries on with it rather than starting over.

## Shortcuts actions {#shortcuts}

In the **Shortcuts** app, search for "Vela" to find its actions, or click **Open Shortcuts** in **Settings → Integrations → Shortcuts and Siri**, which lists them all.

| Action | Parameters | What it does |
| --- | --- | --- |
| **Open Channel** | Channel | Brings Vela to the front and shows the channel or conversation, opening the window if it's closed. |
| **Open Private Conversation** | Person | Shows your private conversation with someone: one that's open, one you closed since Vela started (it's reopened), or a new one, as `/query` starts. |
| **Search Messages** | Search For | Brings Vela to the front with [message search](/guide/automation#message-search) open on your words, across all your networks. |
| **Send Message** | Message, Channel | Sends the message and replies "Sent to #vela on Libera.Chat." Text that starts with `/` is sent as it is, not run as a command. |
| **Join Channel** | Channel, Network (optional), Key (optional) | Joins the channel (adding `#` if you leave it out) without switching to it, and returns it. Without a network, it uses the only network you're connected to, or the one you're looking at, or asks. |
| **Check Mentions** | | Says how many mentions and private messages are waiting ("You have 3 mentions in #vela."), shows up to six channels and conversations, and returns them. |
| **Open Recap** | Channel (optional), Person (optional), Network (optional), Time Span | Opens a [Recap](/guide/recap) in Vela: the channel, else the network, else every network; since your first unread message, or the last 30 minutes, hour, 4 hours, today, the last day, 3 days or week. With a person, it's their messages, messages that name them and your private conversation with them (with a channel, on the channel's whole network). Apple Intelligence, or [your own model](/guide/ai-models) if you chose one for Recap, writes it in Vela; without either, it shows as a log. |
| **Catch Me Up** | Channel (optional) | Summarizes what's new with Apple Intelligence, or your own model if you chose one for Catch me up: the overview as the result, the topics underneath. A stretch too long to summarize quickly opens Vela to the channel, with the Catch me up card summarizing all of it. Without a channel, it picks the unmuted one with the most unread messages; with nothing unread, it says "You're all caught up." |
| **Set Away** | Message (optional) | Marks you away on every network you're connected to, like `/away`. The message defaults to "Away". |
| **Set Back** | | Marks you back on every connected network, like `/back`. |
| **Mark All as Read** | | Marks every channel and conversation as read. |
| **Connect Network** | Network | Connects one of your networks. |
| **Disconnect Network** | Network | Disconnects one of your networks. |

Actions that return something can feed the next action: **Check Mentions** passes on the channels that mention you, and **Join Channel** the channel it joined.

::: tip An idea to start with
Make a "Back at my desk" shortcut: **Connect Network** for your favorite network, then **Set Back**, then **Catch Me Up**. Or use the Shortcuts app's automations to run **Set Away** with a message such as "In a meeting" when a Focus turns on, and **Set Back** when it turns off.
:::

### What actions need {#requirements}

- **Vela opens if it isn't running.** You don't need to start it first. **Catch Me Up** and **Check Mentions** count what's unread from where you last read each channel, so they give the same answer right after Siri opens Vela as they do later.
- **Catch Me Up may bring Vela to the front** for a long stretch, to show its summary in the channel. When it can't (in an automation that runs in the background, say), the summary starts anyway, and Siri says to open the channel in Vela to read it.
- **Sending, joining and away need a connected network.** If a network is still connecting, Vela waits about 10 seconds for it.
- **To send to a channel, you must have joined it.** Otherwise the action says, for example, "You're not in #vela on Libera.Chat."

## Spotlight

Your channels show up in Spotlight with their network, and so do the people you talk to in private: each open private conversation, and those you closed since Vela started. Choose one to open it in Vela; a closed conversation is reopened.

Spotlight only gets their **names** and networks. To keep them out of Spotlight, turn off **Show channels in Spotlight** in **Settings → Integrations → Spotlight** ([`intelligence.spotlightChannels`](/reference/settings#intelligence.spotlightChannels)); Vela removes them from Spotlight's results straight away.

The setting covers what Spotlight shows, not what Siri knows. On macOS 27, Vela also gives the system the same names for Siri, marked so that Spotlight doesn't show them: that's how Siri finds "#vela" or a nick when you ask it to send a message. They stay when the setting is off.

### Actions in Spotlight {#spotlight-actions}

On macOS 26 and later, Spotlight runs Vela's [Shortcuts actions](#shortcuts) itself: type "Send Message", "Catch Me Up", "Open Recap", "Join Channel", "Set Away", "Mark All as Read" or "Search Messages" (or words like "DM", "afk" or "find") and fill in what it asks, without opening Shortcuts.

**Search in Vela**: type what you're looking for in Spotlight and choose **Search in Vela** (or the **Search Messages** action) to open Vela's [message search](/guide/automation#message-search) with those words.

### Messages in Spotlight {#messages-in-spotlight}

You can also let Spotlight search your messages. It's off unless you turn it on: **Search messages in Spotlight**, in **Settings → Integrations → Spotlight** ([`intelligence.spotlightMessages`](/reference/settings#intelligence.spotlightMessages)). It needs **Save message history** ([`history.save`](/reference/settings#history.save)), because Spotlight gets the messages Vela saves, and forgets them with the history.

- **Turning it on** adds the newest 5,000 saved messages of each network, in the background. After that, each message is added as Vela saves it. Messages, actions and notices in channels and private conversations are added; joins, parts, network consoles and deleted messages aren't, and neither are saved messages of conversations you no longer have open.
- **Choose a result** to open its conversation scrolled to that message (or to the conversation, if the message is further back than Vela can load).
- **Spotlight forgets them** when you turn the setting off, turn off **Save message history** or delete saved history. Removing a channel, closing a private conversation or removing a network removes its messages, and a message its sender deletes is removed too. With **Keep messages** set, they leave Spotlight when Vela would delete them.
- **It costs almost nothing while you chat.** Vela adds messages in batches, away from what draws the window, and never more than 2,000 from one batch (a bouncer replaying thousands of lines at once adds its newest).

## With the new Siri in macOS 27 {#macos-27}

On macOS 27 or later, Siri can do more with Vela:

- **Send to a channel or a nick.** A message to a nick opens a private conversation, like `/msg`.
- **Draft a message.** Siri puts the text in the channel's message field and opens the channel; press <kbd>Return</kbd> when it's right.
- **Mark a message, and everything before it, as read.** Newer messages stay unread.
- **Know what's on screen.** Siri knows which channel you're looking at, so "reply to this" works. Notifications for mentions and private messages support "reply to this" too. For a summary, ask Siri to [catch you up](#siri) on the channel.

IRC messages are text, so Siri can't send attachments or locations through Vela, or schedule a message for later.

## Privacy

- **Everything happens on your Mac.** Siri and Shortcuts run Vela's actions inside Vela, and Catch Me Up summarizes on your Mac. ([Private Cloud Compute](/guide/apple-intelligence#private-cloud-compute) for long catch-ups, which you'll be able to turn on, comes in a later version.) What you say to Siri is handled by Siri itself, under Apple's privacy policy.
- **Spotlight gets names only, unless you turn on messages:** your channel names, the nicks of people you talk to in private, and their networks. **Show channels in Spotlight** decides whether they appear in Spotlight's results; on macOS 27, the same names are also kept for Siri, hidden from Spotlight's results, either way. Messages reach Spotlight only if you turn on [Search messages in Spotlight](#messages-in-spotlight), and only while history is saved. Spotlight's index stays on your Mac.
- **Siri learns where you send messages.** When you send a message, Vela tells Siri which channel it went to, so Siri can suggest it later. It never shares the text.
- **Message lookups happen when Siri asks.** On macOS 27, when Siri needs a message (to reply to it, say), Vela searches the recent messages it has in memory at that moment. Nothing is indexed for Siri ahead of time.
- **Demo mode stays out of it.** Sample channels never reach Spotlight or Siri.

## Troubleshooting

**Siri or Shortcuts doesn't know about Vela.** Open Vela once, so macOS registers its actions. If it still doesn't show up, make sure there's **only one copy of Vela.app** on your Mac: an old copy in Downloads, or one you built yourself, can confuse macOS about which one to use. Delete the extra copies and open Vela from Applications.

**"You're not connected to Libera.Chat."** Connect the network first, or add **Connect Network** before the action in your shortcut.

**"You're not in #vela on Libera.Chat."** Join the channel, or add **Join Channel** before **Send Message**.

**Catch Me Up says Apple Intelligence is off.** See [What you need](/guide/apple-intelligence#requirements).

**A channel doesn't appear in Spotlight.** Check that **Show channels in Spotlight** is on. New channels appear a moment after you join them.

**Messages don't appear in Spotlight.** Check that **Save message history** and **Search messages in Spotlight** are both on. After you turn it on, give Spotlight a minute to take in your saved history. Demo mode never adds anything.
