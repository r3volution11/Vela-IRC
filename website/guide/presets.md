---
title: Presets
description: Vela's four one-click presets, Classic IRC, Modern Chat, Tabbed and Focus, and exactly which settings each one changes. Presets never change your theme.
---

# Presets

A preset sets up navigation, message layout, density, media and how unread messages show in one click, so you can get a whole style without visiting every setting. **Presets never change your theme**, and they only touch the settings listed below, so anything else you've customized stays as it is.

Apply one from **Settings → Presets**, the **View → Presets** menu, or the [command palette](/guide/command-palette) (type "preset"). Afterwards, change anything you like. The preset stays checked as long as your settings still match it.

## Classic IRC

<Screenshot src="/screenshots/preset-classic.webp" alt="The Classic IRC preset: a sidebar and one-line monospace messages" />

Sidebar tree, one-line messages in a monospace font, dense spacing, minimal link previews and image thumbnails. Feels like [Textual](https://www.textualapp.com) or [irssi](https://irssi.org). Join and part messages are shown individually, and videos get a one-line row whose player opens underneath when you press ▶.

Messages are simply there as they came in: channels open at the newest messages, with no **New** line marking what you haven't read and no **Jump to present** button to press. Unread counts in the sidebar still work. See [Unread messages](/guide/messages-and-layouts#unread-messages). The other presets open channels at the first unread message, with the New line.

::: tip Used Classic IRC before?
Apply it again to get these two settings. Until you do, Settings → Presets shows your setup as Custom.
:::

## Modern Chat

<Screenshot src="/screenshots/preset-modern.webp" alt="The Modern Chat preset: a sidebar, grouped messages and full inline media" />

Sidebar with grouped messages (one name header per run of messages) and full inline media: full-size images, standard link previews and video players. Joins and parts are collapsed into one line.

## Tabbed

<Screenshot src="/screenshots/preset-tabbed.webp" alt="The Tabbed preset: rounded tab stacks across the top instead of a sidebar" />

[Tab stacks](/guide/tab-stacks) across the top instead of a sidebar, grouped messages and rounded tabs, with the member list hidden and the same media as Modern Chat. Great for one network and a few channels.

## Focus

<Screenshot src="/screenshots/preset-focus.webp" alt="The Focus preset: pill tabs in the title bar and compact columns" />

Pill tabs in the title bar, compact columns, no avatars or join/part noise, and the member list hidden. Link previews are minimal and images are thumbnails, but videos still get a full player. Maximum text, minimum chrome.

## What each preset sets

A dash means the preset leaves that setting alone. Click a setting to read what it does.

<!--@include: ../_generated/presets.md-->

## Making your own

There's no "save as preset" yet, but every value is a key in [settings.json](/customize/settings-json), so you can keep your favorite setup in a file and paste it back whenever you like.
