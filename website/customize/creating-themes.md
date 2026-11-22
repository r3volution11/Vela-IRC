---
title: Creating themes
description: A step-by-step guide to making Vela themes, in the theme editor or as a JSON file of color tokens. Themes set colors only, never layout, and Vela draws their previews for you.
---

# Creating themes

A Vela theme is a small JSON file that gives a color to each part of the window. You can make one in the [theme editor](/customize/theme-editor) without seeing any JSON, or write the file yourself in any text editor. This guide covers both, step by step, from a three-color theme to one ready to share.

::: tip Themes are colors, and only colors
A Vela theme changes **colors** (plus, optionally, whether the window is see-through) and nothing else. Unlike themes for some IRC clients or browsers, a Vela theme can't change the layout, fonts, text size, spacing, icons or how anything behaves. Those are your [settings](/customize/settings-json) and [presets](/guide/presets), so **every theme works with every layout**, and you can switch themes as often as you like without losing your setup.
:::

## Colors only, by design {#colors-only}

How Vela looks is split between the theme and your settings:

| A theme decides | Your settings decide |
| --- | --- |
| Every color: backgrounds, text, borders, badges, buttons, highlights, link previews, the Settings window | [Sidebar or tab stacks](/guide/the-window#sidebar-or-tabs), tab placement and roundness |
| The palette nicknames are colored from | The [message layout](/guide/messages-and-layouts): Classic, Modern grouped or Compact columns |
| The 99 [mIRC](https://www.mirc.com) colors other people's colored text uses | Fonts, text size, line spacing and density |
| Whether it's a dark or a light theme, which macOS follows for menus and alerts | Avatars, timestamps and their format, and whether nicks are colored at all |
| Translucency (`vibrancy`) | The member list, link previews, images and videos |

So a theme you design with the Modern Chat preset also looks right in Classic IRC, Tabbed or Focus, and trying a new theme never resets your fonts or layout. Think of a Vela theme as a palette: your settings decide the shape of the window, the theme decides its colors.

Theme files have no keys for anything else. If a file has one anyway (say, `"font": "Menlo"`), Vela loads the theme, ignores that key and says so in **Settings → Appearance**: "“font” isn't a theme key, so it's ignored. Themes only contain colors: fonts, sizes and layout are settings." (See [Typos and skipped values](#problems).) To change layout or type, use **Settings** (<kbd>⌘,</kbd>), the [settings reference](/reference/settings) or a [preset](/guide/presets).

## Quick start {#quick-start}

There are two ways to start. Both end with an ordinary theme file in your Themes folder, so you can move between the theme editor and a text editor at any time. (Saving from the theme editor writes the file in Vela's own format, without comments.)

### Start from a theme in the theme editor {#start-in-the-editor}

The quickest way to a polished theme is to start from one you like:

1. Open **Settings → Appearance** (<kbd>⌘,</kbd>). Right-click the theme you want to start from in the gallery and choose **Customize in Theme Editor…**.

   (**Theme → Theme Editor…** and **Settings → Appearance → Customize…** open the editor on the theme you're using now.)
2. The editor opens a copy. A built-in theme's copy is named after it, such as "Nord Custom", so the original is never changed. Type your own name in **Name**, and leave **Dark** or **Light** as it is unless you're changing the backgrounds from dark to light or back.
3. Change colors. Pick a group on the left (**Window**, **Sidebar**, **Chat** and so on) or type in **Search tokens**, then click a color well or type a hex value. Every Vela window, including the editor itself, shows the change as you make it.
4. Press **Save** (<kbd>⌘S</kbd>). Vela writes the theme to your Themes folder as a file named after it (`nord-custom.json`), switches to it, and the status bar says "Saved “Nord Custom” to your Themes folder and made it your theme." With **Match System Appearance** on, it becomes your Dark Mode or Light Mode theme, depending on its type.
5. The theme now has a card in the gallery, marked **Yours**. To keep refining it in a text editor, right-click the card and choose **Show in Finder**.

::: warning Changing a base color may not change much
A built-in theme sets nearly every color itself, and the copy keeps all of them. So changing, say, `accent` changes only the colors that still follow it, which in a copy of a built-in theme is very few. To recolor everything that uses the accent, change those tokens too. (To switch to another of the theme's own colors without making a theme, the [accent color](/customize/themes#accent-color) picker in Settings does all of that for you.) In the editor, a token marked **Set** keeps its own color; one marked **Inherited** follows the others. See [How defaults work](#how-defaults-work).
:::

### Write a theme file from scratch {#start-from-a-file}

A theme file can be tiny, because Vela works out every color you leave out:

1. Open the Themes folder: **Settings → Appearance → Reveal Themes Folder**, or **Theme → Reveal Themes Folder**. Finder shows the folder, creating it if needed.
2. In a code editor ([VS Code](https://code.visualstudio.com), [Zed](https://zed.dev), [Nova](https://nova.app), [BBEdit](https://www.barebones.com/products/bbedit/) and so on), create a file called `harbor.json` in that folder with this in it:

   ```jsonc
   {
     "$schema": "https://raw.githubusercontent.com/r3volution11/Vela-IRC/main/schemas/vela-theme.schema.json",
     "name": "Harbor",
     "type": "dark",
     "colors": {
       "window.background": "#1D2733",
       "window.foreground": "#D3DCE6",
       "accent": "#F2A65A"
     }
   }
   ```

3. Save it. **Harbor** appears in the **Settings → Appearance** gallery right away, marked **Dark · Yours**, with a preview card drawn in its colors. There's no need to restart Vela.
4. Click its card to use it, or press <kbd>⌃⌘T</kbd>, type "harbor" and press <kbd>Return</kbd>.
5. Keep the file open. Every time you save it, Vela reloads the theme and the whole window updates.

Those three colors are enough for a complete, readable theme: the sidebar, member list, text shades, links, badges and buttons are all worked out from them. The smallest valid theme is just a name and a type, `{ "name": "Bare", "type": "dark" }`, which gets every color from Vela's defaults.

::: tip Use a code editor
macOS may ask whether your editor can access data from other apps the first time it opens the Themes folder, because the folder is inside Vela's container; allow it. Avoid TextEdit if you can: it saves rich text and turns straight quotes into curly ones, which aren't valid JSON. If you do use it, choose **Format → Make Plain Text** and turn off **Edit → Substitutions → Smart Quotes**.
:::

You can also write a theme anywhere and bring it in with **Theme → Import Theme…**. Import rewrites the file in Vela's own format, so comments aren't kept; to keep them, put the file in the Themes folder yourself.

### Where your themes live {#where-themes-live}

Vela is sandboxed, so the Themes folder is inside its container:

```text
~/Library/Containers/io.github.r3volution11.Vela/Data/Library/Application Support/Vela/Themes
```

- **Every `.json` or `.jsonc` file directly in this folder is a theme.** Files in subfolders and hidden files (names starting with a dot) are ignored.
- **A theme's id is its file name** without the extension (`harbor`), and its **name** is the `name` in the file ("Harbor"). Settings accept either, in any case. Give each theme a name no other theme uses.
- **Vela watches the folder.** Adding, changing, renaming or deleting a file updates the gallery, and the window if it's the theme in use, within a moment.
- **A mistake never breaks the window.** If you save a file with an error in it, Vela keeps using the last version that worked and explains the problem in **Settings → Appearance**. See [Troubleshooting](#troubleshooting).
- **Replacing a built-in theme:** a file named like a built-in theme (for example `nord.json`) takes that theme's place in the gallery. It can still start from the original with `"include": "Nord"`.

## Anatomy of a theme file {#the-theme-file}

Here's a theme with every key filled in. Only `name` and `type` are required.

```jsonc
{
  // Lets your editor autocomplete and check the file. Optional.
  "$schema": "https://raw.githubusercontent.com/r3volution11/Vela-IRC/main/schemas/vela-theme.schema.json",

  // Required.
  "name": "Harbor",
  "type": "dark",

  // Optional details about the theme.
  "author": "Your Name",
  "description": "Blue-grey surfaces with a warm amber accent.",

  // Optional. Uncomment to start from another theme instead of the defaults.
  // "include": "Palenight",

  // Token → color. Anything you leave out is worked out from the rest.
  "colors": {
    "window.background": "#1D2733",
    "window.foreground": "#D3DCE6",
    "accent": "#F2A65A",
    "chat.link": "#7FB8E6",
  },

  // The palette nicknames are colored from.
  "nickColors": ["#F28C8C", "#F2A65A", "#E8D27A", "#A6D98C", "#7FD1C2", "#7FB8E6", "#A99BF0", "#E39BD9"],

  // mIRC colors by number; list only the ones you change.
  "ircColors": { "1": "#141B24", "2": "#5B8FD6", "4": "#F07B7B" },

  // "none" (the default), "sidebar" or "window": see Translucency.
  "vibrancy": "none",
}
```

Theme files are JSON with comments: `//` and `/* */` comments and trailing commas are fine.

| Key | Type | Required | What it does |
| --- | --- | --- | --- |
| `$schema` | String | No | The address of Vela's theme schema, so your editor can autocomplete and check the file. See [below](#schema). |
| `name` | String | **Yes** | The name shown in the gallery and in Select Theme. Settings refer to the theme by this name or by its file name. Can't be empty. |
| `type` | `"dark"` or `"light"` | **Yes** | Picks the defaults for colors you don't set, and whether macOS draws menus and alerts light or dark. See [Light and dark](#light-and-dark). VS Code's `"vs-dark"`, `"vs"`, `"hc-black"` and `"hc-light"` work too. |
| `author` | String | No | Who made the theme. Shown when you hover the theme's card in **Settings → Appearance** or its name in **Select Theme** (<kbd>⌃⌘T</kbd>), and in the [theme editor](/customize/theme-editor). |
| `description` | String | No | One sentence about the theme, shown with the author in the same places. For built-in themes it also appears on the [Built-in themes](/reference/built-in-themes) page. |
| `include` | String | No | Another theme to start from, by name or id: `"Palenight"`. See [Building on another theme](#building-on-another-theme). |
| `colors` | Object | No | Token name → color: `"chat.background": "#1E2030"`. Anything you leave out is [worked out from the rest](#how-defaults-work). See [Color tokens](#tokens). |
| `nickColors` | Array of colors | No | The palette for nicknames: `["#F28C8C", "#A6D98C", …]`. Replaces the default palette. See [Nick colors](#nick-colors). |
| `ircColors` | Object | No | mIRC color number (`"0"` to `"98"`) → color: `{ "4": "#F07B7B" }`. Only the numbers you list change. See [mIRC colors](#irc-colors). |
| `vibrancy` | `"none"`, `"sidebar"` or `"window"` | No | Whether parts of the window use macOS's translucent materials. Defaults to `"none"`. See [Translucency](#translucency). |

There are no other keys. In particular, there's nothing for fonts, sizes, spacing, layout or images: see [Colors only, by design](#colors-only). Vela warns about any other key, and about token names it doesn't know: see [Typos and skipped values](#problems).

### Writing colors {#color-values}

Colors are hex strings in one of four forms, with or without capitals:

| Form | Example | Meaning |
| --- | --- | --- |
| `#RGB` | `"#F80"` | Short for `#FF8800`. |
| `#RRGGBB` | `"#FF8800"` | An opaque color. |
| `#RGBA` | `"#F808"` | Short for `#FF880088`. |
| `#RRGGBBAA` | `"#FF880033"` | A color with transparency: `00` is invisible, `FF` is opaque. |

Transparency works for every token. It's the easiest way to make hover and selection highlights that look right on any background: `"chat.hoverBackground": "#FFFFFF0A"` is a 4% white wash, whatever the conversation's color.

### Autocomplete with `$schema` {#schema}

The `"$schema"` line points to Vela's [theme schema](https://github.com/r3volution11/Vela-IRC/blob/main/schemas/vela-theme.schema.json), which lists every key and token. Editors that understand JSON Schema, including VS Code, Zed and Nova, then:

- autocomplete token names as you type inside `colors`,
- show each token's description and default when you hover it,
- underline typos, unknown keys and malformed colors.

Vela checks the same things itself when it loads the file, and lists what it skipped in **Settings → Appearance** and the theme editor, so you don't need a schema-aware editor to catch typos. See [Typos and skipped values](#problems).

In VS Code, a `.json` file with comments shows "Comments are not permitted in JSON". Name the file `.jsonc` instead (Vela reads both), or click **JSON** in the status bar and choose **JSON with Comments**.

## Color tokens {#tokens}

Each color in a theme belongs to a **token**: a name for one part of the window, such as `sidebar.background` (the sidebar's background) or `chat.timestamp` (the timestamps on messages). Vela has 129 tokens in 13 groups, each named after the part of the window it colors:

| Group | Tokens | Colors |
| --- | --- | --- |
| [Window](/reference/theme-tokens#window) | 4 | The base background and text colors most other tokens are worked out from, and dividers. |
| [Title bar](/reference/theme-tokens#title-bar) | 4 | The bar above the conversation: channel name, topic and buttons. |
| [Sidebar](/reference/theme-tokens#sidebar) | 15 | The list of networks and channels: selected, unread and mentioned channels, badges, disconnected networks. |
| [Rail](/reference/theme-tokens#rail) | 8 | The collapsed, icon-only sidebar. |
| [Tabs](/reference/theme-tokens#tabs) | 16 | Tab stacks, when you use tabs instead of the sidebar. |
| [Chat](/reference/theme-tokens#chat) | 29 | The conversation: message text, timestamps, links, your nick, mentions, joins and parts, notices, errors, day dividers, the New line, selection and code. |
| [Input](/reference/theme-tokens#input) | 7 | The message field and the bar around it. |
| [Member list](/reference/theme-tokens#member-list) | 7 | The channel's member list. |
| [Embeds](/reference/theme-tokens#embeds) | 7 | Link previews and media cards. |
| [Reactions, replies & typing](/reference/theme-tokens#reactions-replies-typing) | 9 | Reactions, reply quotes and "is typing" lines. |
| [Controls](/reference/theme-tokens#controls) | 14 | The accent, buttons, focus rings and popovers such as the command palette. |
| [Status](/reference/theme-tokens#status) | 3 | Success, warning and error colors, such as connection states. |
| [Settings window](/reference/theme-tokens#settings-window) | 6 | The Settings window and the theme editor. |

Token names follow a pattern: the part of the window, a dot, then the role. The common roles are:

- `background` and `foreground` (text and icons), plus `secondaryForeground` for quieter text and `border`;
- states: `hover…` (under the pointer), `active…` (selected), `unread…` (has new messages), `highlight…` (mentions you), `disconnected…` and `inactive…`;
- `badge…` for count badges, and `chat.event.join`, `chat.event.part` and so on for each kind of event line.

The [theme token reference](/reference/theme-tokens) lists every token in a table with four columns: the **token** name to use in `colors`, a **description** of what it colors, and its **dark default** and **light default**, the value it gets when you don't set it (see [How defaults work](#how-defaults-work)). The theme editor shows the same descriptions and defaults, and you can search them there.

### Where to start {#where-to-start}

You don't need to set all 129. A good order:

1. **The base:** `window.background`, `window.foreground` and `accent`. That's already a complete theme.
2. **Surfaces:** `sidebar.background`, `chat.background` and `memberList.background`, if they should differ from what's worked out.
3. **Text shades:** `chat.secondaryForeground`, `chat.timestamp`, `sidebar.foreground` and `sidebar.secondaryForeground`.
4. **You and mentions:** `accentText`, `chat.link`, `chat.selfNick`, `chat.mention`, `chat.highlightBackground` and `chat.highlightBorder`.
5. **Meaning:** the `chat.event.*` colors, `chat.notice`, `chat.error` and the `status.*` colors.
6. **Palettes:** `nickColors` and `ircColors` 0–15.
7. **The rest**, if you use them: embeds, reactions, tabs, the rail and the Settings window.

### The accent tokens {#accent-tokens}

Three tokens work together:

- **`accent`** is the theme's signature color, used for **fills**: the selected channel, mention badges, buttons, focus rings and the active tab.
- **`accentText`** is the accent used **as text** on the conversation's background: links, your nick and mentions. Dark themes use `accent` itself; light themes default to a darker shade, because a bright accent that works as a fill is often too light to read as text. Set it when your accent is too light or too dark to read.
- **`accentForeground`** is text drawn **on** the accent, such as the number on a mention badge. By default, Vela picks white or a dark shade of the accent, whichever reads better.

## How defaults work {#how-defaults-work}

Every token has a default for dark themes and one for light themes, and most defaults are **worked out from other tokens**. That's why a three-color theme looks complete. For example, in a dark theme:

```text
memberList.background → sidebar.background → mix(window.background, #000000, 16%)
```

The member list uses the sidebar's background, and the sidebar's background is the window's background mixed 16% of the way toward black. So with only `window.background` set, the sidebar and member list come out a little darker than the conversation, in the same hue.

Set a token and it **breaks the chain** at that point. This version of Harbor gives the sidebar a lighter blue of its own, and the member list follows it, because it still uses the sidebar's color:

```jsonc
{
  "name": "Harbor",
  "type": "dark",
  "colors": {
    "window.background": "#1D2733",
    "window.foreground": "#D3DCE6",
    "accent": "#F2A65A",
    "sidebar.background": "#263445"
  }
}
```

Set `memberList.background` too, and only the member list changes.

Defaults in the [token reference](/reference/theme-tokens) are written as expressions:

| Expression | Meaning |
| --- | --- |
| `#RRGGBB` | A fixed color. |
| `token.name` | The same color as another token. |
| `mix(a, b, 30%)` | `a` blended 30% of the way toward `b`. |
| `transparent(a, 20%)` | `a` with its opacity multiplied by 20%. |
| `contrast(a)` | White, or a near-black tinted with `a`'s hue, whichever reads better on `a`. |

Where a color comes from, from lowest to highest priority:

1. the token's default for the theme's `type`,
2. the [included](#building-on-another-theme) theme or themes, deepest first,
3. the theme's own `colors`,
4. `appearance.colorCustomizations` in [settings.json](/customize/settings-json#color-customizations) for every theme,
5. `appearance.colorCustomizations` for this theme, in a `"[Theme Name]"` block.

Steps 4 and 5 are your own overrides, including the accent and message box border colors you pick in Settings. They apply on top of any theme, without changing its file.

::: tip Set means fixed, inherited means it follows
A color that's set (by you, or by a theme you start from) stays put when you change the colors it would otherwise follow. The theme editor marks each token **Set** or **Inherited**, and shows the default of every inherited one. To make a set token follow the others again, click its reset arrow, or delete it from `colors`.
:::

## Nick colors and mIRC colors {#nick-colors-and-mirc-colors}

Besides tokens, a theme has two palettes.

### Nick colors {#nick-colors}

`nickColors` is the list of colors nicknames are drawn in, when **Colored nicknames** is on in **Settings → Messages**: on messages, in the member list, and where a message mentions someone (unless **Color nicks in messages** is off). Avatars are tinted from it too. Your own nick isn't from the palette; it uses `chat.selfNick` everywhere.

```jsonc
"nickColors": ["#F28C8C", "#F2A65A", "#E8D27A", "#A6D98C", "#7FD1C2", "#7FB8E6", "#A99BF0", "#E39BD9"]
```

- **How many:** aim for 8 to 12 clearly different hues. Vela's own palettes have 12. More colors means fewer people share one.
- **How they're handed out:** each nick starts from the color its name points to, so it usually keeps the same color in every channel. People talking in the same conversation get different colors while the palette has room, and someone whose color would look like the person they're talking with gets the nearest color that's clearly different. See [Colors and formatting](/guide/messages-and-layouts#colors-and-formatting).
- **Look-alikes are spread apart:** when the theme loads, palette colors that look alike (Palenight's blue and lavender, say) are nudged a little apart: a slight turn of the hue first, then a touch lighter or darker, then a touch less vivid. A color never moves far from what you wrote (an OKLab distance of 0.06 at most, no more than 25° of hue, and never losing more than a third of its vividness), stays at 3:1 or better and clear of the text color, and a color that looks like no other is used exactly as written. The clearer your colors are to begin with, the less Vela changes them.
- **The readability filter:** Vela skips a palette color that would read as plain text (the same as, or a grey close to, `chat.foreground`) or that's below **3:1** contrast against `chat.background`. If skipping would leave too few colors to tell people apart (fewer than four), it uses your palette as written.
- **Your own color is yours:** palette colors that look like `chat.selfNick` (your own nick's color, which is in every conversation) are never given to anyone else. It's fine to have `chat.selfNick` in the palette, as many themes do; a nick that would land on it, or on a color close to it, gets the nearest color that isn't. "Close" is the same measure Vela uses to keep two people talking apart (an OKLab distance under 0.11, about the gap between a blue and a lavender). A color only just too close is nudged off yours instead, when a small change makes it clearly different from yours and from the rest of the palette, so it can still be handed out. At least four colors always stay to hand out, so in a small palette only the closest are held back.
- **Aim higher than the minimum:** 4.5:1 against `chat.background` keeps nicks easy to read. The theme editor marks a color under 3:1 with a dot; hover it for the ratio.
- **Leave it out** and the theme gets Vela's default palette for its type. An empty list does the same. Setting `nickColors` replaces the whole default palette.

### mIRC colors {#irc-colors}

`ircColors` are the colors behind mIRC formatting codes, which other IRC clients use to send colored text (when **mIRC formatting** is on in **Settings → Messages**). They're numbered from 0 to 98:

- **0 to 15** are the classic colors: white, black, blue, green, red, brown, magenta, orange, yellow, light green, cyan, light cyan, light blue, pink, grey and light grey. These are worth tuning so they read well on your background.
- **16 to 98** are the standard extended palette. They rarely need changing.

List only the numbers you change, as strings:

```jsonc
"ircColors": { "1": "#141B24", "2": "#5B8FD6", "4": "#F07B7B" }
```

mIRC colors are used for backgrounds too (white text on black, say), so keep 0 light and 1 dark. The theme editor shows 0–15 under **mIRC colors 0–15**.

Both palettes also feed the [accent color](/customize/themes#accent-color) picker in **Settings → Appearance**, which offers the nick colors and mIRC colors 0–15 that work as an accent. A theme with a few clear, distinct hues gives people more to choose from.

## Translucency {#translucency}

`vibrancy` is the one key in a theme that isn't a color. It puts parts of the main window on macOS's translucent materials, the frosted surfaces Finder and Mail use for their sidebars, so your desktop and the windows behind Vela show through, blurred. Like the rest of a theme, it only changes how things look:

| Value | What sits on a material |
| --- | --- |
| `"none"` (default) | Nothing. Every surface is painted in exactly the colors in your theme. All the built-in themes use this. |
| `"sidebar"` | The sidebar (and the collapsed rail), on the macOS sidebar material. With tab stacks instead of the sidebar, the tab bars: the strip above or below the conversation, or the title bar when the tabs are in it. The conversation, message bar and member list stay opaque. |
| `"window"` | The whole main window. The sidebar and rail use the sidebar material, as with `"sidebar"`; the title bar, tab bars, conversation, message bar and member list use the window material. |

**Your colors tint the material.** On a material, each surface's background token is drawn on top of it as a tint, so the theme still decides the colors:

- **An opaque color tints at 70%.** `"sidebar.background": "#1E2030"` lets 30% of the material through. Every theme, including the built-in ones, works with vibrancy without any other change.
- **A color with its own transparency is used exactly as written**, so you choose the strength: `"#1E2030E6"` (90%) is a light frost, `"#1E203080"` (50%) a strong one, and `"#1E203000"` shows the bare material.
- **The tokens this applies to** are the surface backgrounds: `sidebar.background` and `rail.background`; `tab.barBackground` and `tab.serverBackground` (and `titleBar.background` for tabs in the title bar); and with `"window"`, also `titleBar.background`, `chat.background`, `input.containerBackground` and `memberList.background`. With `"window"`, the full-width backgrounds of messages that mention you (`chat.highlightBackground`) and of your own messages (`chat.selfMessageBackground`) are tinted the same way, so they don't show as solid bands.
- **Everything drawn on top stays as you set it:** text, the selected row, badges, the message field, link previews, reactions and so on.
- **Inactive windows look opaque.** As in Finder, the material turns solid while Vela's window isn't the frontmost one, so a translucent theme looks a little different in the background.

**Reduce Transparency turns it off.** With **Reduce Transparency** on in **System Settings → Accessibility → Display**, Vela draws every theme as if `vibrancy` were `"none"`. **Settings → Appearance → Details → Translucency** shows the current theme's value, and says "(off)" when Reduce Transparency wins.

**Only the main window.** The Settings and Theme Editor windows are always opaque.

To try it without editing a file, use **Translucency** (**None**, **Sidebar** or **Window**) in the [theme editor](/customize/theme-editor), which previews it across Vela, or add `"vibrancy"` for that theme in [`appearance.colorCustomizations`](/customize/settings-json#color-customizations):

```jsonc
"appearance.colorCustomizations": {
  "[Palenight]": { "vibrancy": "sidebar" }
}
```

::: tip Contrast checks still count
Text on a material sits over whatever is behind the window. So for a theme with `vibrancy`, the [contrast checks](#checking-contrast) measure each surface on a material as its tint over a stand-in for the least favorable desktop: the material over white for a dark theme, over black for a light one. Text that only just passes on an opaque background may need a little more contrast, or a stronger tint.
:::

## Building on another theme {#building-on-another-theme}

`include` starts your theme from another one, so your file holds only what's different. The value is a theme's name or id: a built-in theme or one of yours.

```jsonc
{
  "name": "Palenight Midnight",
  "type": "dark",
  "include": "Palenight",
  "colors": {
    "window.background": "#1B1E2B",
    "titleBar.background": "#1B1E2B",
    "chat.background": "#1B1E2B",
    "input.containerBackground": "#1B1E2B",
    "settings.background": "#1B1E2B"
  }
}
```

Here's what you get from the included theme:

| Key | From the included theme |
| --- | --- |
| `colors` | Every color it sets, merged with yours. Yours win. |
| `ircColors` | Every mIRC color it sets, merged with yours. Yours win. |
| `nickColors` | Its palette, unless you set your own. |
| `vibrancy` | Its setting, unless you set your own. (`"none"` turns off an included theme's vibrancy.) |
| `name`, `type`, `author`, `description` | Nothing. These always come from your file, so `name` and `type` are still required. |

::: warning The included theme's colors are all set
Colors from the included theme count as set, so they don't follow your base colors. Palenight sets the title bar, conversation, message bar and Settings window to its background color one by one, so Palenight Midnight above sets all of them; with only `window.background`, just the window's own background would change. To see which tokens a theme sets, open it in the [theme editor](/customize/theme-editor) and look for **Set**, or read its file in [BuiltInThemes](https://github.com/r3volution11/Vela-IRC/tree/main/Packages/VelaKit/Sources/VelaTheme/BuiltInThemes) on GitHub.
:::

- **Chains work:** a theme can include a theme that includes another, up to 8 levels. Themes that include each other in a loop get an error.
- **Paths work too:** a value ending in `.json` or `.jsonc` is read as a file path, relative to your Themes folder.
- **Changing a built-in theme in place:** name your file after the built-in (for example `nord.json`), add `"include": "Nord"` and set only what you want to change. Your theme takes the built-in's place in the gallery.
- **The theme editor merges includes.** When it opens a theme that uses `include`, it copies in the included colors, so a theme you save from the editor or export from it stands on its own.

## Light and dark {#light-and-dark}

Every theme is either `"dark"` or `"light"`. The `type`:

- **picks the defaults** for every color you don't set, and the default nick palette (bright colors for dark backgrounds, deeper ones for light);
- **tells macOS** whether to draw the menu bar menus, context menus, alerts, sheets, file pickers and the font and color panels light or dark. These are drawn by macOS and don't take the theme's colors;
- **sorts the theme** into the **Dark** or **Light** filter of the gallery and the **Dark Mode theme** or **Light Mode theme** picker.

Set it to match your backgrounds. A dark theme marked `"light"` gets light menus and defaults meant for light backgrounds.

### Making a pair {#pairs}

To follow your Mac between Dark Mode and Light Mode, make two themes: one of each type. For example, a light partner for Harbor:

```jsonc
{
  "$schema": "https://raw.githubusercontent.com/r3volution11/Vela-IRC/main/schemas/vela-theme.schema.json",
  "name": "Harbor Light",
  "type": "light",
  "colors": {
    "window.background": "#F4F6F8",
    "window.foreground": "#2B3A48",
    "accent": "#C7701E"
  }
}
```

Then turn on **Match System Appearance** (in the **Theme** menu or **Settings → Appearance → System appearance**) and choose **Harbor** as the **Dark Mode theme** and **Harbor Light** as the **Light Mode theme**. You can also right-click each card in the gallery and choose **Use in Dark Mode** or **Use in Light Mode**. In settings.json, that's:

```jsonc
"appearance.followSystem": true,
"appearance.preferredDarkTheme": "Harbor",
"appearance.preferredLightTheme": "Harbor Light"
```

Tips for a pair:

- **Keep the same hues, at different strengths.** The light theme's accent and nick colors need to be deeper to read on a light background. Vela's default light nick palette, in the [token reference](/reference/theme-tokens#nick-colors), is a good model.
- **Start the light theme from a light theme.** `include` copies the included theme's colors, so including your dark theme in a light one brings its dark colors along. Start from Lighter or Vela Paper in the theme editor instead.

## Checking contrast {#checking-contrast}

The theme editor checks your theme's text against its backgrounds as you edit, using the WCAG contrast ratio (from 1:1, no contrast, to 21:1, black on white). There are three levels:

| Minimum | For |
| --- | --- |
| **4.5:1** | Message text (also on mention and your own messages' backgrounds), links, your nick, mentions, notices, actions, errors and code; the title, sidebar, member list, message field, link preview titles and descriptions, reactions, buttons, popovers and Settings text; text on the accent. |
| **3:1** | Secondary text: hostnames, topics, server names, section headers, events such as joins and parts, server messages, day dividers, badges, the rail, reply quotes, typing lines, link preview site names, Settings captions and every nick color. |
| **2.5:1** | Timestamps, the message field's placeholder and members who are away. |

In the [theme editor](/customize/theme-editor):

- **Contrast issues** in the left column, with a count, lists every token involved in a failing check.
- **Each failing token says what's wrong.** On a text color: "3.9:1 on chat.background, needs 4.5:1". On a background: "chat.foreground on this is 3.9:1, needs 4.5:1". Fix either color.
- **A nick color under 3:1** gets a dot under its well; hover it for the ratio.

These are warnings: a theme with contrast issues still loads and works. Every built-in theme passes every check, and a theme submitted for the built-in collection has to as well.

Tips:

- **Body text matters most.** `chat.foreground` on `chat.background` should be well above 4.5:1; check it on `chat.highlightBackground` (mentions) and `chat.selfMessageBackground` too.
- **Translucent colors are measured over what's under them:** a translucent sidebar color over the sidebar, a highlight over the conversation, and so on.
- **With `vibrancy`, surfaces on a material are measured over a stand-in for the desktop:** their tint over the material on a white desktop (dark themes) or a black one (light themes), the least favorable case. See [Translucency](#translucency).
- **Watch the accent as text** on light themes, and set `accentText` to a deeper shade if links and mentions fail.
- **Don't rely on color alone.** Vela already adds arrows to joins and parts, and bars and tints to mentions; keep those colors distinct, but not too faint.

If you build Vela from source, `vela-theme-tool` runs the same checks from the command line:

```sh
cd Packages/VelaKit
swift run vela-theme-tool check path/to/harbor.json             # problems and failing checks; exits 1 on failures
swift run vela-theme-tool check --verbose path/to/harbor.json   # every check
swift run vela-theme-tool preview path/to/harbor.json harbor.png  # render a mock window
```

`check` also lists [typos and skipped values](#problems) in the file, marked ⚠ (unknown keys and tokens) or ✗ (a value it can't use, such as a bad `vibrancy`). A ✗ counts as a failure, a ⚠ doesn't.

## Previews are drawn for you {#previews}

Vela draws your theme's preview card for you from its colors; there's nothing to make. A theme has no thumbnail or screenshot to provide, and no key for one.

<Screenshot src="/screenshots/settings-themes.webp" alt="Settings → Appearance: two rows of theme cards (Solarized Light, Tokyo Night and Vela Graphite, then Vela Mist, Vela Paper and Volcano), each a miniature window in its own colors, then the System appearance section and the Make your own section with Customize…, Import Theme… and Reveal Themes Folder" caption="Every card is drawn from the theme's own colors." />

Each card in **Settings → Appearance** is a miniature of Vela's window, drawn live in that theme:

- **The surfaces:** the window, sidebar (or the collapsed rail), title bar, conversation, message bar and field, and member list, with the dividers and borders between them.
- **The sidebar's states:** the selected channel in `sidebar.activeBackground`, an unread channel with its count badge, and a channel that mentions you in `sidebar.highlightForeground` with the mention badge. The rail shows the selected tile with its indicator and a mention badge.
- **Text, drawn as bars** in the theme's text colors: the channel name and topic, message text, timestamps, join and part lines, the message field's placeholder, and member names, including a prefix and someone away.
- **The conversation's accents:** a link in `chat.link`, the New line in `chat.unreadMarker`, and a message that mentions you, on `chat.highlightBackground` with its `chat.highlightBorder` bar and your name in `chat.mention`.
- **Nicknames** in the theme's nick colors, after the readability filter.
- **The window buttons** in the theme's error, warning and success colors.
- **Tab stacks** in the `tab.*` colors, if you use tabs: the network row on `tab.serverBackground` with the selected network, then the channel tabs (selected, unread, mentioned and read) with the selected one opening into the conversation, or as pills, or in the title bar, as your settings say.
- **Translucency:** with `vibrancy`, the surfaces on a material are drawn over a soft stand-in desktop in two of the theme's own colors, tinted the way the app tints them, so you can tell a translucent theme at a glance.

**The card shows your own layout:** sidebar, rail or tabs, your message layout, avatars, timestamps, colored nicks, the member list, the monospace font and the message box border. In other words, it's your Vela in that theme. It includes your [color overrides](/customize/settings-json#color-customizations) for the theme, such as a picked accent, and it's redrawn the moment you save the file. **Hover a card** for the theme's author and description.

The same drawing is the **Live preview** in the theme editor, and the layout and preset pictures in **Settings → Layout**, **Settings → Presets** and **Settings → Messages** are drawn in your theme the same way. **Select Theme** (<kbd>⌃⌘T</kbd>) shows a tiny version: the sidebar with its selected row and a mention badge, and the conversation with nick colors, a link and a message that mentions you.

A card is a summary. It doesn't show selections, hover colors, link previews, the Settings window's colors or mIRC colors, and its translucency is only a stand-in for your real desktop, so check those in the app; see [Testing your theme](#testing). If Vela can't draw a theme at all (because the theme it includes is missing, say), its card shows a warning sign instead; if parts of the file were skipped, its name has a small warning triangle.

## Testing your theme {#testing}

A theme has to work with every layout, so try yours in more than one. With your theme in use and the file open in your editor:

1. **All three message layouts.** Switch between **Classic**, **Modern grouped** and **Compact columns** in **View → Message Layout**. Also try **Use a monospace font** in **Settings → Messages**, which many people pair with Classic.
2. **The presets.** Apply **Classic IRC**, **Modern Chat**, **Tabbed** and **Focus** from **View → Presets**. Tabbed is the easiest way to check the `tab.*` colors. A preset changes your layout settings (never your theme), so if you've arranged yours by hand, keep a copy of your [settings.json](/customize/settings-json) to go back to.
3. **The sidebar's other forms.** Collapse the sidebar to the rail with <kbd>⌃⌘S</kbd>, and try tab stacks at the top, in the title bar and at the bottom (**Settings → Layout**).
4. **Light and dark.** If you made a pair, switch macOS between Dark Mode and Light Mode, and check that menus and alerts match each theme.
5. **States.** Look at the selected channel, unread and mention badges, a disconnected network, a message that mentions you, your own messages, the New line, day dividers, notices, `/me` actions and errors.
6. **Selection, hover and the keyboard.** Select text in a message, and hover messages and sidebar rows. Press <kbd>⌥⌘1</kbd>, <kbd>⌥⌘2</kbd> and <kbd>⌥⌘4</kbd> to see the `focusBorder` ring on a sidebar row or tab, a message and a person in the member list, and the selected message in `chat.selectionBackground`.
7. **Media and IRCv3.** Look at link previews, images and videos, and, on a network that supports them, reactions, replies and typing lines.
8. **Popovers.** Open the command palette (<kbd>⇧⌘P</kbd>) and the emoji picker.
9. **The Settings window.** It uses the `settings.*` colors; open a few panes, including **Advanced**.
10. **Translucency.** If your theme sets `vibrancy`, look at it over a light and a dark desktop picture, with the window in front and behind other windows. See [Translucency](#translucency).
11. **Contrast.** In the theme editor, check that **Contrast issues** is empty, or that you're happy with what's left.

Layouts and presets never change your theme, and themes never change your layout, so whatever you test with, the theme file stays the same.

## Importing a VS Code theme {#vs-code}

Vela's themes are modeled on VS Code's, so you can also start from any VS Code color theme: choose **Theme → Import Theme…** and pick its `.json` file or a whole `.vsix` extension. Vela turns it into an ordinary theme file in your Themes folder, which you can then edit like any other.

- **What carries over:** the workbench colors (editor, side bar, activity bar, title bar, inputs, buttons, badges, widgets, links and selection) become Vela's tokens, and the terminal colors become mIRC colors 0–15 and the nick palette.
- **What doesn't:** syntax highlighting, font styles such as bold and italic, and icon themes have no place in Vela; syntax colors are only used to fill out the nick palette when the terminal colors are too few. A single `.json` file that builds on another file in its extension can't find it, so import the `.vsix` instead.
- **Readability comes first:** faint text colors are dropped, so Vela works out readable ones, and accent-colored text is adjusted to 4.5:1.

The full mapping is in [Importing VS Code themes](/customize/vs-code-themes). After importing, check **Contrast issues** in the theme editor.

## Sharing and submitting {#sharing-your-theme}

### Sharing a theme

- **Export it** from the theme editor with **Export…**. You get a `.json` file that stands on its own, with any included theme merged in.
- **Or share the file** from your Themes folder: right-click its card and choose **Show in Finder**. If it uses `include` with another theme of yours, share that one too, or export it from the theme editor instead.
- **To install a theme** someone sent you, choose **Theme → Import Theme…**, or drop the file in your Themes folder. Import never replaces a theme: if you already have one with that name, the new one is named "Harbor (Imported)". To update a theme you already have, replace its file in the Themes folder.

### Proposing a built-in theme

To propose a theme for Vela's built-in collection, open a [theme submission](https://github.com/r3volution11/Vela-IRC/issues/new?template=theme_submission.yml) with the theme's JSON, or send a pull request. A built-in theme needs:

1. **No contrast issues.** Every built-in theme passes every [check](#checking-contrast).
2. **An `author` and a one-sentence `description`**, which appears on the [Built-in themes](/reference/built-in-themes) page.
3. **Screenshots** of all three message layouts: Classic, Modern grouped and Compact columns.
4. **For a port of someone else's theme, a license that allows it**, and attribution in [THEME-CREDITS.md](https://github.com/r3volution11/Vela-IRC/blob/main/docs/THEME-CREDITS.md).

A pull request adds the file to `Packages/VelaKit/Sources/VelaTheme/BuiltInThemes/` and a row to the built-in themes table in [THEMES.md](https://github.com/r3volution11/Vela-IRC/blob/main/docs/THEMES.md#built-in-themes). See [CONTRIBUTING.md](https://github.com/r3volution11/Vela-IRC/blob/main/CONTRIBUTING.md).

## Troubleshooting {#troubleshooting}

### My theme doesn't appear {#not-in-the-gallery}

- **Is it in the right folder?** Open it with **Settings → Appearance → Reveal Themes Folder**. The file has to be directly in that folder, not in a subfolder.
- **Does it end in `.json` or `.jsonc`?** TextEdit may add `.rtf` or `.txt`. Also check that the name doesn't start with a dot.
- **Is there an error message?** A new file with a mistake doesn't appear until it's fixed; look for "Couldn't load …" in **Settings → Appearance**.
- **Is the gallery filtered?** Choose **All** above the gallery.
- **Did it take a built-in's place?** A file named like a built-in theme (`nord.json`) appears under its own `name`, in place of the built-in.

### Settings → Appearance says "Couldn't load my-theme.json" {#error-messages}

Vela explains what's wrong, and keeps using the last version of the file that worked until you fix it. **Show in Finder** shows you the file. Common messages:

| Message | Fix |
| --- | --- |
| The file isn't valid JSON: … around line 4, column 5. | A missing comma or quote near that spot, or curly quotes from TextEdit. |
| The required field “type” is missing. | Add `"type": "dark"` or `"type": "light"` (and `"name"` if that's missing). |
| “colors.accent”: “#GGG” is not a hex color (use #RGB, #RGBA, #RRGGBB or #RRGGBBAA). | Fix the color. See [Writing colors](#color-values). |
| “type”: “dim” is not a theme type; use "dark" or "light". | Use `"dark"` or `"light"`. |
| “ircColors.99”: IRC color indexes run from 0 to 98. | Use mIRC color numbers from 0 to 98. |
| The included theme “Nope” wasn't found. | Check the name or id in `include`. Until then, the theme's card shows a warning sign, and if it's the theme in use, Vela shows Palenight (or Lighter, for a light theme) instead. |
| The themes include each other in a loop: A → B → A. | Remove one of the `include`s. |

### Settings → Appearance says "Parts of my-theme.json were ignored" {#problems}

<Screenshot src="/screenshots/settings-theme-problems.webp" alt="Settings → Appearance: below Make your own, a red callout titled Parts of harbor.json were ignored, listing that fontSize isn't a theme key because themes only contain colors, that glass isn't a vibrancy value and the three valid values, and that colors.sidebar.backgroud isn't a theme color token with the suggestion sidebar.background, then The rest of the theme works and a Show in Finder button" caption="A theme file with three mistakes. The theme still loads." />

The theme loaded and works, but Vela skipped part of the file: a key or token name it doesn't know (usually a typo) or a value it can't use. Everything else in the file is used. The same list shows at the top of the [theme editor](/customize/theme-editor) when you open the theme there, and `vela-theme-tool check` prints it too. The theme's card gets a small warning triangle.

| Message | What it means |
| --- | --- |
| “colors.sidebar.backgroud” isn't a theme color token, so it's ignored. Did you mean “sidebar.background”? | A token name with a typo. Vela suggests the closest real token when there's one. Fix the name; the [token reference](/reference/theme-tokens) has every spelling. |
| “fontSize” isn't a theme key, so it's ignored. Themes only contain colors: fonts, sizes and layout are settings (Settings → Messages and Layout, or settings.json). | A key for something themes don't do. Set it in Settings instead; see [Colors only, by design](#colors-only). |
| “autor” isn't a theme key, so it's ignored. Did you mean “author”? | A misspelled top-level key. |
| “accent” isn't a theme key, so it's ignored. Color tokens go inside "colors": { "accent": … }. | A color token outside `colors`. Move it into `colors`. |
| “vibrancy”: “glass” isn't a vibrancy value, so it's ignored. Use "none", "sidebar" or "window". | A `vibrancy` Vela can't use. The theme is drawn as if it had none (or with its included theme's). A value in the wrong case, such as `"Sidebar"`, adds "Did you mean "sidebar"?". |

The callout is a warning, or an error when a value was skipped (the `vibrancy` message). In the theme editor, **Remove Unknown Tokens** deletes misspelled token names from the working copy; saving from the editor leaves unknown keys and a bad `vibrancy` out of the file.

Colors are stricter: a malformed color stops the theme from loading, as in the table above, because Vela can't guess what you meant.

### A color doesn't change {#color-doesnt-change}

- **An override in settings.json wins.** Colors in [`appearance.colorCustomizations`](/customize/settings-json#color-customizations) apply on top of the theme, and so do the [accent color](/customize/themes#accent-color) and [message box border color](/customize/themes#message-box-border) you pick in **Settings → Appearance**, which are saved there. **Settings → Appearance → Details → Color overrides** counts the ones you wrote yourself. The theme editor leaves all overrides out, so a theme can look right in the editor and different after you save it. Choose **Default** in the accent and border color pickers, or remove the entries from settings.json.
- **The token name has a typo.** Vela ignores names it doesn't know, and lists them under "Parts of … were ignored" in **Settings → Appearance**, with the token you probably meant. See [Typos and skipped values](#problems). The `$schema` line also makes your editor underline them.
- **A more specific token is set.** If the theme, or the theme it includes, sets `chat.background`, changing `window.background` doesn't move it. Set that token too, or remove it so it follows again. See [How defaults work](#how-defaults-work).
- **You're editing a different theme.** With **Match System Appearance** on, the theme in use depends on whether your Mac is in Dark Mode or Light Mode.
- **Vela doesn't draw that part yet.** `chat.findMatchBackground` is reserved for searching the conversation, which this version of Vela can't do yet. Setting it does no harm. (The other tokens are all drawn: `window.border` is the thin outline inside the edge of Vela's windows, `button.hoverBackground` a primary button such as **Save** under the pointer, and `scrollbar.thumb` and `scrollbar.thumbHover` the scroll bars of the conversation, member list and sidebar.)
- **The window is inactive and translucent.** With `vibrancy`, the material turns solid while Vela isn't the frontmost window, which changes how tinted surfaces look. See [Translucency](#translucency).
- **It's drawn by macOS.** Menus, alerts and file pickers follow only the theme's `type`.

### The fonts, sizes or layout didn't change

That's by design: a theme only sets colors. Change fonts and text size in **Settings → Messages**, the layout in **Settings → Layout**, or everything at once with a [preset](/guide/presets). See [Colors only, by design](#colors-only).
