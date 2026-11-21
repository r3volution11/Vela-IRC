---
title: Updates
description: Vela updates itself. How it checks for new versions, when it offers them, the settings for checking and installing automatically, and what an update check sends.
---

# Updates

Vela updates itself. Once a day it checks for a new version, and when there's one, it offers it at a moment that suits you: when you open Vela, or when you come back to your Mac after a while. It never interrupts you in the middle of a conversation.

Every update is signed, and Vela checks the signature before it installs anything. Your networks, settings, themes and saved history stay as they are.

::: tip Still on Vela 1.0?
Vela updates itself from version 1.1. Version 1.0 has no updater, so it never offers a new version: download the latest version once, as [Install → From Vela 1.0](/guide/install#from-1-0) explains, and from then on updates come to you.
:::

## Checking for updates

Choose **Vela → Check for Updates…**. If there's a new version, a window shows what's new in it, with three choices:

- **Install Update** downloads it, quits Vela, installs it and opens Vela again.
- **Remind Me Later** closes the window. Vela offers the update again later.
- **Skip This Version** doesn't offer this version again. **Check for Updates…** still shows it, if you change your mind.

If Vela is up to date, the window says so.

You can also check from:

- **Vela → About Vela**, which shows your version, whether you're up to date and when Vela last checked, with a **Check for Updates** button.
- **Settings → Updates** (<kbd>⌘,</kbd>).
- The [command palette](/guide/command-palette): **Help: Check for Updates…**.

The first time a new version opens, **What's New in Vela** shows what changed in it. See [Install](/guide/install#updating).

## When Vela offers an update

With **Check for updates automatically** on, Vela checks once a day, in the background. When it finds a new version:

- **Right after you open Vela,** or when your Mac has been idle for a while, it shows the update window.
- **While you're using Vela,** it waits, so the window never takes over while you're typing. The **About** window and **Settings → Updates** say "Version 1.2.0 is available.", and **Check for Updates…** shows it. The next time you open Vela, it offers it.

## Settings

<Screenshot src="/screenshots/settings-updates.webp" alt="Settings → Updates: Vela 1.0.0 with “Vela is up to date. Last checked 2 hours ago.” and a Check for Updates button, then the Automatic updates section with Check for updates automatically on and Install updates automatically off, and a link to what an update check sends" caption="Settings → Updates." />

Open **Settings → Updates**.

| Setting | What it does |
| --- | --- |
| **Check for updates automatically** | On by default. Checks once a day. Off, Vela only checks when you choose **Check for Updates…**. |
| **Install updates automatically** | Off by default. Downloads new versions in the background and installs them the next time you quit Vela, without asking. It needs **Check for updates automatically**. |

**Check for updates automatically** is also in the **About** window. In settings.json, they're [`updates.checkAutomatically`](/reference/settings#updates.checkAutomatically) and [`updates.installAutomatically`](/reference/settings#updates.installAutomatically). The update window's **Automatically download and install updates in the future** box is the same setting as **Install updates automatically**.

With **Install updates automatically** on, Vela doesn't interrupt you to install. Settings and the About window say "Version 1.2.0 will be installed when you quit Vela." If Vela stays open for more than a week, it offers to install the update then, the same way it offers a new version.

## What an update check sends {#privacy}

An update check asks **velairc.app** for its list of releases (the update feed). The request carries what any web request does, such as your IP address, and a User-Agent with Vela's version and the updater's (Sparkle's). Nothing about you, your Mac or how you use Vela is sent: no system profile, no identifier and no usage data.

An update downloads from **GitHub**, where Vela's releases are published. The release notes come with the feed, so the update window loads nothing else.

velairc.app is hosted by GitHub Pages, so GitHub handles both. See [Privacy](/help/privacy#updates). To stop the checks, turn off **Check for updates automatically**.

## Development builds

Vela Dev, the development build you get from building Vela yourself with `scripts/run.sh --dev` or in Xcode, never checks for updates or installs them. Its About window and **Settings → Updates** say "Updates are turned off in development builds.", with the controls turned off.

## Troubleshooting

**The update fails to install.** Make sure Vela is in your **Applications** folder, not running from the disk image or from **Downloads**: macOS doesn't let an app replace itself there. Drag it to Applications, open it from there and check again.

**The check fails.** The status line in **Settings → Updates** shows what went wrong, such as no internet connection. Vela tries again the next day, or choose **Check for Updates** to try now. You can always download the latest **Vela.dmg** from the [Install](/guide/install) page instead.
