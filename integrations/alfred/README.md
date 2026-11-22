# Vela for Alfred

Jump to a channel or private conversation in [Vela](https://velairc.app), send a message, and open Catch me up or a Recap, from Alfred. Needs Vela 1.5 or later and Alfred 5 or later with the Powerpack.

## Setup

The first time the workflow lists your conversations, macOS asks: “Alfred wants access to control Vela.” Click **Allow**. If you clicked **Don't Allow**, the workflow offers to open **System Settings → Privacy & Security → Automation**, where you turn on **Vela** under **Alfred**.

## Usage

Search your channels and private conversations via the `vela` keyword. Mentions come first, then what's unread, then the rest, with each one's network and unread and mention counts. Type to filter by name or network, or `vela unread` for what's waiting.

* <kbd>↩</kbd> Show it in Vela.
* <kbd>⌘</kbd><kbd>↩</kbd> Catch me up on it.
* <kbd>⌥</kbd><kbd>↩</kbd> Open a Recap of it.
* <kbd>⌃</kbd><kbd>↩</kbd> Write a message to it. Type the message, then <kbd>↩</kbd> sends it, or <kbd>⌘</kbd><kbd>↩</kbd> puts it in Vela's message box instead, without sending it.
* <kbd>⇧</kbd><kbd>↩</kbd> Mark it read.
* <kbd>⌘</kbd><kbd>C</kbd> Copy its `vela://` link.

Type `vela catch`, `vela recap` or `vela mark` for **Catch Me Up** (the unmuted conversation with the most unread messages), **Open Recap** (every network, since you last read) and **Mark All Read**.

Search your messages in Vela via the `vsearch` keyword.

Alternatively, search for selected text via the Universal Action.

The keywords and which Vela to talk to (Vela, or the Vela Dev development build) are in the [Workflow's Configuration](https://www.alfredapp.com/help/workflows/user-configuration/).

<!-- end of the workflow's About: scripts/build-alfred-workflow.sh puts everything above, from "## Setup", in info.plist's readme. -->

## Install

Download **Vela.alfredworkflow** from the [latest release](https://github.com/r3volution11/Vela-IRC/releases/latest) and double-click it. Alfred asks for the keywords and the app; the defaults are `vela`, `vsearch` and Vela. The [Alfred & Raycast guide](https://velairc.app/guide/alfred-and-raycast) has the details.

## How it works

Every step runs `scripts/vela.js`, one JavaScript for Automation script, with `/usr/bin/osascript`:

| Step | Command | What it does |
| --- | --- | --- |
| `vela` keyword (Script Filter) | `vela.js list` | Asks macOS whether Vela is running (which sends Vela nothing), then reads every conversation's `id`, `name`, `network name`, `kind`, `unread count`, `mention count`, `joined` and `muted`: one Apple event per property, however many conversations you have. Alfred filters the results as you type, and shows the last list at once while it reads a new one (`cache`, 5 seconds, loose reload). |
| ⌃↩, then typing (Script Filter) | `vela.js write "<text>"` | Shows the message you're typing. Doesn't talk to Vela. |
| Every action (Run Script) | `vela.js act` | Sends what the result asked for, from the `vela_action` variable: `show`, `catch up`, `open recap`, `mark read`, `mark all read`, `send message … to …` or `draft message … to …`, each to `conversation id "…"`. Then Alfred posts a notification, only when there's something to say: what was sent, what was marked read, or what went wrong. |
| `vsearch` keyword, Universal Action (Run Script) | `vela.js search "<text>"` | Opens `vela://search?q=…`. Links need no permission and open Vela if it's closed. |

It never launches Vela to list things: if Vela isn't running, the list says so, and ↩ opens it. Errors from Vela's dictionary (velairc.app/guide/automation#errors) become a result or a notification in words: not connected, not in that channel, Catch me up turned off, Apple Intelligence unavailable, still starting (the list asks again every second), and macOS's own (Automation not allowed, no answer).

The **App** setting (`vela_app`) is a bundle id: `io.github.r3volution11.Vela` (Vela) or `io.github.r3volution11.Vela.dev` (Vela Dev, which answers `vela-dev://` links).

## Files

| Path | What it is |
| --- | --- |
| `info.plist` | The workflow: objects, connections, the Workflow's Configuration. Its `version` and `readme` are filled in when it's built. |
| `scripts/vela.js` | Everything the workflow does. |
| `icon.png` | Vela's icon (`docs/vela-icon.png`, 512 × 512). |
| `icons/*.png` | The results' icons, drawn by `icons/make-icons.swift`. |
| `test/vela.test.mjs` | The tests. |
| `test/dictionary-terms.applescript` | The AppleScript for each Apple event the script sends, compiled by the tests against Vela's dictionary. |

## Development

```sh
node --test integrations/alfred/test/*.test.mjs   # the tests: never talk to Vela
scripts/build-alfred-workflow.sh                  # checks, tests, and writes build/Vela.alfredworkflow
swift integrations/alfred/icons/make-icons.swift integrations/alfred/icons   # redraw the result icons
```

The tests run `vela.js` in Node with stand-ins for JXA's `$`, `ObjC` and `Application`: the sorting, the results and their modifiers, subtitles, problems and notifications, every Apple event each action sends, and that nothing launches Vela. They check the plist's connections and configuration, and each term the script uses against `Vela/Vela.sdef`. On macOS they also run the plain functions under `osascript`, and compile `test/dictionary-terms.applescript` against a throwaway stand-in app that carries a copy of `Vela.sdef` (never against Vela, so nothing asks for permission).

To work on the workflow in Alfred, build it, double-click `build/Vela.alfredworkflow`, and choose **Vela Dev** as the app, so your everyday Vela is never involved. Alfred keeps its own copy: after a change, build and import it again, or copy your edits from Alfred's workflow editor back into `info.plist` (keep it XML: `plutil -convert xml1 info.plist`).

### Testing by hand

With Vela Dev running (`scripts/run.sh --dev`), and the workflow set to **Vela Dev**:

1. Import `build/Vela.alfredworkflow`. Alfred asks for the configuration: keep the keywords, choose **Vela Dev**.
2. Type `vela`. macOS asks whether Alfred may control Vela Dev: **Allow**. The list shows mentions, then unread, then the rest, with networks and counts.
3. Type a few letters of a channel and of a network; then `vela unread`.
4. On a channel: ↩ shows it; ⌘↩ opens Catch me up; ⌥↩ opens a Recap; ⇧↩ marks it read (a notification says so); ⌘C copies its `vela-dev://` link.
5. ⌃↩ on a channel you're in, type a message, ↩: it's sent, and a notification shows it. Again with ⌘↩: it's in the message box, not sent. ⌃↩ on a channel you've left says you're not in it.
6. `vela catch`, `vela recap`, `vela mark`: Catch Me Up, Open Recap, Mark All Read.
7. `vsearch release notes`, and the **Search in Vela** Universal Action on selected text: message search opens.
8. Errors: send to a channel on a network you've disconnected (a notification says you're not connected); turn off Catch me up in **Settings → Intelligence** and try ⌘↩; quit Vela Dev and type `vela` (“Vela Dev isn't running”, ↩ opens it); while it starts, the list says so and fills in.
9. In **System Settings → Privacy & Security → Automation**, turn off Vela Dev under Alfred, and type `vela`: the result offers to open those settings.
10. Switch the configuration to **Vela** and repeat 2 and 4 with your everyday Vela, if you like.

## Alfred Gallery

What a Gallery submission needs, and where it stands. Nothing has been submitted.

- **Ready:** the About text (above, in the Gallery's style), keywords of three letters or more that you can change, a Workflow's Configuration rather than environment variables, a 512 × 512 icon, no binaries (only a script anyone can read), nothing downloaded or installed, no updater of its own, and no tracking.
- **Description** (one line): “Jump to a channel or private conversation in Vela, send a message, and open Catch me up or a Recap.”
- **Category:** Productivity.
- **To do:**
  1. Screenshots, per the Gallery's guide (alfred.app/submit/screenshots): the Alfred window only, with its shadow and no wallpaper, nothing from other workflows, and realistic data (Vela's demo networks, `--demo`). Put them in `images/about/` and add them to the About under each paragraph they illustrate:
     - `vela` with mentions, unread and the rest (`conversations.png`);
     - a result with ⌘ held, showing “Catch me up on #…” (`modifiers.png`);
     - the write step with a message typed (`write.png`);
     - `vela catch` or `vela mark` (`commands.png`);
     - `vsearch` with words typed (`search.png`).
  2. Share it on the Alfred forum's **Share your Workflows** board first; the Alfred team invites workflows to the Gallery.
  3. When invited, follow alfred.app/submit: an issue on `alfredapp/gallery-edits`, linking this folder and the release's `Vela.alfredworkflow`.

## License

Part of Vela, under the [Mozilla Public License 2.0](../../LICENSE).
