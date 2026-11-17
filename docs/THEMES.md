# Theming Vela

Everything in Vela's window is drawn from a theme: the sidebar, the conversation,
the composer, the member list, link previews, badges, even the nickname and mIRC
color palettes. Themes are plain JSON files of named color **tokens**, modeled on
VS Code color themes, so if you've ever tweaked `workbench.colorCustomizations`
you already know how this works.

- [Quick start](#quick-start)
- [Where themes live](#where-themes-live)
- [The theme file](#the-theme-file)
- [How defaults and fallbacks work](#how-defaults-and-fallbacks-work)
- [Building on another theme with `include`](#building-on-another-theme-with-include)
- [Nick colors and IRC colors](#nick-colors-and-irc-colors)
- [Tweaking a theme without writing one](#tweaking-a-theme-without-writing-one)
- [Choosing themes and following the system](#choosing-themes-and-following-the-system)
- [Importing VS Code themes](#importing-vs-code-themes)
- [Checking your theme](#checking-your-theme)
- [Limits](#limits)
- [Built-in themes](#built-in-themes)
- [Token reference](#token-reference)

## Quick start

1. Open the Themes folder (see below) and create `my-theme.json`.
2. Paste this, save, and pick **My Theme** in Settings → Appearance:

   ```jsonc
   {
     "$schema": "https://raw.githubusercontent.com/r3volution11/Vela-IRC/main/schemas/vela-theme.schema.json",
     "name": "My Theme",
     "type": "dark",
     "include": "Palenight",
     "colors": {
       "accent": "#FF8A65",
       "chat.background": "#1E2030"
     }
   }
   ```

3. Keep the file open in your editor. Every time you save, Vela reloads it
   instantly — no restart.

Because of `"$schema"`, editors such as VS Code, Zed and Nova autocomplete
every token name, show its description and default, and flag typos and
malformed colors as you type.

## Where themes live

Vela is sandboxed, so its Themes folder is inside its container:

```text
~/Library/Containers/io.github.r3volution11.Vela/Data/Library/Application Support/Vela/Themes
```

Every `.json` or `.jsonc` file in that folder is a theme. Its **id** is the file
name without the extension (`my-theme`); its **name** is the `name` field.
Settings can refer to a theme by either, case-insensitively.

**Live reload.** Vela watches the folder. When a file is added, changed,
renamed or deleted, the theme list and the active theme update immediately. If
you save a file with a mistake in it (a missing comma, a bad color), Vela keeps
showing the **last version that worked** and reports the problem in Settings →
Appearance, so a half-finished edit never leaves you with a broken window.

**Overriding a built-in.** A user theme whose file name matches a built-in id
(for example `nord.json`) replaces that built-in in the list. It can still
`"include": "Nord"` to start from the original.

## The theme file

Theme files are JSON with comments: `//` and `/* */` comments and trailing
commas are allowed.

| Field | Required | Meaning |
| --- | --- | --- |
| `$schema` | no | Schema URL, for editor autocompletion and validation. |
| `name` | yes | Display name. Must be unique among your themes. |
| `type` | yes | `"dark"` or `"light"`. Picks the token defaults and the appearance of system UI (see [Limits](#limits)). |
| `include` | no | Name or id of another theme to start from. |
| `author`, `description` | no | Shown in the theme picker. |
| `colors` | no | Token → color. Anything you leave out is derived. |
| `nickColors` | no | Array of colors used for nicknames. |
| `ircColors` | no | mIRC color index (`"0"`–`"98"`) → color. |
| `vibrancy` | no | `"none"` (default), `"sidebar"` or `"window"`: let the sidebar or the whole window use the system's translucent materials (Liquid Glass) instead of opaque colors. |

Colors are hex strings: `#RGB`, `#RGBA`, `#RRGGBB` or `#RRGGBBAA`. Alpha is
honored everywhere, which is how hover and selection highlights stay subtle
on any background (`"chat.hoverBackground": "#FFFFFF0A"`).

## How defaults and fallbacks work

Each token has a default for dark themes and one for light themes, and most
defaults are *expressions over other tokens*. That means you can write a
convincing theme with three colors —

```jsonc
{ "name": "Three Colors", "type": "dark",
  "colors": { "window.background": "#20242C", "window.foreground": "#D8DEE9", "accent": "#E5A050" } }
```

— and everything else follows: the sidebar is a slightly darker tint of the
window, the member list matches the sidebar, links and your own nick use the
accent, badges use the accent with a readable text color, and so on. Set a
more specific token whenever you want to break the chain:

```text
memberList.background → sidebar.background → mix(window.background, #000000, 16%)
```

Setting `sidebar.background` moves the member list with it; setting
`memberList.background` changes only the member list.

Default expressions in the [token reference](#token-reference) use:

| Expression | Meaning |
| --- | --- |
| `#RRGGBB` | A fixed color. |
| `token.name` | The value of another token. |
| `mix(a, b, 30%)` | `a` blended 30% of the way toward `b`. |
| `transparent(a, 20%)` | `a` with its opacity multiplied by 20%. |
| `contrast(a)` | White, or a near-black tinted with `a`'s hue — whichever reads better on `a`. |

Resolution order, from lowest to highest priority:

1. the token's default for the theme's `type`
2. the included theme(s), deepest first
3. the theme's own `colors`
4. global `colorCustomizations` from settings
5. `"[Theme Name]"`-scoped `colorCustomizations`

Two tokens deserve a note:

- `accent` is the theme's signature color, used for fills (selection, badges,
  buttons, the rail indicator). `accentText` is the same accent used **as text**
  (links, your nick, mentions). They default to the same value in dark themes
  and a darker shade in light themes; set `accentText` when your accent is too
  light or too dark to read as text.
- `accentForeground` is text drawn **on** the accent. By default it's whichever
  of white or a dark tint reads better.

## Building on another theme with `include`

```jsonc
{
  "name": "Palenight Midnight",
  "type": "dark",
  "include": "Palenight",
  "colors": { "chat.background": "#1B1E2B", "window.background": "#1B1E2B" }
}
```

The included theme's colors and IRC colors are merged key by key under yours;
its `nickColors` and `vibrancy` are used unless you set your own. Includes can
chain (up to 8 levels); loops are reported as errors. The value is a theme name
or id; a value ending in `.json` is read as a path relative to the Themes
folder.

## Nick colors and IRC colors

**`nickColors`** is the palette nicknames are drawn from. Each nick starts
from the entry its name hashes to (case-insensitively, using IRC's RFC 1459
case mapping, so `Nick[a]` and `nick{a}` match), so it usually keeps its color
across channels and launches. Within a conversation, people who talk get
different entries while the palette has room, so two nicks that hash alike
don't look alike, and someone whose color would look like (say, orange beside
red) a person they're talking with gets the nearest palette color that's
clearly different. Aim for 8–12 clearly different hues with at least 3:1
contrast — ideally 4.5:1 — against `chat.background`. Entries that would read
as plain text (a grey close to `chat.foreground`) or fall under 3:1 aren't
used.

**`ircColors`** are the colors behind mIRC formatting codes. 0–15 are the
classic colors (white, black, blue, green, red, brown, magenta, orange, yellow,
light green, cyan, light cyan, light blue, pink, grey, light grey) and are worth
tuning for your background; 16–98 are the standard extended palette and rarely
need changing. List only the indexes you change:

```jsonc
"ircColors": { "1": "#1B1E2B", "2": "#6C8EEF", "4": "#FF5370" }
```

## Tweaking a theme without writing one

Like VS Code's `workbench.colorCustomizations`, settings.json can override
colors on top of whatever theme is active:

```jsonc
"appearance.colorCustomizations": {
  // Applies to every theme.
  "chat.timestamp": "#7A7A7A",

  // Applies only to Palenight.
  "[Palenight]": {
    "accent": "#FFCB6B",
    "nickColors": ["#F07178", "#C3E88D", "#82AAFF", "#C792EA"]
  },

  // Several themes at once, and wildcards.
  "[Nord][Dracula]": { "chat.selfNick": "#FFB86C" },
  "[Catppuccin *]": { "ircColors": { "4": "#FF5555" } },
  "[Solarized*]": { "vibrancy": "sidebar" }
}
```

Scopes match a theme's name or id, case-insensitively. Scoped values win over
global ones. Entries with unknown token names or malformed colors are ignored
and listed in Settings → Appearance. Customizations apply to the active theme
and to the previews in the theme picker, but not to the theme editor's draft,
so the editor always shows the theme exactly as written.

The **Accent color** picker in Settings → Appearance writes here too. It
offers a theme's own `nickColors` and `ircColors` 0–15 that work as an accent
(not grey, clear of the text color, 3:1 against the window and sidebar, and
distinct from each other; at most ten), and switching to one recolors every
token the theme draws in its accent, keeping text readable. It writes into the
theme's own scope and lists the keys it wrote under `"$accentPicker"`, so
choosing Default removes exactly those; entries written by hand always win
(except `accent` itself). See
[settings.json → Accent colors](https://velairc.app/customize/settings-json#accent-colors).

## Choosing themes and following the system

Vela can follow the macOS light/dark setting (including automatic switching)
and use a different theme for each, or stay on one theme:

```jsonc
"appearance.theme": "Palenight",                     // used when not following the system
"appearance.followSystem": true,
"appearance.preferredDarkTheme": "Palenight",
"appearance.preferredLightTheme": "Lighter"
```

The defaults are **Palenight** for dark and **Lighter** for light. If a named
theme can't be found or fails to load, Vela falls back to the default for
that appearance.

## Importing VS Code themes

Settings → Appearance → **Import Theme…** accepts:

- a VS Code color theme file (`*-color-theme.json`, comments allowed), or
- a whole `.vsix` extension — every JSON color theme it contributes is imported,
  with names taken from the extension (including localized names), and `include`d
  base files followed.

Vela files are recognized and copied as they are. Imports are written into your
Themes folder as ordinary Vela themes, so you can edit them afterwards; a name
that clashes with an existing theme gets an “(Imported)” suffix.

How the mapping works:

| VS Code | Vela |
| --- | --- |
| `editor.background` / `editor.foreground` | `chat.*` and `window.*` |
| `sideBar.background` / `foreground` / `border` | `sidebar.*` |
| `sideBarSectionHeader.foreground` | `sidebar.headerForeground` |
| `list.activeSelectionBackground` / `Foreground` | `sidebar.activeBackground` / `Foreground` |
| `list.hoverBackground` | `sidebar.hoverBackground` |
| `activityBar.*`, `activityBarBadge.*` | `rail.*` |
| `titleBar.activeBackground` / `activeForeground` / `border` | `titleBar.*` |
| `input.*`, `button.*`, `focusBorder`, `scrollbarSlider.*` | `input.*`, `button.*`, `focusBorder`, `scrollbar.*` |
| `badge.*` | sidebar unread badges |
| `editorWidget.*`, `quickInput.*` | `popover.*` |
| `textLink.foreground` | `chat.link` |
| `editorLineNumber.foreground` | `chat.timestamp` |
| `editor.findMatchHighlightBackground` (or `wordHighlightBackground`) | `chat.highlightBackground` |
| `editor.selectionBackground` | `chat.selectionBackground` |
| `textCodeBlock.background` | `chat.codeBackground` |
| `terminal.ansi*` | `ircColors` 0–15 and the nick palette |

The **accent** is the first saturated, visible color among the activity bar
badge, the active activity bar border, the primary button and the focus
border. `type` comes from the file, the extension's `uiTheme`, or the editor
background's brightness. Terminal colors map to mIRC colors the way terminal
IRC clients do (bright white → 0, black → 1, blue → 2, green → 3, bright red → 4,
red → 5, magenta → 6, yellow → 7, bright yellow → 8, bright green → 9, cyan → 10,
bright cyan → 11, bright blue → 12, bright magenta → 13, bright black → 14,
white → 15). The nick palette uses the theme's colored ANSI entries, topped up
from its syntax colors when there aren't enough (or built entirely from syntax
colors when the theme has no terminal palette).

Imported text colors that would be hard to read in Vela (VS Code line numbers,
for instance, are often deliberately faint) are dropped so Vela derives a
readable value instead, and accent-colored text is lightened or darkened to
reach 4.5:1.

## Checking your theme

If you build Vela from source, `vela-theme-tool` helps when designing themes:

```sh
cd Packages/VelaKit
swift run vela-theme-tool check path/to/my-theme.json   # contrast report; exits 1 on failures
swift run vela-theme-tool check --verbose palenight     # every check, passing or not
swift run vela-theme-tool preview my-theme.json out.png # render a mock Vela window
swift run vela-theme-tool import some-color-theme.json  # VS Code → Vela JSON on stdout
swift run vela-theme-tool schema                        # regenerate schemas/vela-theme.schema.json
swift run vela-theme-tool tokens                        # regenerate the token table below
```

`check` uses WCAG contrast ratios: 4.5:1 for message text and other body text,
3:1 for secondary text, events, badges and nick colors, and 2.5:1 for
timestamps, placeholders and away members. Every built-in theme passes all of
them.

## Limits

- **System UI follows only light/dark.** The menu bar, context menus,
  sheets, alerts, file pickers, the font panel and the system color
  picker are drawn by macOS. They follow the theme's `type`, not its colors.
- Standard macOS controls in Settings (switches, pop-up buttons, steppers)
  take the theme's `accent` where macOS allows tinting, and otherwise look
  native.
- `vibrancy` asks macOS for its translucent materials; how much of your colors
  show through is up to the system and the wallpaper. With `"none"` (the
  default) every surface is exactly the color you set.
- Fonts and sizes aren't part of themes; they're regular settings.

## Built-in themes

| Theme | Type | File | Notes |
| --- | --- | --- | --- |
| Palenight | dark | `palenight.json` | **Default dark.** Inspired by Material Theme Palenight. |
| Lighter | light | `lighter.json` | **Default light.** Inspired by Material Theme Lighter. |
| Oceanic | dark | `oceanic.json` | Inspired by Material Theme Oceanic. |
| Darker | dark | `darker.json` | Inspired by Material Theme Darker. |
| Ocean | dark | `ocean.json` | Inspired by Material Theme Ocean. |
| Deepforest | dark | `deepforest.json` | Inspired by Material Theme Deepforest. |
| Volcano | dark | `volcano.json` | Inspired by Material Theme Volcano. |
| Sandy Beach | light | `sandy-beach.json` | Inspired by Material Theme Sandy Beach. |
| Vela Graphite | dark | `vela-graphite.json` | Vela original. |
| Vela Paper | light | `vela-paper.json` | Vela original. |
| Vela Mist | light | `vela-mist.json` | Vela original. |
| Dracula | dark | `dracula.json` | Port of Dracula for VS Code. |
| Nord | dark | `nord.json` | Port of Nord for VS Code. |
| Catppuccin Latte | light | `catppuccin-latte.json` | Port of Catppuccin for VS Code. |
| Catppuccin Mocha | dark | `catppuccin-mocha.json` | Port of Catppuccin for VS Code. |
| Tokyo Night | dark | `tokyo-night.json` | Port of Tokyo Night for VS Code. |
| One Dark | dark | `one-dark.json` | Port of One Dark Pro for VS Code. |
| Gruvbox Dark | dark | `gruvbox-dark.json` | Port of Gruvbox for VS Code. |
| Solarized Dark | dark | `solarized-dark.json` | Port of VS Code's Solarized Dark. |
| Solarized Light | light | `solarized-light.json` | Port of VS Code's Solarized Light. |
| Rosé Pine | dark | `rose-pine.json` | Port of Rosé Pine for VS Code. |

Sources, licenses and attributions are in [THEME-CREDITS.md](THEME-CREDITS.md).

## Token reference

Generated from the token registry by `vela-theme-tool tokens`; don't edit the
section between the markers by hand.

<!-- BEGIN TOKEN TABLE -->
### Window

Base colors most other tokens derive from.

| Token | Description | Dark default | Light default |
| --- | --- | --- | --- |
| `window.background` | Base background of the window. Most surfaces derive from it. | `#292D3E` | `#FAFAFA` |
| `window.foreground` | Base text color. Most text colors derive from it. | `#BFC7D5` | `#3E525C` |
| `window.border` | Outer window border and the edges of floating panels. | `pane.divider` | `pane.divider` |
| `pane.divider` | Dividers between the sidebar, conversation and member list. | `mix(window.background, #000000, 30%)` | `mix(window.background, window.foreground, 12%)` |

### Title bar

The toolbar area above the conversation.

| Token | Description | Dark default | Light default |
| --- | --- | --- | --- |
| `titleBar.background` | Background of the title bar / toolbar above the conversation. | `chat.background` | `chat.background` |
| `titleBar.foreground` | Channel name and toolbar icons. | `chat.foreground` | `chat.foreground` |
| `titleBar.secondaryForeground` | Topic and other secondary title bar text. | `mix(titleBar.foreground, titleBar.background, 40%)` | `mix(titleBar.foreground, titleBar.background, 33%)` |
| `titleBar.border` | Line under the title bar. | `pane.divider` | `pane.divider` |

### Sidebar

The network and channel list.

| Token | Description | Dark default | Light default |
| --- | --- | --- | --- |
| `sidebar.background` | Sidebar background. Usually a slight tint of window.background. | `mix(window.background, #000000, 16%)` | `mix(window.background, window.foreground, 4.5%)` |
| `sidebar.foreground` | Names of channels and queries with no unread activity, and general sidebar text. | `mix(window.foreground, sidebar.background, 20%)` | `mix(window.foreground, sidebar.background, 15%)` |
| `sidebar.secondaryForeground` | Secondary sidebar text: server names, counts, parted channels. | `mix(sidebar.foreground, sidebar.background, 40%)` | `mix(sidebar.foreground, sidebar.background, 20%)` |
| `sidebar.headerForeground` | Section and network headers. | `mix(sidebar.foreground, sidebar.background, 30%)` | `mix(sidebar.foreground, sidebar.background, 22%)` |
| `sidebar.hoverBackground` | Row under the pointer. | `transparent(sidebar.foreground, 7.0%)` | `transparent(sidebar.foreground, 7.0%)` |
| `sidebar.activeBackground` | The selected channel or query. | `mix(sidebar.background, accent, 22%)` | `mix(sidebar.background, accent, 18%)` |
| `sidebar.activeForeground` | Text of the selected channel or query. | `sidebar.unreadForeground` | `sidebar.unreadForeground` |
| `sidebar.unreadForeground` | Names of channels and queries with unread messages. | `window.foreground` | `window.foreground` |
| `sidebar.highlightForeground` | Names of channels and queries with unread mentions of you. | `accentText` | `accentText` |
| `sidebar.badgeBackground` | Unread-count badge. | `mix(sidebar.background, sidebar.foreground, 20%)` | `mix(sidebar.background, sidebar.foreground, 20%)` |
| `sidebar.badgeForeground` | Text of the unread-count badge. | `sidebar.unreadForeground` | `sidebar.unreadForeground` |
| `sidebar.highlightBadgeBackground` | Badge counting unread mentions of you. | `accent` | `accent` |
| `sidebar.highlightBadgeForeground` | Text of the mention badge. | `accentForeground` | `accentForeground` |
| `sidebar.disconnectedForeground` | Networks and channels while disconnected. | `mix(sidebar.foreground, sidebar.background, 50%)` | `mix(sidebar.foreground, sidebar.background, 50%)` |
| `sidebar.border` | Edge between the sidebar and the conversation. | `pane.divider` | `pane.divider` |

### Rail

The collapsed, icon-only sidebar.

| Token | Description | Dark default | Light default |
| --- | --- | --- | --- |
| `rail.background` | Background of the collapsed sidebar. | `sidebar.background` | `sidebar.background` |
| `rail.foreground` | Icons and initials in the collapsed sidebar. | `sidebar.foreground` | `sidebar.foreground` |
| `rail.inactiveForeground` | Icons of disconnected or idle networks in the collapsed sidebar. | `sidebar.secondaryForeground` | `sidebar.secondaryForeground` |
| `rail.activeBackground` | Selected item in the collapsed sidebar. | `sidebar.activeBackground` | `sidebar.activeBackground` |
| `rail.activeIndicator` | Indicator bar next to the selected item. | `accent` | `accent` |
| `rail.badgeBackground` | Activity badge in the collapsed sidebar. | `sidebar.highlightBadgeBackground` | `sidebar.highlightBadgeBackground` |
| `rail.badgeForeground` | Text of the activity badge. | `sidebar.highlightBadgeForeground` | `sidebar.highlightBadgeForeground` |
| `rail.border` | Edge of the collapsed sidebar. | `sidebar.border` | `sidebar.border` |

### Tabs

Vivaldi-style tab stacks used when navigation is set to tabs.

| Token | Description | Dark default | Light default |
| --- | --- | --- | --- |
| `tab.barBackground` | Strip behind the tabs. | `sidebar.background` | `sidebar.background` |
| `tab.border` | Strip border and the outline of an attached tab. | `titleBar.border` | `titleBar.border` |
| `tab.foreground` | Text of read tabs. | `sidebar.foreground` | `sidebar.foreground` |
| `tab.unreadForeground` | Text of tabs with unread messages. | `sidebar.unreadForeground` | `sidebar.unreadForeground` |
| `tab.highlightForeground` | Text of tabs with mentions. | `sidebar.highlightForeground` | `sidebar.highlightForeground` |
| `tab.inactiveForeground` | Muted, parted or offline tabs. | `sidebar.disconnectedForeground` | `sidebar.disconnectedForeground` |
| `tab.hoverBackground` | Hovered tab. | `sidebar.hoverBackground` | `sidebar.hoverBackground` |
| `tab.activeBackground` | Selected tab that opens into the conversation. | `chat.background` | `chat.background` |
| `tab.activeForeground` | Text of the selected attached tab. | `chat.foreground` | `chat.foreground` |
| `tab.activeIndicator` | Accent line on the selected tab. | `accent` | `accent` |
| `tab.pillBackground` | Selected floating tab (title bar and pill shapes). | `sidebar.activeBackground` | `sidebar.activeBackground` |
| `tab.pillForeground` | Text of a selected floating tab. | `sidebar.activeForeground` | `sidebar.activeForeground` |
| `tab.separator` | Rule between tabs. | `pane.divider` | `pane.divider` |
| `tab.serverBackground` | Background of the server (network) row. | `rail.background` | `rail.background` |
| `tab.serverActiveBackground` | Selected network in the server row. | `rail.activeBackground` | `rail.activeBackground` |
| `tab.groupBackground` | Segmented network group in the title bar. | `transparent(sidebar.foreground, 7.0%)` | `transparent(sidebar.foreground, 7.0%)` |

### Chat

The conversation view.

| Token | Description | Dark default | Light default |
| --- | --- | --- | --- |
| `chat.background` | Conversation background. | `window.background` | `window.background` |
| `chat.foreground` | Message text. Keep at least 4.5:1 contrast with chat.background. | `window.foreground` | `window.foreground` |
| `chat.secondaryForeground` | Secondary conversation text such as hostnames and metadata. | `mix(chat.foreground, chat.background, 35%)` | `mix(chat.foreground, chat.background, 35%)` |
| `chat.timestamp` | Message timestamps. | `mix(chat.foreground, chat.background, 45%)` | `mix(chat.foreground, chat.background, 45%)` |
| `chat.link` | Links in messages. | `accentText` | `accentText` |
| `chat.selfNick` | Your own nickname on your messages. | `accentText` | `accentText` |
| `chat.selfMessageBackground` | Background behind your own messages. | `chat.background` | `chat.background` |
| `chat.highlightBackground` | Background of messages that mention you. | `mix(chat.background, chat.highlightBorder, 12%)` | `mix(chat.background, chat.highlightBorder, 10%)` |
| `chat.highlightBorder` | Bar along the edge of messages that mention you. | `chat.mention` | `chat.mention` |
| `chat.mention` | Your nickname where it's mentioned in message text. | `accentText` | `accentText` |
| `chat.notice` | NOTICE messages. | `mix(chat.foreground, status.warning, 55.0%)` | `mix(chat.foreground, status.warning, 55.0%)` |
| `chat.action` | /me action messages. | `mix(chat.foreground, accentText, 35%)` | `mix(chat.foreground, accentText, 35%)` |
| `chat.event` | Membership and state events (joins, parts, modes…) unless a more specific token is set. | `chat.secondaryForeground` | `chat.secondaryForeground` |
| `chat.event.join` | Join events. | `mix(chat.event, status.success, 40%)` | `mix(chat.event, status.success, 40%)` |
| `chat.event.part` | Part events. | `mix(chat.event, status.error, 35%)` | `mix(chat.event, status.error, 35%)` |
| `chat.event.quit` | Quit events. | `chat.event.part` | `chat.event.part` |
| `chat.event.nick` | Nickname changes. | `chat.event` | `chat.event` |
| `chat.event.mode` | Mode changes. | `chat.event` | `chat.event` |
| `chat.event.topic` | Topic changes. | `chat.event` | `chat.event` |
| `chat.error` | Errors shown in the conversation. | `status.error` | `status.error` |
| `chat.serverMessage` | Server messages: MOTD, numerics, connection progress. | `chat.secondaryForeground` | `chat.secondaryForeground` |
| `chat.dayDivider` | Line separating days. | `mix(chat.background, chat.foreground, 12%)` | `mix(chat.background, chat.foreground, 12%)` |
| `chat.dayDividerForeground` | Date label on the day divider. | `chat.secondaryForeground` | `chat.secondaryForeground` |
| `chat.unreadMarker` | Line and label marking the first unread message. | `accent` | `accent` |
| `chat.hoverBackground` | Message under the pointer. Usually translucent. | `transparent(chat.foreground, 4%)` | `transparent(chat.foreground, 4%)` |
| `chat.selectionBackground` | Selected text and selected messages. Usually translucent. | `transparent(accent, 30%)` | `transparent(accent, 25%)` |
| `chat.findMatchBackground` | Matches when searching the conversation. Usually translucent. | `transparent(status.warning, 35%)` | `transparent(status.warning, 35%)` |
| `chat.codeBackground` | Background of inline code and preformatted text. | `mix(chat.background, chat.foreground, 7.0%)` | `mix(chat.background, chat.foreground, 5%)` |
| `chat.codeForeground` | Inline code and preformatted text. | `chat.foreground` | `chat.foreground` |

### Input

The message composer.

| Token | Description | Dark default | Light default |
| --- | --- | --- | --- |
| `input.containerBackground` | The bar around the message field. | `chat.background` | `chat.background` |
| `input.background` | The message field. | `mix(input.containerBackground, chat.foreground, 6%)` | `mix(input.containerBackground, #FFFFFF, 70%)` |
| `input.foreground` | Text typed in the message field. | `chat.foreground` | `chat.foreground` |
| `input.placeholder` | Placeholder text in the empty message field. | `mix(input.foreground, input.background, 50%)` | `mix(input.foreground, input.background, 42%)` |
| `input.border` | Border of the message field. | `mix(input.background, input.foreground, 12%)` | `mix(input.background, input.foreground, 15%)` |
| `input.focusBorder` | Border of the message field while it has focus. | `focusBorder` | `focusBorder` |
| `input.iconForeground` | Buttons and icons inside the composer. | `mix(input.foreground, input.background, 35%)` | `mix(input.foreground, input.background, 35%)` |

### Member list

The channel member list.

| Token | Description | Dark default | Light default |
| --- | --- | --- | --- |
| `memberList.background` | Member list background. | `sidebar.background` | `sidebar.background` |
| `memberList.foreground` | Member nicknames (when nick colors are off). | `sidebar.foreground` | `sidebar.foreground` |
| `memberList.headerForeground` | Group headers such as “Operators” and member counts. | `sidebar.headerForeground` | `sidebar.headerForeground` |
| `memberList.prefixForeground` | Mode prefixes (~ & @ % +) before nicknames. | `memberList.headerForeground` | `memberList.headerForeground` |
| `memberList.awayForeground` | Members who are away. | `mix(memberList.foreground, memberList.background, 45%)` | `mix(memberList.foreground, memberList.background, 36%)` |
| `memberList.hoverBackground` | Row under the pointer. | `sidebar.hoverBackground` | `sidebar.hoverBackground` |
| `memberList.border` | Edge between the member list and the conversation. | `pane.divider` | `pane.divider` |

### Embeds

Link previews and inline media cards.

| Token | Description | Dark default | Light default |
| --- | --- | --- | --- |
| `embed.background` | Link preview card background. | `mix(chat.background, chat.foreground, 4%)` | `mix(chat.background, chat.foreground, 3%)` |
| `embed.border` | Link preview card border. | `mix(chat.background, chat.foreground, 12%)` | `mix(chat.background, chat.foreground, 12%)` |
| `embed.accent` | Bar along the edge of a link preview. | `accent` | `accent` |
| `embed.title` | Link preview title. | `chat.link` | `chat.link` |
| `embed.description` | Link preview description. | `mix(chat.foreground, embed.background, 15%)` | `mix(chat.foreground, embed.background, 15%)` |
| `embed.siteName` | Site name above the link preview title. | `chat.secondaryForeground` | `chat.secondaryForeground` |
| `embed.placeholderBackground` | Placeholder shown while an image or video loads. | `mix(embed.background, chat.foreground, 6%)` | `mix(embed.background, chat.foreground, 6%)` |

### Reactions, replies & typing

IRCv3 message reactions, reply quotes and typing indicators.

| Token | Description | Dark default | Light default |
| --- | --- | --- | --- |
| `reaction.background` | Reaction pill. | `mix(chat.background, chat.foreground, 6%)` | `mix(chat.background, chat.foreground, 6%)` |
| `reaction.foreground` | Reaction count. | `chat.foreground` | `chat.foreground` |
| `reaction.border` | Reaction pill border. | `mix(chat.background, chat.foreground, 12%)` | `mix(chat.background, chat.foreground, 12%)` |
| `reaction.selfBackground` | Reaction pill you've added. | `mix(chat.background, accent, 18%)` | `mix(chat.background, accent, 14.0%)` |
| `reaction.selfBorder` | Border of a reaction pill you've added. | `mix(chat.background, accent, 60%)` | `mix(chat.background, accent, 60%)` |
| `reply.quoteBar` | Bar beside the quoted message a reply refers to. | `mix(chat.background, chat.foreground, 25%)` | `mix(chat.background, chat.foreground, 25%)` |
| `reply.foreground` | Quoted message text in a reply. | `chat.secondaryForeground` | `chat.secondaryForeground` |
| `reply.background` | Background of the quoted message in a reply. | `transparent(chat.background, 0%)` | `transparent(chat.background, 0%)` |
| `typing.foreground` | “… is typing” indicator. | `chat.secondaryForeground` | `chat.secondaryForeground` |

### Controls

Accent, buttons, scrollbars and popovers.

| Token | Description | Dark default | Light default |
| --- | --- | --- | --- |
| `accent` | The theme's accent: selection, badges, buttons, focus rings. | `#C792EA` | `#39ADB5` |
| `accentText` | The accent when used as text or thin lines on chat.background (links, your nick, mentions). Set it when accent is too light or dark to read. | `accent` | `mix(accent, #000000, 36%)` |
| `accentForeground` | Text and icons drawn on accent-colored fills. | `contrast(accent)` | `contrast(accent)` |
| `focusBorder` | Focus ring of focused controls. | `accent` | `accent` |
| `button.background` | Primary button. | `accent` | `accent` |
| `button.foreground` | Primary button text. | `accentForeground` | `accentForeground` |
| `button.hoverBackground` | Primary button under the pointer. | `mix(button.background, #FFFFFF, 12%)` | `mix(button.background, #000000, 10%)` |
| `button.secondaryBackground` | Secondary button. | `mix(window.background, window.foreground, 12%)` | `mix(window.background, window.foreground, 8%)` |
| `button.secondaryForeground` | Secondary button text. | `window.foreground` | `window.foreground` |
| `scrollbar.thumb` | Scrollbar thumb. | `transparent(window.foreground, 20%)` | `transparent(window.foreground, 20%)` |
| `scrollbar.thumbHover` | Scrollbar thumb under the pointer. | `transparent(window.foreground, 35%)` | `transparent(window.foreground, 35%)` |
| `popover.background` | Popovers, autocomplete lists and tooltips drawn by Vela. | `mix(window.background, #FFFFFF, 5%)` | `mix(window.background, #FFFFFF, 80%)` |
| `popover.foreground` | Text in popovers. | `window.foreground` | `window.foreground` |
| `popover.border` | Popover border. | `mix(popover.background, popover.foreground, 12%)` | `mix(popover.background, popover.foreground, 12%)` |

### Status

Semantic colors for connection state and feedback.

| Token | Description | Dark default | Light default |
| --- | --- | --- | --- |
| `status.success` | Connected state and success messages. | `#C3E88D` | `#3D7D1E` |
| `status.warning` | Connecting/away state and warnings. | `#FFCB6B` | `#A86400` |
| `status.error` | Disconnected state and errors. | `#FF6B81` | `#D32F2F` |

### Settings window

The Settings window.

| Token | Description | Dark default | Light default |
| --- | --- | --- | --- |
| `settings.background` | Settings window content background. | `window.background` | `window.background` |
| `settings.sidebarBackground` | Settings window sidebar. | `sidebar.background` | `sidebar.background` |
| `settings.foreground` | Settings labels and text. | `window.foreground` | `window.foreground` |
| `settings.secondaryForeground` | Settings help text and captions. | `mix(settings.foreground, settings.background, 40%)` | `mix(settings.foreground, settings.background, 33%)` |
| `settings.border` | Settings section separators. | `pane.divider` | `pane.divider` |
| `settings.controlBackground` | Text fields and grouped rows in Settings. | `input.background` | `input.background` |

### Nick colors

`nickColors` is an array of colors. Each nickname starts from the entry its name hashes to (case-insensitively, RFC 1459 case mapping), so a nick usually keeps its color across channels and launches. In a conversation, people who talk get different entries while the palette has room. Someone whose usual entry is taken by, or looks like the color of, a person in the current exchange gets the entry closest to their usual one that is clearly different; when none is, a look-alike keeps its usual color. Entries that would read as plain text (close to `chat.foreground`) or fall under 3:1 against `chat.background` aren't used.

- Dark default: `#F07178` `#F78C6C` `#FFCB6B` `#C3E88D` `#7FDBCA` `#89DDFF` `#82AAFF` `#B4A5FF` `#C792EA` `#FF9CAC` `#E6B07E` `#A8D8A0`
- Light default: `#C62828` `#BF4A12` `#8C6200` `#4E7A12` `#1B7D4F` `#00727C` `#1565C0` `#3949AB` `#6A3FB5` `#9C27B0` `#AD1457` `#7D5A3C`

### IRC colors

`ircColors` maps mIRC color indexes to colors. 0–15 default to mIRC's classic values; 16–98 to the standard extended palette.

| Index | Name | Default |
| --- | --- | --- |
| 0 | White | `#FFFFFF` |
| 1 | Black | `#000000` |
| 2 | Blue | `#00007F` |
| 3 | Green | `#009300` |
| 4 | Red | `#FF0000` |
| 5 | Brown | `#7F0000` |
| 6 | Magenta | `#9C009C` |
| 7 | Orange | `#FC7F00` |
| 8 | Yellow | `#FFFF00` |
| 9 | Light Green | `#00FC00` |
| 10 | Cyan | `#009393` |
| 11 | Light Cyan | `#00FFFF` |
| 12 | Light Blue | `#0000FC` |
| 13 | Pink | `#FF00FF` |
| 14 | Grey | `#7F7F7F` |
| 15 | Light Grey | `#D2D2D2` |
| 16–98 | Extended palette | see [modern.ircdocs.horse](https://modern.ircdocs.horse/formatting.html#colors-16-98) |
<!-- END TOKEN TABLE -->
