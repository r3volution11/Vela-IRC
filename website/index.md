---
layout: home
title: Vela — A modern, deeply themable IRC client for macOS
titleTemplate: false
description: Vela is a free, open-source IRC client for macOS with 21 built-in themes, VS Code theme import, a sidebar or tab stacks, inline images and video, IRCv3 and ZNC and soju bouncer support.

hero:
  name: Vela
  text: A modern, deeply themable IRC client for macOS
  tagline: A native Mac IRC client with IRCv3, inline media, on-device Apple Intelligence and VS Code-style themes. Make IRC look and work the way you want.
  image:
    src: /vela-icon.webp
    alt: The Vela app icon, a glowing V with a small star in its notch
  actions:
    - theme: brand
      text: Download for macOS
      link: https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg
      target: _self
    - theme: alt
      text: View on GitHub
      link: https://github.com/r3volution11/Vela-IRC

features:
  - title: Themes everywhere
    details: Every surface is drawn from VS Code-style color tokens. 21 built-in themes, a live theme editor, and any VS Code theme imports in one step.
    link: /customize/themes
    linkText: Choosing a theme
  - title: Your layout, your rules
    details: A sidebar, tab stacks or nothing but the conversation. Modern, Classic IRC or Columns messages, at the density you like. Mix them freely; your theme never changes.
    link: /guide/presets
    linkText: Presets
  - title: Modern IRC
    details: IRCv3 reactions, replies, typing and history, SASL and client certificates, and first-class ZNC and soju support.
    link: /reference/ircv3
    linkText: IRCv3 support
---

<ShowcaseRow
  eyebrow="Themes everywhere"
  title="Every pixel is yours to color"
  themes="dracula,nord,catppuccin-latte,tokyo-night,vela-paper,gruvbox-dark"
  link="/customize/themes"
  linkText="Browse the themes"
>

The title bar, sidebar, tabs, chat, input, member list, link previews and even nick colors all come from a theme.

- **21 built-in themes**, from Palenight and Lighter to Dracula, Nord, Catppuccin and Tokyo Night.
- **Select Theme** (<kbd>⌃⌘T</kbd>) previews each one live as you arrow through the list.
- **Import any [VS Code](https://code.visualstudio.com) theme** from a `.json` file or a whole `.vsix` extension.
- A **theme editor** with contrast warnings, and `settings.json` overrides for any color.

</ShowcaseRow>

<ShowcaseRow
  eyebrow="Layouts & presets"
  title="Classic, modern or somewhere in between"
  src="/screenshots/preset-classic.webp"
  alt="The Classic IRC message style: one-line monospace messages with timestamps and angle-bracketed nicks"
  link="/guide/presets"
  linkText="Mix your own"
  reverse
>

Pick a message style: Classic IRC `[12:01] <nick> text` like [irssi](https://irssi.org), Modern like [Slack](https://slack.com) or [Discord](https://discord.com), or Columns like [WeeChat](https://weechat.org).

**Settings → Presets** puts it together in three picks that combine freely: a window layout (**Sidebar**, **Tabs on Top**, **Tabs in Title Bar** or **Focus**), a message style (**Modern**, **Classic IRC** or **Columns**) and a density (**Compact**, **Standard** or **Comfortable**). Your theme is never changed. Fine-tune anything afterwards, down to every setting in a searchable, VS Code-style [settings editor](/customize/settings-editor).

</ShowcaseRow>

<ShowcaseRow
  eyebrow="Sidebar or tab stacks"
  title="Navigate the way you think"
  src="/screenshots/tabs-title-bar.webp"
  alt="Pill-shaped tab stacks in the title bar: networks on the left, the selected network's channels beside them"
  link="/guide/tab-stacks"
  linkText="Tab stacks"
>

On a lot of networks? Use the compact sidebar, which folds into a thin rail when you want more room.

On just a few? Switch to **[Vivaldi](https://vivaldi.com)-style tab stacks**: networks in one row, that network's channels in the next. Put them at the top, in the title bar or above the message field, with corners anywhere from square to pill.

Want nothing but the conversation? The **[Focus](/guide/presets#focus)** layout hides both, and <kbd>⌘P</kbd> takes you anywhere.

</ShowcaseRow>

<ShowcaseRow
  eyebrow="Inline media"
  title="Links that show what's behind them"
  src="/screenshots/home-palenight.webp"
  light="/screenshots/home-lighter.webp"
  alt="An animated GIF and a link card with the page's title, description and image, shown inline in a conversation"
  link="/guide/inline-media"
  linkText="Inline media & privacy"
  reverse
>

Images and animated GIFs appear right in the conversation. Links become cards with the page's title, description and image. YouTube, Vimeo, Twitch and Streamable videos play inline, and their players load only when you press play.

Prefer less? Switch to **compact** previews, turn media off for a channel, or allow it only from domains you trust.

</ShowcaseRow>

<ShowcaseRow
  eyebrow="IRCv3 & bouncers"
  title="IRC, done properly"
  src="/screenshots/preset-focus.webp"
  alt="Pill tabs in the title bar and compact columns of time, nick and message"
  link="/guide/bouncers"
  linkText="Connecting through a bouncer"
>

- **Reactions, replies, typing indicators** and message deletion where the server supports them.
- **`server-time`, `chathistory`, `echo-message`** and the rest of the modern basics, plus STS upgrades.
- **SASL PLAIN and EXTERNAL**, client certificates and TLS, with secrets in your Keychain.
- **[ZNC](https://znc.in) and [soju](https://soju.im)**: playback and self-message for ZNC, automatic network discovery and history for soju, and channels you leave stay on the bouncer.

</ShowcaseRow>

<ShowcaseRow
  eyebrow="Apple Intelligence"
  title="See what you missed"
  src="/screenshots/ai-catch-up.webp"
  alt="A Catch me up card in #swift: an overview of four new messages, a topic with who took part, a note that it was summarized on this Mac, and an Open Full Recap button"
  link="/guide/apple-intelligence"
  linkText="Apple Intelligence & translation"
  reverse
>

Back to a busy channel? **Catch me up** summarizes what you missed, topic by topic, with Apple Intelligence on your Mac.

- **Translate** messages from other languages, one at a time or a whole channel as they arrive.
- **Writing Tools** proofreads your message without touching commands, nicks or links.
- **[Your own models](/guide/ai-models)**, if you like: OpenAI, Anthropic or Google Gemini with your own key, or Ollama or LM Studio on your Mac. Nothing goes to a provider until you add one and say yes.

</ShowcaseRow>

<ShowcaseRow
  eyebrow="Integrations"
  title="Vela from anywhere on your Mac"
  src="/screenshots/settings-integrations.webp"
  alt="Settings → Integrations: cards for Alfred and Raycast, each with what it does, whether it's installed and buttons to set it up"
  link="/guide/integrations"
  linkText="Integrations"
>

Jump to a channel, send a message or catch up without switching to Vela.

- **[Alfred](/guide/alfred-and-raycast#alfred) and [Raycast](/guide/alfred-and-raycast#raycast)** list your channels and conversations, mentions first. The Alfred workflow comes with Vela.
- **Siri and Shortcuts** can catch you up, check your mentions, send a message or set you away.
- **Spotlight** finds your channels and the people you talk to, and can search your saved messages if you turn that on.
- **[Message search](/guide/automation#message-search)** finds what was said, newest first, and shows it in its conversation.
- **[`vela://` links and AppleScript](/guide/automation)** for your own scripts. Links only ever show things; they never send.

</ShowcaseRow>

<ShowcaseRow
  eyebrow="Private by design"
  title="Your chats stay between you and your servers"
  src="/screenshots/media-compact.webp"
  alt="Compact link previews: one-line titles with small thumbnails"
  link="/help/privacy"
  linkText="How Vela handles your data"
  reverse
>

Vela has no telemetry, analytics or accounts. It talks to the IRC servers you add, to velairc.app once a day to check for updates (sending only its version; you can turn that off), and, if you let it, to the sites behind the links people post. Summaries and translations are made on your Mac unless you choose an AI provider of your own, and saving your message history on your Mac is up to you.

Link previews tell those sites your IP address, so you decide: automatic, click-to-load, per channel, or only from an allow list. Vela never fetches previews from addresses on your local network.

</ShowcaseRow>

<div class="home-cta">
  <img src="/vela-icon.webp" alt="" width="96" height="96">
  <h2>Free and open source</h2>
  <p>Vela is written in Swift and SwiftUI, with web views only for video players, previews of sites that need a browser and an update's release notes, and built in the open under the Mozilla Public License 2.0. <a href="/help/license">See the credits</a>.</p>
  <div class="home-cta__actions">
    <a class="vela-button vela-button--brand no-icon" href="https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg">Download for macOS</a>
    <a class="vela-button vela-button--alt" href="/guide/install">Read the guide</a>
  </div>
</div>
