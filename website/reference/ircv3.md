---
title: IRCv3 support
description: The IRCv3 capabilities and client tags Vela supports, from server-time, chathistory, SASL and STS to reactions, replies, typing, redaction and soju and ZNC extensions.
---

# IRCv3 support

Vela follows the [Modern IRC Client Protocol](https://modern.ircdocs.horse) and the [IRCv3 specifications](https://ircv3.net/irc/). When it connects, it negotiates capabilities with `CAP LS 302` and asks for everything below that the server offers. Features that depend on a capability simply don't appear when the server lacks it.

## Capabilities

| Capability | What Vela does with it |
| --- | --- |
| [`sasl`](https://ircv3.net/specs/extensions/sasl-3.1) | Logs in while connecting, with `PLAIN` (account and password) or `EXTERNAL` (TLS client certificate). |
| [`sts`](https://ircv3.net/specs/extensions/sts) | Upgrades a plain-text connection to TLS on the port the server names, and saves the change. |
| [`cap-notify`](https://ircv3.net/specs/extensions/capability-negotiation#cap-notify) | Follows capabilities the server adds or removes while you're connected. |
| [`server-time`](https://ircv3.net/specs/extensions/server-time) | Shows when a message was actually sent, which matters for history and bouncers. |
| [`message-tags`](https://ircv3.net/specs/extensions/message-tags) | Carries reactions, replies and typing indicators (see client tags below). |
| [`echo-message`](https://ircv3.net/specs/extensions/echo-message) | Shows your messages as the server received them. |
| [`batch`](https://ircv3.net/specs/extensions/batch) | Groups history and bouncer responses. |
| [`labeled-response`](https://ircv3.net/specs/extensions/labeled-response) | Matches replies to the requests that caused them. |
| [`chathistory`](https://ircv3.net/specs/extensions/chathistory) (and `draft/chathistory`) | Fetches messages you missed when you connect, and older history as you scroll up. |
| [`away-notify`](https://ircv3.net/specs/extensions/away-notify) | Dims people in the member list when they go away. |
| [`account-notify`](https://ircv3.net/specs/extensions/account-notify), [`account-tag`](https://ircv3.net/specs/extensions/account-tag), [`extended-join`](https://ircv3.net/specs/extensions/extended-join) | Keeps track of which account each person is logged in to. |
| [`multi-prefix`](https://ircv3.net/specs/extensions/multi-prefix) | Knows every rank someone holds (for example both `@` and `+`). |
| [`userhost-in-names`](https://ircv3.net/specs/extensions/userhost-in-names) | Knows everyone's host from the start, for hover details and `/ban`. |
| [`chghost`](https://ircv3.net/specs/extensions/chghost), [`setname`](https://ircv3.net/specs/extensions/setname) | Updates hosts and real names without a fake quit and rejoin. |
| [`invite-notify`](https://ircv3.net/specs/extensions/invite-notify) | Shows invitations to channels you're in. |
| [`standard-replies`](https://ircv3.net/specs/extensions/standard-replies) | Shows `FAIL`, `WARN` and `NOTE` replies; failures appear in the conversation you're looking at. |
| [`draft/message-redaction`](https://ircv3.net/specs/extensions/message-redaction) | Lets you delete your own messages, and shows deleted messages as **Message deleted**. |

## Client tags

These ride on `message-tags`. Vela respects the server's `CLIENTTAGDENY`, so a feature the server blocks is hidden.

| Tag | Used for |
| --- | --- |
| `+draft/react`, `+draft/unreact` | [Reactions](/guide/reactions-replies-typing#reactions) |
| `+draft/reply` | [Replies](/guide/reactions-replies-typing#replies). Without it, **Reply** starts your message with the sender's `nick: `, the usual IRC way. |
| `+typing` | [Typing indicators](/guide/reactions-replies-typing#typing-indicators) (sending them can be turned off) |

## Bouncer extensions

| Capability | What Vela does with it |
| --- | --- |
| `soju.im/bouncer-networks`, `soju.im/bouncer-networks-notify` | Lists the networks on your [soju](https://soju.im) bouncer, adds each one to the sidebar, and keeps the list in sync. |
| `znc.in/playback` | Asks [ZNC](https://znc.in) only for messages Vela doesn't have yet, when you connect and when you join a channel you left on the bouncer. |
| `znc.in/self-message` | Shows messages you sent from your other clients. |
| `znc.in/server-time-iso`, `znc.in/batch` | ZNC's older names for `server-time` and `batch`. |

**Leave Channel** through a bouncer detaches the channel with the bouncer's own command, so the bouncer stays in it: `detach #channel` to ZNC's `*status`, or `channel update #channel -detached true` to soju's `BouncerServ`. Joining the channel again reattaches it.

See [Connecting through a bouncer](/guide/bouncers).

## Also supported

- **TLS** with certificate validation, an opt-in **Allow invalid certificates** for self-signed bouncers, and **client certificates** (CertFP).
- **`ISUPPORT`**: the network name, channel types, member prefixes, case mapping (so `Nick[a]` and `nick{a}` are the same person), history limits and `CLIENTTAGDENY`.
- **CTCP**: `ACTION` (`/me`), and automatic replies to `VERSION`, `PING`, `TIME` and `CLIENTINFO`.
- **[mIRC](https://www.mirc.com) formatting**: bold, italic, underline, strikethrough, monospace, colors 0–98, hex colors and reverse.
- **Reconnection** with backoff, after a dropped connection, a network change, or your Mac waking up.

## Requested, not used yet

Vela already asks for `draft/read-marker`, but doesn't yet sync your read position between clients. That's on the [roadmap](https://github.com/r3volution11/Vela-IRC/blob/main/ROADMAP.md), along with `draft/multiline`, `draft/metadata-2` avatars, message editing once the spec settles, and image uploads through soju's `FILEHOST`.
