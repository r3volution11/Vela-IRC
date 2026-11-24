---
title: AI privacy
description: What Vela sends to Apple Intelligence and to the AI providers you add, what it never sends, where it goes, and how to allow a provider or take your OK back, in Settings → AI Privacy.
---

# AI privacy

**Settings → AI Privacy** says, in plain words, what Vela sends to AI models and where. Open it with <kbd>⌘,</kbd>, run **Settings: AI Privacy** from the [command palette](/guide/command-palette), or click **AI Privacy** in **Settings → Intelligence** or on a provider in **Settings → AI Providers**.

<Screenshot src="/screenshots/settings-ai-privacy.webp" alt="Settings → AI Privacy: Apple Intelligence for Catch me up and Recap, Translation and Writing Tools; what a provider gets: Sent, Never sent and Your keys; Your providers, reading No providers; and Spotlight" caption="Settings → AI Privacy, with no providers added." />

The short version: **until you add a provider, your messages go nowhere.** Apple Intelligence summarizes them on your Mac. Add one, and it's sent nothing until you've agreed and you ask for a summary, and then only the messages you asked about, to the model you chose. Vela has no server of its own, keeps no record of what it sends, and has no analytics.

The pane has four parts: **Apple Intelligence**, **What a provider gets**, **Your providers** and **Spotlight**.

## Apple Intelligence {#apple-intelligence}

- **Catch me up and Recap** are summarized on your Mac by Apple Intelligence, unless you choose [a model of your own](/guide/ai-models). Apple Intelligence gets the messages and your nick, never a channel's or network's name. ([Private Cloud Compute](/guide/apple-intelligence#private-cloud-compute) for long catch-ups comes in a later version, and will be off unless you turn it on.)
- **Translation** runs on your Mac, with Apple's Translation framework. macOS downloads each language from Apple once.
- **Writing Tools** is Apple's own: Apple Intelligence handles what you type in the message box as it does in any app.

## What a provider gets {#sent}

When Catch me up or a Recap uses one of [your providers](/guide/ai-models), it's sent:

- **The text and nicks of the messages you ask about, and your own nick**, so the summary can say what was asked of "you". Links are shortened to the site they point to, formatting is taken out, and a very long message is cut short.
- **Vela's instructions** for the summary, the same ones Apple Intelligence gets. For a long stretch read in parts, the model also gets its own notes on the earlier parts, and **More detail** in a Recap sends the messages behind that topic again.

It's **never** sent:

- **The names of channels, networks or servers**, who a Recap is about, or your account. Several conversations in one Recap are told apart by number only, and the messages go without their times.

And:

- **Only when you ask:** a Catch me up or a Recap you start, in Vela or by asking Siri to catch you up, with the model you chose. Nothing is sent in the background, and a provider that fails is never swapped for another.
- **Its list of models** is fetched with your key and nothing else: when you test a key, save one or click **Test**, and when **Settings → AI Providers** opens and its list is missing or more than a day old.
- **Your keys** are kept in your Keychain, never in settings.json, and sent only to their own provider.
- **What comes back** is kept only in memory: a Catch me up summary until you quit Vela, a Recap while its window is open. Requests carry no cookies and leave nothing on disk.

## Your providers {#providers}

Each provider you've added is listed with:

- **Where its messages go.** OpenAI, Anthropic and Google Gemini handle them under their data policy, and the usage is billed to your key. On **Gemini's free tier**, Google may use what's sent to improve its products. Vela asks OpenAI not to store its answers (`store: false`); its data policy covers the rest. A server shows its address and where that is: Ollama or LM Studio on your Mac keeps them on your Mac ("They stay on this Mac, with the server at 127.0.0.1:11434."); for one on your network or the internet, its owner's rules apply.
- **Whether it may be sent messages:** **Allowed**, or **Asks first**. A provider you've turned off in AI Providers says **Off**, or **Off · allowed** when your OK still stands for when you turn it back on.
- **Its policies:** **Data policy** and **Privacy policy** open the provider's own pages: [OpenAI](https://openai.com/enterprise-privacy/) ([privacy policy](https://openai.com/policies/privacy-policy/)), [Anthropic](https://www.anthropic.com/legal/commercial-terms) ([privacy policy](https://www.anthropic.com/legal/privacy)) and [Google](https://aistudio.google.com/docs/terms) ([privacy policy](https://policies.google.com/privacy)).

With no providers, it says **No providers**: Catch me up and Recap use Apple Intelligence on this Mac.

### Allow, or take it back {#consent}

- **Allow…** shows the sheet "Send messages to Anthropic?": what the provider would be sent and never sent, where it goes, and a link to its data policy. **Allow** gives your OK. A provider you add with the [setup sheet](/guide/ai-models#add), or **Connect** for a model on your Mac, asks there, and Catch me up and Recap ask the first time they'd use one that hasn't been allowed.
- **Withdraw** takes your OK back at once, keeping the provider and its key. From then on, Vela sends that provider nothing: Catch me up and Recap ask again before they use it (with **Review…** and **Use Apple Intelligence**), and you can **Allow…** it here again. What it already received is kept under its own policy.
- **Removing a provider**, in **Settings → AI Providers**, deletes its key from your Keychain too.

In settings.json, your OK is the `consent` of each provider in [`intelligence.providers`](/reference/settings#intelligence.providers).

## Spotlight {#spotlight}

**Search messages in Spotlight** is off unless you turn it on, in **Settings → [Integrations](/guide/integrations)**. On, your saved messages are in this Mac's Spotlight index, which stays on your Mac. See [Messages in Spotlight](/guide/siri-shortcuts#messages-in-spotlight).

## Looking for models on your Mac {#local}

When **Settings → AI Providers** is open, Vela asks `127.0.0.1` on ports 11434 and 1234 whether Ollama or LM Studio is running, for the list of models only, and asks macOS whether either app is installed. Nothing leaves your Mac, and macOS doesn't ask about your local network for it. A server on another Mac is contacted only once you add it. See [Models on your Mac](/guide/ai-models#on-this-mac).

See [Privacy](/help/privacy) for everything else Vela does and doesn't do.
