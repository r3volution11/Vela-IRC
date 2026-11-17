---
title: Siri, Shortcuts & Spotlight
description: Ask Siri to catch you up, check mentions or send a message, use Vela's actions in Shortcuts and automations, and find your IRC channels in Spotlight.
---

# Siri, Shortcuts & Spotlight

Vela works with Siri, the Shortcuts app and Spotlight without any setup. Ask Siri what you missed, send a quick message, set yourself away from a shortcut, or open a channel from Spotlight.

<Screenshot src="/screenshots/settings-siri.webp" alt="Settings → Apple Intelligence, scrolled to Siri & Shortcuts: the Show channels in Spotlight switch, a list of things to ask Siri, and an Open Shortcuts button" caption="Settings → Apple Intelligence → Siri & Shortcuts." />

## Ask Siri {#siri}

These phrases work as soon as Vela is installed. Say the channel's name where the phrase has one, such as "#vela": Siri knows the names of your channels and conversations, and keeps up as you join and leave them.

| To | Say |
| --- | --- |
| Get a summary of what you missed | "Catch me up in Vela", "Catch me up on #vela in Vela", "What did I miss in Vela", "Summarize #vela in Vela" |
| Hear who mentioned you | "Check my Vela mentions", "Check mentions in Vela", "Who mentioned me in Vela" |
| Send a message | "Send a message with Vela", "Send a message to #vela with Vela", "Message #vela in Vela" |
| Open a channel | "Open #vela in Vela", "Show #vela in Vela", "Go to #vela in Vela" |
| Set yourself away | "Set me away in Vela", "Mark me away in Vela" |
| Come back | "Set me back in Vela", "I'm back in Vela" |
| Clear your unread counts | "Mark everything as read in Vela", "Mark all as read in Vela" |

Siri asks for anything you leave out, such as the message. Before sending, it may read your message back and ask you to confirm.

**Catch me up** needs [Apple Intelligence](/guide/apple-intelligence#requirements). Siri reads the overview aloud and shows the topics. With nothing unread, it says "You're all caught up."

## Shortcuts actions {#shortcuts}

In the **Shortcuts** app, search for "Vela" to find its actions, or click **Open Shortcuts** in **Settings → Apple Intelligence → Siri & Shortcuts**.

| Action | Parameters | What it does |
| --- | --- | --- |
| **Open Channel** | Channel | Brings Vela to the front and shows the channel or conversation, opening the window if it's closed. |
| **Send Message** | Message, Channel | Sends the message and replies "Sent to #vela on Libera.Chat." Text that starts with `/` is sent as it is, not run as a command. |
| **Join Channel** | Channel, Network (optional), Key (optional) | Joins the channel (adding `#` if you leave it out) without switching to it, and returns it. Without a network, it uses the only network you're connected to, or the one you're looking at, or asks. |
| **Check Mentions** | | Says how many mentions and private messages are waiting ("You have 3 mentions in #vela."), shows up to six channels and conversations, and returns them. |
| **Catch Me Up** | Channel (optional) | Summarizes what's new with Apple Intelligence: the overview as the result, the topics underneath. Without a channel, it picks the unmuted one with the most unread messages. |
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

- **Vela opens if it isn't running.** You don't need to start it first.
- **Sending, joining and away need a connected network.** If a network is still connecting, Vela waits about 10 seconds for it.
- **To send to a channel, you must have joined it.** Otherwise the action says, for example, "You're not in #vela on Libera.Chat."

## Spotlight

Your channels and conversations show up in Spotlight, with their network. Choose one to open it in Vela.

Spotlight only ever gets their **names**, never messages. To keep them out of Spotlight, turn off **Show channels in Spotlight** in **Settings → Apple Intelligence → Siri & Shortcuts** ([`intelligence.spotlightChannels`](/reference/settings#intelligence.spotlightChannels)); Vela removes them straight away.

## With the new Siri in macOS 27 {#macos-27}

On macOS 27 or later, Siri can do more with Vela:

- **Send to a channel or a nick.** A message to a nick opens a private conversation, like `/msg`.
- **Draft a message.** Siri puts the text in the channel's message field and opens the channel; press <kbd>Return</kbd> when it's right.
- **Mark a message, and everything before it, as read.** Newer messages stay unread.
- **Know what's on screen.** Siri knows which channel you're looking at, so "reply to this" and "summarize this" work. Notifications for mentions and private messages support "reply to this" too.

IRC messages are text, so Siri can't send attachments or locations through Vela, or schedule a message for later.

## Privacy

- **Everything happens on your Mac.** Siri and Shortcuts run Vela's actions inside Vela. What you say to Siri is handled by Siri itself, under Apple's privacy policy.
- **Spotlight gets names only:** your channel and conversation names and their networks. Never messages.
- **Siri learns where you send messages.** When you send a message, Vela tells Siri which channel it went to, so Siri can suggest it later. It never shares the text.
- **Message lookups happen when Siri asks.** On macOS 27, when Siri needs a message (to reply to it, say), Vela searches the recent messages it has in memory at that moment. Nothing is indexed ahead of time.
- **Demo mode stays out of it.** Sample channels never reach Spotlight or Siri.

## Troubleshooting

**Siri or Shortcuts doesn't know about Vela.** Open Vela once, so macOS registers its actions. If it still doesn't show up, make sure there's **only one copy of Vela.app** on your Mac: an old copy in Downloads, or one you built yourself, can confuse macOS about which one to use. Delete the extra copies and open Vela from Applications.

**"You're not connected to Libera.Chat."** Connect the network first, or add **Connect Network** before the action in your shortcut.

**"You're not in #vela on Libera.Chat."** Join the channel, or add **Join Channel** before **Send Message**.

**Catch Me Up says Apple Intelligence is off.** See [What you need](/guide/apple-intelligence#requirements).

**A channel doesn't appear in Spotlight.** Check that **Show channels in Spotlight** is on. New channels appear a moment after you join them.
