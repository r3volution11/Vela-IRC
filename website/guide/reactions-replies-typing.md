---
title: Reactions, replies & typing
description: React to messages with emoji, reply to a specific message, see who's typing and delete your own messages in Vela, on IRC servers that support IRCv3 message tags.
---

# Reactions, replies & typing

Modern IRC servers support a few things chat apps have made familiar. Vela supports them all, and quietly hides them on servers that don't.

## Reactions

Hover a message: the toolbar at its top-right offers your three most-used emoji and a **smiley** button that opens the emoji picker, with search, your frequently used emoji and every category. **Right-click → Add Reaction** works too.

Reactions appear as chips under the message, each with a count; yours are highlighted. Click a chip to add or remove your reaction, or the **+** chip to pick another emoji.

## Replies

Hover a message and click the **reply** arrow. A bar above the message field shows who you're replying to (<kbd>Esc</kbd> cancels). Your reply appears with a small quote of the original above it; click the quote to jump to the original message.

On servers without reply support, the bar warns that your message will be **sent as a normal message**.

## Typing indicators

When someone is typing in the current channel or conversation, you'll see "**wren is typing…**" just above the message field ("Several people are typing…" when it's busy).

Vela tells others when you're typing, too. It doesn't when you're typing a command, or while [Writing Tools](/guide/sending-messages#writing-tools) is working on your message, and you can turn it off with **Send typing indicators** in **Settings → Messages → Typing**.

## Deleting your messages

On servers that support message deletion, hover one of your own messages, click **…** and choose **Delete Message**. After you confirm, it shows as **Message deleted** for everyone whose client supports it.

## When do these work?

They need the server to support **IRCv3 message tags** (and, for deletion, `draft/message-redaction`), and to allow the specific tags involved. Vela checks what the server offers each time it connects:

| Feature | Needs | If it's missing |
| --- | --- | --- |
| Reactions | `message-tags`, `+draft/react` allowed | No reaction buttons; others' reactions can't arrive |
| Replies | `message-tags`, `+draft/reply` allowed | Replies are sent as normal messages |
| Typing | `message-tags`, `+typing` allowed | No typing line |
| Delete | `draft/message-redaction` | No **Delete Message** item |

Support varies by network and server software: [Ergo](https://ergo.chat) supports all of them, and many older networks don't yet.

::: info Bouncers
A bouncer sits between you and the network, so it must support message tags too. **soju** does. **Older ZNC versions don't pass them through**, so on those connections reactions, replies and typing indicators are unavailable even if the network supports them.
:::

See the full [IRCv3 support](/reference/ircv3) list for everything else Vela speaks.
