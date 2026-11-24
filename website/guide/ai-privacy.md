---
title: AI privacy
description: What Vela sends to Apple Intelligence and to the AI providers you add, what it never sends, where it goes, and how to allow a provider or take your OK back, in Settings → AI Privacy.
---

# AI privacy

**Settings → AI Privacy** says, in plain words, what Vela sends to AI models and where. Open it with <kbd>⌘,</kbd>, or run **Settings: AI Privacy** from the [command palette](/guide/command-palette).

<!-- Screenshot to come: Settings → AI Privacy (website/scripts/screenshots.sh shoots settings-ai-privacy). -->

The short version: **nothing is sent until you ask for a summary**, and then only the messages you asked about, to the model you chose. Vela has no server of its own, keeps no record of what it sends, and has no analytics.

## Apple Intelligence {#apple-intelligence}

- **Catch me up and Recap** are summarized on your Mac by Apple Intelligence, unless you choose [a model of your own](/guide/ai-models). Apple Intelligence gets the messages and your nick, never a channel's or network's name. ([Private Cloud Compute](/guide/apple-intelligence#private-cloud-compute) for long catch-ups comes in a later version, and will be off unless you turn it on.)
- **Translation** runs on your Mac, with Apple's Translation framework. macOS downloads each language from Apple once.
- **Writing Tools** is Apple's own: Apple Intelligence handles what you type in the message box as it does in any app.

## What a provider gets {#sent}

When Catch me up or a Recap uses one of [your providers](/guide/ai-models), it's sent:

- **The text and nicks of the messages you ask about, and your own nick**, so the summary can say what was asked of "you". Links are shortened to the site they point to.

It's **never** sent:

- **The names of channels, networks or servers**, or your account. Several conversations in one Recap are told apart by number only.

And:

- **Only when you ask:** a Catch me up or a Recap you start, with the model you chose. Nothing is sent in the background, and a provider that fails is never swapped for another.
- **Your keys** are kept in your Keychain, never in settings.json, and sent only to their own provider.

## Your providers {#providers}

Each provider you've added is listed with:

- **Where its messages go.** OpenAI, Anthropic and Google Gemini handle them under their data policy, and the usage is billed to your key. On **Gemini's free tier**, Google may use what's sent to improve its products. A server on your Mac (Ollama or LM Studio) keeps them on your Mac; for one on your network or the internet, its owner's rules apply.
- **Whether it may be sent messages:** **Allowed**, or **Asks first** (with **Off** for a provider you've turned off in AI Providers).
- **Its policies:** **Data policy** and **Privacy policy** open the provider's own pages: [OpenAI](https://openai.com/enterprise-privacy/) ([privacy policy](https://openai.com/policies/privacy-policy/)), [Anthropic](https://www.anthropic.com/legal/commercial-terms) ([privacy policy](https://www.anthropic.com/legal/privacy)) and [Google](https://aistudio.google.com/docs/terms) ([privacy policy](https://policies.google.com/privacy)).

### Allow, or take it back {#consent}

- **Allow…** shows what the provider would be sent, and never sent, and asks for your OK. A provider you add with the [setup sheet](/guide/ai-models#add), or **Connect** for a model on your Mac, asks there.
- **Withdraw** takes your OK back. From then on, Vela sends that provider nothing: Catch me up and Recap ask again before they use it (with **Review…** and **Use Apple Intelligence**), and you can **Allow…** it here again. What it already received is kept under its own policy.

In settings.json, your OK is the `consent` of each provider in [`intelligence.providers`](/reference/settings#intelligence.providers).

## Spotlight {#spotlight}

**Search messages in Spotlight** is off unless you turn it on, in **Settings → [Integrations](/guide/integrations)**. On, your saved messages are in this Mac's Spotlight index, which stays on your Mac. See [Messages in Spotlight](/guide/siri-shortcuts#messages-in-spotlight).

## Looking for models on your Mac {#local}

When **Settings → AI Providers** is open, Vela asks `127.0.0.1` on ports 11434 and 1234 whether Ollama or LM Studio is running, for the list of models only. Nothing leaves your Mac, and macOS doesn't ask about your local network for it. See [Models on your Mac](/guide/ai-models#on-this-mac).

See [Privacy](/help/privacy) for everything else Vela does and doesn't do.
