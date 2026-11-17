---
title: Connecting through a bouncer
description: Connect Vela to a ZNC or soju IRC bouncer, including the ZNC password format, TLS and self-signed certificates, soju network discovery and chat history.
---

# Connecting through a bouncer

A bouncer stays connected to IRC for you, so you keep receiving messages while your Mac is asleep. Vela has first-class support for the two most popular ones, **[ZNC](https://znc.in)** and **[soju](https://soju.im)**.

Add the bouncer like any other network (<kbd>⇧⌘N</kbd>), with your bouncer's address and port, and set **Bouncer → Type** to ZNC or soju.

## ZNC

ZNC uses **one connection per IRC network**, so add one Vela network for each network on your ZNC (for example "Libera via ZNC" and "OFTC via ZNC").

### Logging in

Use either method. Both tell ZNC which user and which network you want.

- **Server password** (the classic way): set **Authentication → Method** to **Server password** and enter

  ```text
  username/network:password
  ```

  For example `doug/libera:hunter2`, where `libera` is the network's name in ZNC.
- **SASL PLAIN**: set **Account** to `username/network` (for example `doug/libera`) and **Password** to your ZNC password.

### TLS and certificates

Match Vela's settings to your ZNC listener:

- **Your listener uses SSL/TLS** (`SSL = true` in ZNC): leave **Use TLS** on.
- **ZNC uses a self-signed certificate** (the default when ZNC generates its own `znc.pem`): also turn on **Allow invalid certificates**. Otherwise the connection fails certificate validation.
- **Your listener is plain text**: turn **Use TLS** off. Only do this on a network you trust, because your password is then sent unencrypted.

The port is whatever you configured for the listener in ZNC; it's often not 6697.

### What Vela does with ZNC

- **Playback.** If ZNC's `playback` module is loaded, Vela asks for only the messages it hasn't seen yet each time it connects, so nothing is shown twice.
- **Your own messages from other clients.** With `self-message`, messages you send from another client connected to the same ZNC appear in Vela too. Vela and your other clients can stay connected at the same time.
- **Accurate timestamps** with `server-time`.
- **Channels.** ZNC rejoins your channels itself, so Vela doesn't send its own joins. The **Channels** list in the network editor is only used for direct connections.
- **Talking to ZNC.** Send commands to ZNC's modules as usual, for example `/msg *status help`.

::: info Reactions, replies and typing
These need IRCv3 message tags. Some bouncers, including older ZNC versions, don't pass them through. Vela notices and hides the reaction and reply buttons on those connections.
:::

## soju

soju uses **one connection for all your networks**. Add it once:

1. Enter your soju server's address and port.
2. Set **Authentication → Method** to **SASL PLAIN**, with your soju username as the **Account** and your soju password.
3. Set **Bouncer → Type** to **soju** and click **Add Network**.

Vela connects, asks soju for your networks, and adds each one under the bouncer in the sidebar, with its own channels and history. Networks you add or remove on soju (for example with `/msg BouncerServ network create`) appear and disappear in Vela automatically. The bouncer entry itself only shows its server console.

The bouncer's networks always stay under it. Drag them to change their order there, or drag the bouncer to move it and its networks together. See [Arranging networks and channels](/guide/the-window#arranging-networks-and-channels).

Each network provided by soju uses the bouncer's server, identity and login. You can still rename it and give it its own perform commands, highlight words, ignore list and auto-connect setting; edit the bouncer to change everything else.

### History

soju supports `chathistory`, so Vela fetches the messages you missed when it connects, and scrolling up past what's stored on your Mac loads older history from the bouncer.

## Troubleshooting

See [Can't connect](/help/troubleshooting#cant-connect) for the common causes: TLS on a plain-text port (or the other way around), a self-signed certificate, the ZNC password format, and firewalls.
