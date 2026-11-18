---
title: License & credits
description: Vela is open source under the Mozilla Public License 2.0. Credits for the Apple frameworks, libraries, data, IRC specifications, theme palettes, website tools and screenshot media Vela builds on.
---

# License & credits

Vela stands on a lot of other people's work: Apple's frameworks, open-source libraries, decades of IRC documentation, the editor themes its palettes come from, and the photos and films in its screenshots. Thank you to everyone below.

## Vela's license

Vela is free and open source under the **[Mozilla Public License 2.0](https://github.com/r3volution11/Vela-IRC/blob/main/LICENSE)**. In short:

- You can use, modify and distribute Vela, including in paid or App Store builds.
- Changes to Vela's own source files must stay open under the MPL.
- Third-party components and ported themes keep their own licenses.

The source code is at [github.com/r3volution11/Vela-IRC](https://github.com/r3volution11/Vela-IRC). Contributions are welcome, especially themes; see [CONTRIBUTING.md](https://github.com/r3volution11/Vela-IRC/blob/main/CONTRIBUTING.md).

## Built with {#built-with}

Vela is a native Mac app, written in **[Swift](https://www.swift.org)** with **[SwiftUI](https://developer.apple.com/swiftui/)** and **[AppKit](https://developer.apple.com/documentation/appkit)**. It's built in [Xcode](https://developer.apple.com/xcode/), its unit tests use [Swift Testing](https://developer.apple.com/documentation/testing), and its app icon was made in [Icon Composer](https://developer.apple.com/icon-composer/).

### Apple frameworks {#apple-frameworks}

| Framework | What Vela uses it for |
| --- | --- |
| [SwiftUI](https://developer.apple.com/documentation/swiftui) | Windows, settings and almost every view |
| [AppKit](https://developer.apple.com/documentation/appkit) | Text editing in the message field and the JSON settings editor, Writing Tools, menus and the Dock icon |
| [Foundation](https://developer.apple.com/documentation/foundation) | Everything underneath: files, dates, text and link fetching |
| [Network](https://developer.apple.com/documentation/network) | IRC connections over TCP and TLS, and noticing when your Mac's network changes |
| [Security](https://developer.apple.com/documentation/security) | The Keychain for passwords, and client certificates for TLS and SASL EXTERNAL |
| [WebKit](https://developer.apple.com/documentation/webkit) | The YouTube, Vimeo, Twitch and Streamable players, which load only when you press play |
| [AVKit](https://developer.apple.com/documentation/avkit) and [AVFoundation](https://developer.apple.com/documentation/avfoundation) | Playing links to video files |
| [Image I/O](https://developer.apple.com/documentation/imageio) and [Core Image](https://developer.apple.com/documentation/coreimage) | Decoding images and animated GIFs, and blurring media until you click it |
| [User Notifications](https://developer.apple.com/documentation/usernotifications) | Notifications for highlights and private messages |
| [Foundation Models](https://developer.apple.com/documentation/foundationmodels) | Catch me up summaries, from the Apple Intelligence model on your Mac |
| [Translation](https://developer.apple.com/documentation/translation) | Translating messages on your Mac |
| [Natural Language](https://developer.apple.com/documentation/naturallanguage) | Working out which language a message is in |
| [App Intents](https://developer.apple.com/documentation/appintents) | Siri and Shortcuts actions |
| [Core Spotlight](https://developer.apple.com/documentation/corespotlight) | Your channels in Spotlight |

Vela also uses [Observation](https://developer.apple.com/documentation/observation), [Uniform Type Identifiers](https://developer.apple.com/documentation/uniformtypeidentifiers), [Core Services](https://developer.apple.com/documentation/coreservices) (to watch theme and settings files for changes), and [Link Presentation](https://developer.apple.com/documentation/linkpresentation) and [GeoToolbox](https://developer.apple.com/documentation/geotoolbox) for Siri's message actions.

## Libraries {#libraries}

| Component | What Vela uses it for | License |
| --- | --- | --- |
| [GRDB.swift](https://github.com/groue/GRDB.swift) by Gwendal Roué | The local message database and its full-text search | MIT |
| [SQLite](https://www.sqlite.org), the copy that comes with macOS | The database engine underneath GRDB | [Public domain](https://www.sqlite.org/copyright.html) |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) by Thomas Zoechling | Importing `.vsix` theme extensions | MIT |

## Data {#data}

| Data | What Vela uses it for | License |
| --- | --- | --- |
| [Sinfonietta/hostfiles](https://github.com/Sinfonietta/hostfiles) `pornography-hosts` | The bundled list behind [Hide previews of adult sites](/guide/inline-media#adult-sites) | MIT, © 2016 Sinfonietta |

Emoji in the reaction picker are searched by their [Unicode](https://unicode.org/emoji/) names, and `:shortcode:` names follow the spellings common in chat apps. Both are built into Vela's code; no emoji data file is bundled.

## IRC specifications {#specifications}

Vela's IRC support is written from these documents. Thanks to the people who keep IRC documented.

- **[Modern IRC Client Protocol](https://modern.ircdocs.horse/)** by Jack Allnutt, Daniel Oaks and Val Lorentz ([ircdocs](https://github.com/ircdocs/modern-irc)): Vela's main reference for the client protocol.
- **[IRC Formatting](https://modern.ircdocs.horse/formatting.html)** (ircdocs): bold, italic, colors, hex colors and the other formatting codes.
- **[Client-to-Client Protocol (CTCP)](https://modern.ircdocs.horse/ctcp.html)** (ircdocs): `/me` actions and CTCP queries.
- **[IRCv3 specifications](https://ircv3.net/irc/)** by the [IRCv3 Working Group](https://ircv3.net/): capability negotiation, SASL, message tags, `server-time`, `chathistory`, reactions, replies, typing and the rest. See [IRCv3 support](/reference/ircv3) for the full list.
- **[RFC 1459](https://www.rfc-editor.org/rfc/rfc1459.html)** and **[RFC 2812](https://www.rfc-editor.org/rfc/rfc2812.html)**: the original IRC protocol documents, which Modern IRC builds on. Vela's `rfc1459` nickname case rules come from RFC 1459.
- **Bouncer extensions**: [soju](https://soju.im)'s [`soju.im/bouncer-networks`](https://codeberg.org/emersion/soju/src/branch/master/doc/ext/bouncer-networks.md) and [ZNC](https://znc.in)'s [`znc.in/playback`](https://wiki.znc.in/Playback).

## Theme credits {#theme-credits}

Every built-in theme file was written for Vela and is distributed under Vela's license, with these attributions. Ports reuse their projects' published color palettes, adjusted where needed for legibility.

| Vela theme | Based on | License |
| --- | --- | --- |
| Dracula | [Dracula for Visual Studio Code](https://github.com/dracula/visual-studio-code) | MIT, © 2016 Dracula Theme |
| Nord | [Nord for Visual Studio Code](https://github.com/nordtheme/visual-studio-code) | MIT, © 2016-present Sven Greb |
| Catppuccin Latte, Catppuccin Mocha | [Catppuccin for VS Code](https://github.com/catppuccin/vscode) and the [Catppuccin palette](https://github.com/catppuccin/palette) | MIT, © 2021 Catppuccin |
| Tokyo Night | [Tokyo Night](https://github.com/tokyo-night/tokyo-night-vscode-theme) | MIT, © 2018-present Enkia |
| One Dark | [One Dark Pro](https://github.com/Binaryify/OneDark-Pro), after Atom's One Dark | MIT, © 2013-2022 Binaryify |
| Gruvbox Dark | [vscode-theme-gruvbox](https://github.com/jdinhify/vscode-theme-gruvbox), palette [Gruvbox](https://github.com/morhetz/gruvbox) by Pavel Pertsev | MIT, © 2017 JD; palette MIT/X11 |
| Solarized Dark, Solarized Light | VS Code's built-in Solarized themes, palette [Solarized](https://github.com/altercation/solarized) by Ethan Schoonover | MIT, © Microsoft Corporation; palette MIT, © 2011 Ethan Schoonover |
| Rosé Pine | [Rosé Pine for VS Code](https://github.com/rose-pine/vscode) | MIT, © 2021 Rosé Pine |

**Palenight, Lighter, Oceanic, Darker, Ocean, Deepforest, Volcano and Sandy Beach** are original Vela themes inspired by the classic variants of the Material Theme by Mattia Astorino and contributors. Vela isn't affiliated with or endorsed by Material Theme or Vira Software, and its themes contain none of their files.

**Vela Graphite, Vela Paper and Vela Mist** are original designs. Their paper-like surfaces and single confident accent were inspired by the look of [Bear](https://bear.app); no colors were taken from Bear's themes.

The full attributions, including the exact changes made to each palette and the MIT license text, are in [THEME-CREDITS.md](https://github.com/r3volution11/Vela-IRC/blob/main/docs/THEME-CREDITS.md) and [THIRD_PARTY_NOTICES.md](https://github.com/r3volution11/Vela-IRC/blob/main/THIRD_PARTY_NOTICES.md).

## Screenshots and demo media {#screenshots}

The screenshots on this site and in the README come from Vela's demo mode. Its conversations are made up, but the pictures, videos and link cards in it are real, loaded from the web when the screenshot is taken. They appear scaled down, and sometimes cropped or blurred, inside Vela's previews.

| Media | Credit | License |
| --- | --- | --- |
| *Big Buck Bunny*, the video players in `#vela` and `#media` | © copyright 2008, Blender Foundation / [www.bigbuckbunny.org](https://peach.blender.org/about/). The YouTube player shows the [4K 60 fps edition](https://www.youtube.com/watch?v=aqz-KE-bpKQ) posted by Blender, whose changes are by [Janus B. Kristensen](https://bbb3d.renderfarming.net/) (2013, CC BY); the [Vimeo copy](https://vimeo.com/1084537) is the original. | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| The Crab Nebula, in `#vela` | NASA, ESA, J. Hester and A. Loll (Arizona State University), via [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Crab_Nebula.jpg) | Public domain |
| The rotating Earth GIF, in `#vela` | [Blue Marble animation](https://visibleearth.nasa.gov/images/57760/blue-marble-animations) by NASA Goddard Space Flight Center (Reto Stöckli; enhancements by Robert Simmon), GIF by Jahobr, via [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Rotating_earth_animated.gif) | Public domain |
| The aurora photo, in `#vela-offtopic` | U.S. Air Force photo by Senior Airman Joshua Strang, via [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Aurora_borealis_over_Eielson_Air_Force_Base,_Alaska.jpg) | Public domain |
| The RCW 38 star cluster, in the link card for ESO's [Star cluster reveals its colours in stunning 80-million-pixel ESO image](https://www.eso.org/public/news/eso2503/) | [ESO/VVVX survey](https://www.eso.org/public/images/eso2503a/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| The rocket launch GIF, in `#macdev` | NASA, via [GIPHY](https://giphy.com/gifs/nasa-space-rocket-launch-x4vlKY5ocArL3SeVVU) | Public domain |
| The GIF of Earth and the space station, in `#macdev` | NASA, via [Tenor](https://tenor.com/view/nasa-nasa-gifs-earth-space-station-space-gif-9368490) | Public domain |

The link cards for [Swift.org](https://www.swift.org/blog/) and the [IRCv3 specifications](https://ircv3.net/irc/) show those sites' own icons. Swift and the Swift logo are trademarks of Apple Inc.; the IRCv3 logo belongs to the IRCv3 Working Group.

## This website {#this-website}

Built with [VitePress](https://vitepress.dev), which runs on [Vue](https://vuejs.org) and [Vite](https://vite.dev), with code highlighting by [Shiki](https://shiki.style) and search by [MiniSearch](https://github.com/lucaong/minisearch), all MIT-licensed. It's styled in Vela's own Palenight and Lighter themes, and its images are [WebP](https://developers.google.com/speed/webp). The site's source is in the [`website` folder](https://github.com/r3volution11/Vela-IRC/tree/main/website) of the Vela repository; if something here is wrong or unclear, **Suggest a change to this page** at the bottom of any page.

## Trademarks

Apple, Mac, macOS, Apple Intelligence, Siri, Spotlight, Xcode, Swift and SwiftUI are trademarks of Apple Inc. Other product names belong to their owners. Vela is an independent project, not affiliated with or endorsed by any of them.
