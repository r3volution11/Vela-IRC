---
title: Settings editor
description: Search, filter and change every Vela setting in Settings → Advanced, or edit settings.json in its JSON view with suggestions, inline problems and docs on hover.
---

# Settings editor

**Settings → Advanced** is Vela's settings editor, modeled on [VS Code](https://code.visualstudio.com)'s. It lists every setting Vela has, including the ones that don't have a control on another pane, each with the right control for its type. Switch to the **JSON** view to edit [settings.json](/customize/settings-json) itself, with suggestions, inline problems and docs on hover.

<Screenshot src="/screenshots/settings-editor.webp" alt="Settings → Advanced in the UI view: a search field with a Modified button, category chips, then the Appearance settings, each titled like “Appearance: Theme” with its description and a control" caption="The settings editor's UI view." />

Both views work on the same file. A change in the UI view, or anywhere else in Settings, shows up in the JSON view, and a change you save in the JSON view applies everywhere.

## Opening it {#opening}

- **Settings → Advanced** (<kbd>⌘,</kbd>, then **Advanced**).
- **Type in the Search field** at the top of the Settings sidebar. The results show in Advanced as you type, and <kbd>Return</kbd> moves you into the editor's own search field.
- **Show in settings editor**, beside the title of the Appearance, Layout, Messages, Media, Networks, Notifications, Apple Intelligence and Updates panes, shows just that pane's settings.
- **Vela → Search Settings…**, or **Settings: Search…** in the [command palette](/guide/command-palette), opens Advanced with the search field ready, keeping your last search.

At the top right, the **UI** | **JSON** switch changes views, and the **⋯** menu has **Open settings.json in External Editor**, **Reveal Data Folder** and [Reset All Settings…](#reset-all).

## Finding a setting {#search}

Type in **Search settings, or type @ for filters**. Words match a setting's title, key, description and current value, so `font`, `chat.clock` and `columns` all find something. The field counts the matches ("12 settings"). <kbd>⌘F</kbd> jumps to it and <kbd>Esc</kbd> clears it.

Type `@` for filters, which you can combine with words and with each other:

| Filter | Shows |
| --- | --- |
| `@modified` | Settings set in settings.json. The **Modified** button beside the field, with its count, turns this on and off. |
| `@unknown` | Keys in settings.json that Vela doesn't know. |
| `@category:chat` | One category, by its id or its name: `appearance`, `layout`, `chat` (or `messages`), `typing`, `history`, `media`, `gifs`, `notifications`, `connection`, `moderation`, `intelligence` and `updates`. |
| `@pane:messages` | The settings on one pane: `appearance`, `layout`, `messages`, `media`, `networks`, `notifications`, `intelligence` or `updates`. This is what **Show in settings editor** uses. |

The chips under the field do the same for categories: **All**, **Appearance**, **Layout**, **Messages**, **Typing**, **History**, **Media**, **Notifications**, **Connection**, **Moderation** and **Apple Intelligence**. An **Unknown** chip, with a warning sign, appears when settings.json has keys Vela doesn't know.

<Screenshot src="/screenshots/settings-editor-modified.webp" alt="The settings editor filtered with @modified: the Modified button is on, with a count of 20, and the list shows only the Appearance and Layout settings that are set in settings.json, each with an accent bar on its left" caption="@modified: only what's set in settings.json." />

## The list {#list}

Settings are grouped by category. Each group's header counts its settings and links to the pane where they usually live ("Messages pane").

Each row shows the setting's name ("Messages: **Layout**") and what it does. Hover the name to see its key, such as `chat.layout`. A bar on the left means the setting is in settings.json: in the accent color for a setting you've changed, in amber for a key Vela doesn't know.

Hover a row and click its **⚙** button, or right-click its name, for:

- **Reset Setting**, which removes it from settings.json so it goes back to its default (**Remove Setting** for an unknown key);
- **Copy Setting ID**, such as `chat.layout`;
- **Copy Setting as JSON**, a line ready to paste into settings.json;
- **Edit in settings.json**, which opens the [JSON view](#json-view) with the value selected, adding the setting with its default value if it isn't in the file yet.

Changes apply immediately. Setting something back to its default removes it from settings.json, as in VS Code, so the file only ever holds what you've changed.

## Controls {#controls}

| Setting | Control |
| --- | --- |
| **On or off** | A switch. |
| **On, off or Same as macOS** (autocorrect, text replacements, smart quotes and dashes) | A switch with **Same as macOS** under it while it follows your Mac. Once you change it, **Use macOS Setting** goes back to following macOS. See [Following macOS](/guide/sending-messages#following-macos). |
| **A choice** | A pop-up menu with readable names, such as **Grouped**, **Text only** or **12-hour**. Hover it to see the value as it's written in settings.json. |
| **A number** | A field and a stepper. Hover the field for the allowed range. Type a number and press <kbd>Return</kbd>; a number out of range says "Must be between 9 and 28." and isn't saved, and <kbd>Esc</kbd> puts the old one back. |
| **Text with suggestions** (fonts, themes, the timestamp format and the translation language) | A field holding one chip. Pick a suggestion or type your own. Fonts are shown in their own typeface, and timestamp formats with a sample time. Remove the chip (**×**) to go back to the default. |
| **A list** (highlight words, and the channels with media turned off, blurred images or automatic translation) | A field of chips. See [below](#chips). |
| **A list of choices** (what the Dock badge counts, and which messages bounce the Dock icon) | A field of chips offering only the setting's choices, with readable names such as **Private messages**. Anything else is refused. |
| **Site rules** | The same editor as **Settings → Media → Site rules**, with **Everything**, **Text only** or **Nothing** for each site. New sites are suggested from your rules and from links in your conversations. See [Site rules](/guide/inline-media#site-rules). |
| **Color customizations** | Override groups. See [below](#color-customizations). |

### Lists of chips {#chips}

- **Click in the field** to see suggestions. Move with <kbd>↑</kbd> <kbd>↓</kbd> and pick one with <kbd>Return</kbd>, <kbd>Tab</kbd> or a click.
- **Type your own** and press <kbd>Return</kbd> or type a comma to add it. A word that's already there isn't added twice.
- **Remove a chip** with its **×**, or press <kbd>⌫</kbd> in the empty field to remove the last one.
- **Channels read like this:** `#vela · Libera.Chat` for one channel, and `All of Libera.Chat` for a whole network.

### Color customizations {#color-customizations}

[`appearance.colorCustomizations`](/customize/settings-json#color-customizations) gets an editor of its own:

- **All themes** comes first, then a group for each theme scope, such as `[Palenight]` or `[Catppuccin *]`, saying which themes it covers. The theme you're using is marked **In use**. Click a group's chevron to fold it.
- **Each override** has its token, a color well, a hex field (`#RGB`, `#RRGGBB` or `#RRGGBBAA`) and a remove button. Hover a token to read what it colors. Tokens set by the [accent color](/customize/themes#accent-color) picker are labeled **Accent picker**; change one here and it becomes yours, so picking **Default** in Settings → Appearance leaves it alone.
- **Add Override** suggests [theme tokens](/reference/theme-tokens) and starts from the theme's current color.
- **Add Overrides for a Theme…** adds a group for a theme name or a pattern such as `Catppuccin *`.
- **Nick colors and [mIRC](https://www.mirc.com) colors** (`nickColors`, `ircColors`) show as swatches, with an **Edit** link to change them in settings.json. **Vibrancy** is a pop-up menu.
- **Edit in settings.json** opens the JSON view at the whole setting.

### Unknown settings {#unknown}

A key Vela doesn't know, perhaps a typo or a setting from a newer version, is listed under **Unknown** with "Unknown setting. Vela keeps it but doesn't use it." Its value is shown as JSON you can edit (Vela checks it as you type), and **Remove** deletes it. The [JSON view](#problems) suggests what you might have meant.

### Reset all settings {#reset-all}

**⋯ → Reset All Settings…** asks "Reset all settings to their defaults?" and says how many settings it will remove. **Reset All Settings** removes them from settings.json; **Cancel** keeps everything. Unknown keys are kept, and your networks, themes and saved message history aren't affected. **Save message history** goes back to its default, off, so new messages aren't saved until you turn it on again; the confirmation says so when it's on.

## The JSON view {#json-view}

Click **JSON** to edit settings.json right in Settings. It's **JSON with Comments**, like VS Code's settings: `//` and `/* */` comments and trailing commas are fine.

<Screenshot src="/screenshots/settings-json.webp" alt="The JSON view with Defaults on: the read-only Default Settings on the left, each setting under a comment describing it, and settings.json on the right with comments, a squiggle under a misspelled key and another under a bad value, and “2 problems” in the bottom bar" caption="The JSON view, with the default settings alongside." />

**Changes apply when you save** (<kbd>⌘S</kbd>), not as you type. Text uses your chat's monospace font, a point smaller than your chat text (between 11 and 16 points), with line numbers, and long lines wrap.

### The toolbar {#toolbar}

From left to right:

| Item | What it does |
| --- | --- |
| **The file's path** | Hover it for the full path, or select it to copy it. **● Edited** follows it while you have unsaved changes, and the **JSON** switch shows a dot. |
| **Defaults** | Shows the read-only [default settings](#defaults) on the left. Vela remembers whether it's on. |
| **Find** (magnifying glass) | Opens the find bar (<kbd>⌘F</kbd>). |
| **Revert** (curved arrow) | Throws away your changes and goes back to the file on disk. |
| **Open in External Editor** | Opens settings.json in your default editor for JSON files. |
| **Save** | Saves the file exactly as you typed it, even if it has errors (<kbd>⌘S</kbd>). |

### Keyboard {#json-keyboard}

| Press | To |
| --- | --- |
| <kbd>⌘S</kbd> | Save |
| <kbd>⌘F</kbd> | Find; <kbd>⌥⌘F</kbd> finds and replaces |
| <kbd>⌘G</kbd> / <kbd>⇧⌘G</kbd> | Next / previous match |
| <kbd>⌘E</kbd> | Find the selected text |
| <kbd>⌃Space</kbd>, <kbd>⌥Esc</kbd> or <kbd>F5</kbd> | Show suggestions |
| <kbd>Tab</kbd> / <kbd>⇧Tab</kbd> | Indent (with the file's own tabs or spaces) / outdent |
| <kbd>Return</kbd> | New line, keeping the indentation, and one level deeper after `{` or `[` |
| <kbd>"</kbd> | Adds the closing quote too, or steps over one that's already there |
| <kbd>⌘Z</kbd> / <kbd>⇧⌘Z</kbd> | Undo / redo |

::: tip ⌃Space does nothing?
macOS uses <kbd>⌃Space</kbd> to switch input sources when you have more than one keyboard language. Use <kbd>⌥Esc</kbd> or <kbd>F5</kbd> instead.
:::

### Suggestions {#suggestions}

<Screenshot src="/screenshots/settings-json-complete.webp" alt="Suggestions after typing “media.” on a new line: media.autoLoad, media.showLinkCards, media.linkPreviewSize and other media settings, each with its title, and below the list the highlighted setting's description and default" caption="Suggestions for a setting name." />

Suggestions appear as you type: after a `"` where a setting name goes, after a `:`, inside a string, and after `[` in a list. Use <kbd>↑</kbd> <kbd>↓</kbd> (or <kbd>Page Up</kbd> <kbd>Page Down</kbd>) to move, <kbd>Return</kbd> or <kbd>Tab</kbd> to insert, or click one. <kbd>Esc</kbd> closes the list.

- **Setting names** come with their title, and the highlighted one's description and default show underneath. A dot marks settings already in the file.
- **Choosing a setting** inserts it with its default value selected, ready to type over, and offers the other values when there's a choice.
- **Values** include `true` and `false`, each setting's choices (inside the list, for lists of choices like `dock.badgeCounts`), your themes and fonts, timestamp formats, translation languages and your channels (`#vela · Libera.Chat`).
- **Inside `appearance.colorCustomizations`**, you get theme tokens, `"[Theme Name]"` scopes, `nickColors`, `ircColors` and `vibrancy`, and for a token's value, the color it has in your current theme.
- **Inside `media.siteRules`**, you get sites from your rules and from links in your conversations, then `"allow"`, `"textOnly"` or `"block"`.

### Problems {#problems}

<Screenshot src="/screenshots/settings-json-problems.webp" alt="A card under the misspelled key “chat.fontSzie” reading “Unknown setting. Did you mean “chat.fontSize”?” with a Change to “chat.fontSize” button, and the problems list open at the bottom with a warning and an error, each with its line and column" caption="Hover a problem for a fix, or open the problems list." />

Vela checks the file as you type. Each problem gets a squiggle under it and a dot beside its line number: red for errors, amber for warnings and gray for notes. Hover a squiggle to read it; for an unknown key with a likely match, click **Change to “…”** to fix it.

The bar at the bottom counts the problems ("2 problems", with errors and warnings), and shows where the cursor is ("Ln 10, Col 5"). Click the count to list them, and click one to jump to it.

| Message | Means |
| --- | --- |
| "Expected a comma." and other syntax errors | The file can't be read. Vela keeps using the last valid settings until it's fixed. |
| "Unknown setting. Did you mean “chat.fontSize”?" | Vela doesn't know the key. It's kept in the file but not used. |
| "“chat.layout” is set again below; only the last one is used." | The same key appears twice. The last one wins, as in VS Code. |
| "Expected true or false.", "Expected a number." and the like | The value has the wrong type, so the setting uses its default. |
| "Expected true, false or `"system"`." | For the three typing settings that can [follow macOS](/guide/sending-messages#following-macos). |
| "Value is not accepted. Valid values: “system”, “12h”, “24h”." | Not one of the setting's choices, so it uses its default. |
| "Value must be between 9 and 28." | A number outside the setting's range. |
| "Replaced by media.siteRules. Vela converts this setting when it starts." | A setting from an older version, which Vela upgrades for you. |

Unknown tokens and malformed colors inside `appearance.colorCustomizations` are flagged too.

### Docs on hover {#hover}

<Screenshot src="/screenshots/settings-json-hover.webp" alt="A card under “history.retentionDays”: History: Keep Messages (Days), marked Modified, with the key, a description, Default 0 and Type “Whole number from 0 to 3650”" caption="Hover a setting to read about it." />

Hover a setting's name for its title and key, what it does, its default, and its type or allowed values. **Modified** means it's set in your settings.json. Hovering a theme token in `appearance.colorCustomizations` says what it colors.

### Default settings {#defaults}

Click **Defaults** to see **Default Settings**, a read-only list of every setting with its description and default value, beside your file. Hover a setting there and click **✎** to copy it into settings.json with its default value, or to jump to it if it's already there.

### Unsaved changes {#unsaved}

| Banner | When | Buttons |
| --- | --- | --- |
| **Save changes to settings.json?** | You switch to the UI view, or close Settings while the JSON view is showing, with unsaved changes. | **Save**, **Discard**, **Cancel** |
| **settings.json changed on disk.** | The file changed (in another editor, say) while you have unsaved changes. | **Reload** takes the version on disk; **Keep My Changes** keeps yours, to save over it. |
| **settings.json has errors.** | You saved a file Vela can't read. Vela keeps using the last valid settings until you fix it. | |
| **settings.json wasn't saved.** | Writing the file failed, with the reason. | |

With no unsaved changes, a change on disk just reloads, keeping your place in the file.

Unsaved changes survive switching panes and closing Settings, but not quitting Vela. There's no Format Document command yet.

## How settings.json is kept tidy {#comments}

Whichever way you change a setting, in the editor, on another pane, with a preset or the accent color picker, Vela changes only that setting's text in settings.json, so your **comments and formatting stay as they are**. See [Comments and formatting](/customize/settings-json#comments) for the details.
