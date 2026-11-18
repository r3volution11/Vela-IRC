---
title: App icon
description: Vela's icon, a V with a star in its notch, and how to choose one of six versions of it for the Dock and app switcher, from Settings, the command palette or settings.json.
---

# App icon

Vela's icon is a glass **V** on a navy background, with a small four-point star in its notch. *Vela* is Latin for "the sails", and it's also the name of a constellation in the southern sky; the star is a nod to it.

The icon comes in six versions. The standard one, **Vela**, is what macOS shows in Finder, Spotlight and the Apps list. The other five are alternatives for the Dock.

<Screenshot src="/screenshots/app-icons.webp" light="/screenshots/app-icons-light.webp" alt="Vela's six icons in a row: Vela (navy with a cyan V), Midnight (near-black with a pale ice V), Graphite (charcoal with a silver V), Sunrise (deep plum with a peach-to-coral V and a warm star), Paper (white with a deep blue V) and Vivid (bright blue with a white V)" caption="Vela, Midnight, Graphite, Sunrise, Paper and Vivid." />

## Choosing a Dock icon {#choosing}

Go to **Settings → Appearance → Dock icon** and click an icon. The Dock changes straight away, and Vela uses your choice each time it opens.

| Icon | Looks like |
|---|---|
| **Vela** (the default) | The standard icon: navy, with a cyan V and a white star. |
| **Midnight** | Near-black, with a pale ice V. |
| **Graphite** | Charcoal, with a silver V. |
| **Sunrise** | Deep plum, with a peach-to-coral V and a warm star. |
| **Paper** | White, with a deep blue V and star. |
| **Vivid** | Bright blue, with a white V. |

<Screenshot src="/screenshots/settings-app-icon.webp" alt="Settings → Appearance: the Dock icon section, with the App icon row showing six small icons and a ring around Sunrise, above the note about where the icon shows" caption="Dock icon, near the bottom of Settings → Appearance." />

Hover an icon for its name. A ring marks the one in use, and the row's description names it.

From the [command palette](/guide/command-palette): **Appearance: Next App Icon** steps through the six (after Vivid, it's back to Vela), and **Appearance: App Icon: Vela**, **Midnight**, **Graphite**, **Sunrise**, **Paper** or **Vivid** picks one.

## Where your choice shows {#where-it-shows}

The icon you choose shows in the **Dock** and the **app switcher** (<kbd>⌘Tab</kbd>) while Vela is open. Everywhere else, macOS shows the standard icon:

- in **Finder**, **Spotlight**, the **Apps** list and **notifications**;
- in the **Dock while Vela is quit**, if you keep it there;
- for a moment as Vela opens, before it switches to your choice.

That's a limit of macOS, not a setting you've missed. Mac apps can't switch icons the way iPhone and iPad apps can. While an app is running it can change its Dock icon, but the icon Finder and Spotlight show is part of the app itself. Vela never changes its own app: it's sandboxed, and its files are signed and notarized by Apple, so they stay exactly as they were installed.

## Icon & widget style {#icon-and-widget-style}

macOS 26 lets you choose how every app icon looks, in **System Settings → Appearance → Icon & widget style**:

- **Default:** full color.
- **Dark:** a darker background.
- **Clear:** see-through glass, light, dark or automatic.
- **Tinted:** glass in one color of your choice.

The standard Vela icon is built for all four: its V and star are separate layers of Liquid Glass, so macOS can restyle them like the icons of Apple's own apps. You'll see the style you pick in Finder, Spotlight and the Apps list, and in the Dock when you've chosen **Vela**.

The other five icons are fixed pictures. They look the same whatever your Icon & widget style is. If you use Dark, Clear or Tinted and want the Dock to match the rest of your icons, choose **Vela**.

When a network goes offline, Vela draws a small amber [offline mark](/guide/notifications#offline) on whichever icon you chose. To draw it on the standard icon, Vela shows a picture of it in the Dock, so it may not follow Dark, Clear or Tinted until the network is back and the mark goes away.

## In settings.json {#settings-json}

The choice is saved in [settings.json](/customize/settings-json) as [`appearance.appIcon`](/reference/settings#appearance.appIcon):

```jsonc
{
    // vela (the default), midnight, graphite, sunrise, paper or vivid
    "appearance.appIcon": "sunrise"
}
```

Vela picks up a change as soon as you save the file. An unknown value is ignored, and Vela shows the standard icon.
