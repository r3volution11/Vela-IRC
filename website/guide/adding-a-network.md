---
title: Adding a network
description: Add an IRC network to Vela, with presets for Libera.Chat, OFTC and others, TLS, SASL or client-certificate login, auto-join channels and perform commands.
---

# Adding a network

Choose **File → Add Network…** (<kbd>⇧⌘N</kbd>), click **+** at the bottom of the sidebar, or go to **Settings → Networks**. The **Add Network** sheet opens.

::: tip The quick way
Click **Presets** in the top-right corner and choose a network. Vela fills in its address, port 6697 and TLS. Check the nickname (Vela suggests one from your Mac user name) and click **Add Network**.
:::

Presets are included for **Libera.Chat**, **OFTC**, **Ergo testnet**, **Rizon**, **EFnet** and **hackint**. For anything else, fill in the fields yourself.

## Server

| Field | What to enter |
| --- | --- |
| **Name** | What the network is called in the sidebar and tabs. Leave it empty to use the address. |
| **Address** | The server's host name, such as `irc.libera.chat`. |
| **Port** | Usually **6697** for TLS and **6667** without it. Vela switches between the two when you toggle TLS and the port is still a default. |
| **Use TLS** | Encrypts the connection. Leave it on; almost every network supports it. |
| **Allow invalid certificates** | Accepts self-signed or expired certificates. Only turn this on for a server you trust, such as your own bouncer. Anyone between you and the server could otherwise read your messages and passwords. |

If a server advertises a [Strict Transport Security](https://ircv3.net/specs/extensions/sts) policy while you're connected without TLS, Vela switches the network to TLS on the port the server names and reconnects.

## Identity

| Field | What to enter |
| --- | --- |
| **Nickname** | The name people see. It can't contain spaces or `, * ? ! @`, or start with a digit or `- # & : $`. |
| **Alternates** | Nicknames to try, in order, if yours is taken. Separate them with commas. |
| **Username** | The "ident" part of your hostmask (`nick!username@host`). Defaults to your nickname. |
| **Real name** | Shown when people look you up with `/whois`. Defaults to your nickname. |

## Authentication

Pick a **Method**:

- **None.** Connect without logging in.
- **SASL PLAIN (account and password).** Log in to your services account (NickServ) while connecting. Recommended for most networks. **Account** defaults to your nickname.
- **SASL EXTERNAL (client certificate).** Log in with a TLS client certificate, also called CertFP. Choose a certificate from your Keychain or click **Import .p12…** and enter the file's password. Add the certificate's fingerprint to your services account first, and keep TLS on.
- **Server password.** Sends a password with `PASS` when connecting. Used by ZNC and some private servers.

Passwords, channel keys and certificates are stored in your **macOS Keychain**. Everything else is saved to `networks.json`.

## Bouncer

Set **Type** to **soju** or **ZNC** if this entry is a bouncer rather than an IRC server. Vela then adjusts how it logs in, rejoins channels and fetches history. See [Connecting through a bouncer](/guide/bouncers).

## Channels

Channels to join after connecting, each with an optional key (password). Vela adds the `#` if you leave it out. When you connect through a bouncer, the bouncer rejoins channels itself, so this list only matters for direct connections.

Channels you join later are remembered too: Vela rejoins the channels you had open unless you left them with `/part`.

## Perform on connect

Commands to run after connecting, one per line, exactly as you'd type them in the message field. For example:

```text
/mode doug +x
/msg ChanServ invite #private-channel
```

::: warning
Perform commands are saved in `networks.json` as plain text. Don't put passwords here; use SASL instead.
:::

## Highlight words and ignore list

- **Highlight words** count as mentions on this network only, in addition to your nickname and the words in **Settings → Notifications**. See [Notifications & highlights](/guide/notifications).
- **Ignore list** hides messages from matching people. Masks use `nick!user@host` with `*` wildcards; a bare nick like `troll` matches any user and host. You can also use `/ignore` and `/unignore`.

## Connection

**Connect automatically** connects this network when Vela opens. It's on by default.

## Editing and removing networks

Right-click a network in the sidebar, or use the **Network** menu, to **Connect**, **Disconnect**, **Reconnect**, **Edit Network…** or **Remove Network…**. **Settings → Networks** lists them all; double-click one to edit it.

If you change the address, port, TLS, nickname or SASL login while connected, Vela reconnects for you. For other changes, such as a new password, choose **Network → Reconnect**.

Removing a network deletes its settings, saved passwords and message history from this Mac.
