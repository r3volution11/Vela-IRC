---
title: Install
description: Download Vela for macOS, install it from the disk image, and keep it up to date. Vela needs macOS 26 or later and runs on Apple silicon and Intel Macs.
---

# Install Vela

<DownloadCard />

## Requirements

- **macOS 26 Tahoe or later.**
- **Apple silicon or Intel.** Vela is a universal app, so the same download runs natively on both.
- **For Catch me up and Writing Tools,** a Mac with Apple silicon and Apple Intelligence turned on. Everything else, translation included, works without it. See [Apple Intelligence & translation](/guide/apple-intelligence#requirements).

## Install from the disk image

1. Download **[Vela.dmg](https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg)**. It's always the latest release.
2. Open the downloaded file. A window with the Vela icon and your Applications folder appears.
3. Drag **Vela** onto **Applications**.
4. Eject the disk image, then open Vela from the Applications folder or Spotlight.

Every release is signed with a Developer ID and notarized by Apple, so macOS opens it without a security warning. The first time, macOS may still ask you to confirm that you want to open an app downloaded from the internet. Click **Open**.

::: tip Next
Continue with [First launch](/guide/first-launch) to add your first network.
:::

## Updating

Vela updates itself. It checks for a new version once a day and offers it when you open Vela, never in the middle of a conversation; **Vela → Check for Updates…** checks right away. See [Updates](/guide/updates) for the settings and what a check sends.

Vela 1.0 doesn't have the updater yet. To update from it, or any time you'd rather do it yourself:

1. Quit Vela (<kbd>⌘Q</kbd>).
2. Download the latest **Vela.dmg** and drag Vela into Applications again. Choose **Replace** when asked.

Your networks, settings, themes and saved history are kept. They live outside the app, so replacing it doesn't touch them.

The first time the new version opens, **What's New in Vela** shows what changed in it, with anything you need to know first, such as a setting that works differently now. Press <kbd>Return</kbd> or <kbd>Esc</kbd> to close it, and choose **Help → What's New in Vela** (or **Help: What's New in Vela** in the [command palette](/guide/command-palette)) to see it again. The [changelog](/changelog) lists what changed in every release.

## Uninstalling

1. Quit Vela and drag it from Applications to the Trash.
2. To remove your data too, delete Vela's container folder:

   ```text
   ~/Library/Containers/io.github.r3volution11.Vela
   ```

   It holds your settings, networks, themes and message history, and your [chat logs](/guide/chat-logs) unless you chose another folder for them. In Finder, choose **Go → Go to Folder…** (<kbd>⇧⌘G</kbd>) and paste the path.
3. Saved passwords, channel keys and client certificates are in your login keychain. Open **Keychain Access** and search for `io.github.r3volution11.Vela` to remove them.

## Building from source

Vela is open source. If you'd rather build it yourself, you need Xcode 27 or later:

```sh
git clone https://github.com/r3volution11/Vela-IRC.git
cd Vela-IRC
scripts/run.sh          # builds and launches build/Vela.app
```

See the [README](https://github.com/r3volution11/Vela-IRC#building-from-source) for details.
