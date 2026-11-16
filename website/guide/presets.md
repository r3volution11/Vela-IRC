---
title: Presets
description: Vela's four one-click presets, Classic IRC, Modern Chat, Tabbed and Focus, and exactly which settings each one changes. Presets never change your theme.
---

# Presets

A preset sets up navigation, message layout, density and media in one click, so you can get a whole style without visiting every setting. **Presets never change your theme**, and they only touch the settings listed below, so anything else you've customized stays as it is.

Apply one from **Settings → Presets**, the **View → Presets** menu, or the [command palette](/guide/command-palette) (type "preset"). Afterwards, change anything you like. The preset stays checked as long as your settings still match it.

## Classic IRC

<Screenshot src="/screenshots/preset-classic.webp" alt="The Classic IRC preset: a sidebar and one-line monospace messages" />

Sidebar tree, one-line messages in a monospace font, dense spacing and compact link titles. Feels like Textual or irssi. Join and part messages are shown individually, and video links show a title line instead of a player.

## Modern Chat

<Screenshot src="/screenshots/preset-modern.webp" alt="The Modern Chat preset: a sidebar, grouped messages and full inline media" />

Sidebar with grouped messages (one name header per run of messages) and full inline media: large images, link cards and video players. Joins and parts are collapsed into one line.

## Tabbed

<Screenshot src="/screenshots/preset-tabbed.webp" alt="The Tabbed preset: rounded tab stacks across the top instead of a sidebar" />

[Tab stacks](/guide/tab-stacks) across the top instead of a sidebar, grouped messages and rounded tabs, with the member list hidden. Great for one network and a few channels.

## Focus

<Screenshot src="/screenshots/preset-focus.webp" alt="The Focus preset: pill tabs in the title bar and compact columns" />

Pill tabs in the title bar, compact columns, no avatars or join/part noise, the member list hidden and compact previews. Maximum text, minimum chrome.

## What each preset sets

A dash means the preset leaves that setting alone. Click a setting to read what it does.

<!--@include: ../_generated/presets.md-->

## Making your own

There's no "save as preset" yet, but every value is a key in [settings.json](/customize/settings-json), so you can keep your favorite setup in a file and paste it back whenever you like.
