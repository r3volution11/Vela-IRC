---
title: AI providers
description: Use OpenAI, Anthropic (Claude), Google Gemini, or Ollama or LM Studio on your Mac, for Catch me up and Recap. Vela finds local models and walks you through getting a key.
---

# AI providers

[Catch me up](/guide/apple-intelligence#catch-me-up) and [Recap](/guide/recap) use Apple Intelligence on your Mac by default. You can also have them written by a model of your own choosing:

- **A model on your Mac**, with [Ollama](https://ollama.com) or [LM Studio](https://lmstudio.ai): free, no key, no account, and nothing leaves your Mac. Vela finds them for you.
- **OpenAI**, **Anthropic (Claude)** or **Google Gemini**, with your own API key. Usage is billed by the provider to your account; Gemini has a free tier, with limits.
- **Another server that speaks OpenAI's API**, on your network or elsewhere.

A model of your own also works on a Mac that can't run Apple Intelligence (an Intel Mac, say), so Catch me up and Recap's summaries are there too.

**Translation stays with Apple's Translation framework**, on your Mac, and **Writing Tools** is part of macOS: neither uses your models.

## Settings → AI Providers {#settings}

<!-- Screenshot to come: Settings → AI Providers (website/scripts/screenshots.sh shoots settings-ai-providers). -->

Open **Settings → AI Providers** (<kbd>⌘,</kbd>), or run **AI: Manage Providers…** or **Settings: AI Providers** from the [command palette](/guide/command-palette). From top to bottom:

- **Apple Intelligence:** whether it's ready on this Mac, and **Open System Settings** when it needs turning on.
- **Default model:** the model Catch me up and Recap use, **Automatic (Apple)** until you choose another. See [Choose a model](#choose).
- **Providers:** the ones you've added, with **Add Provider**. See [Add OpenAI, Anthropic or Gemini](#add) and [Other servers](#local-servers).
- **On this Mac:** Ollama or LM Studio, found for you. See [Models on your Mac](#on-this-mac).

Each feature's own model is in **Settings → Intelligence**, in the feature's section; what each provider is sent, and whether it may be, is in **Settings → [AI Privacy](/guide/ai-privacy)**.

## Models on your Mac {#on-this-mac}

When **Settings → AI Providers** opens, Vela looks for [Ollama](https://ollama.com) and [LM Studio](https://lmstudio.ai) on your Mac, and **On this Mac** says what it found:

| What it says | What to do |
| --- | --- |
| **Ollama is running on this Mac, with 3 models.** | Click **Connect**. Ollama is added as a provider, with its models, in one click: no key, no account. |
| **LM Studio is installed, but isn't running.** | Click **Open LM Studio**, and turn on its server in its **Developer** tab. Ollama's server starts when you open Ollama. Vela looks again a few seconds after you click **Open**, and when you come back to it. |
| **Ollama is connected as Ollama.** | It's set up. Its models are in the model menus. |
| Neither is installed | **ollama.com** and **lmstudio.ai** take you to them. Once one is running, Vela finds it. |

**Look Again** looks again at any time. Vela looks only on your Mac (at `127.0.0.1`, on Ollama's port 11434 and LM Studio's port 1234), asks only for the list of models, gives up after a second, and never looks on a timer or in demo mode.

After **Connect**, a sheet shows what Ollama or LM Studio will be sent (they stay on your Mac) and asks you to **Allow** it, and whether Catch me up and Recap should use it: **Use it for Catch me up and Recap** makes the model you pick the default. **Not Now** keeps it connected, and Vela asks the first time it's used.

A model on your Mac can take a while to answer on a slower Mac: the server loads it first, then reads the messages. Vela waits up to 5 minutes for it to start answering. See [Other servers](#local-servers) for its **Context**.

## Add OpenAI, Anthropic or Gemini {#add}

Never made an API key? The setup sheet walks you through it. In **Settings → AI Providers**, click **Add a Provider…** (or **Add Provider**, then the provider):

1. **Choose the provider:** **OpenAI**, **Anthropic (Claude)** or **Google Gemini**. Each says what it costs you: **OpenAI** and **Anthropic** bill your account, which needs credit; **Gemini** has a free tier, with limits, and bills your account beyond it.
2. **Get a key.** **Get a Key** opens the provider's page for keys, in your browser:
   - OpenAI: [platform.openai.com/api-keys](https://platform.openai.com/api-keys). Sign in, choose **Create new secret key**, and copy the key.
   - Anthropic: [platform.claude.com/settings/keys](https://platform.claude.com/settings/keys), in the Claude Console. Sign in, choose **Create Key**, and copy the key.
   - Google Gemini: [aistudio.google.com/apikey](https://aistudio.google.com/apikey), in Google AI Studio. Sign in with your Google account, choose **Create API key**, and copy the key.
3. **Paste it.** Vela checks its shape as you paste: "Looks like an OpenAI key", or what's wrong, such as a key that's cut short, or one that belongs to another provider (with **Use Anthropic Instead**, say).
4. **Test Connection.** Vela asks the provider for its list of models with the key, and says **Connected. 42 models are available.**, or what went wrong: a key it didn't accept, an account out of credit, or no internet connection. Testing sends nothing else, and saves nothing. **Continue** tests the key first if you haven't. When the problem is the connection rather than the key, **Continue Anyway** goes on, and Vela tries the key when it's first used.
5. **Allow it.** The sheet shows exactly what the provider will be sent, and never sent (see [AI privacy](/guide/ai-privacy#sent)), with its data policy. **Use it for Catch me up and Recap** makes it the default model, with its recommended model picked; choose another from the menu, or turn it off to keep your default.
6. **Allow and Add** adds the provider, with your OK. **Cancel**, at any step, adds nothing.

You can add each of OpenAI, Anthropic and Gemini once, and as many servers as you like.

::: tip Costs
Vela doesn't charge anything, and doesn't see your bill. What a summary costs depends on the provider, the model and how much there is to read: check your provider's pricing and usage pages. Vela asks models to keep their thinking short, which keeps summaries quick and cheaper.
:::

### Your providers {#providers}

Each provider in the list shows where it stands (**No key**, **Asks first**, **Allowed** or **Off**), and opens to show its key, its models, whether it may be sent messages (with a link to **AI Privacy**) and **Remove**. The switch on the row turns a provider off without removing it: its models aren't offered, and its key stays.

**Test** fetches a provider's models again; **Connected** says how many it found, or it says what went wrong.

### Keys {#keys}

**Your keys are kept in your Keychain,** under Vela's own entry, and never in settings.json or anywhere else. Once saved, a key is never shown again: **Remove Key** deletes it, and removing a provider deletes its key too. Vela reads a key only when it needs it, and sends it only to its own provider: the setup sheet's **Test Connection** too.

## Choose a model {#choose}

The **Default model**, in **Settings → AI Providers**, is **Automatic (Apple)** until you choose another. Menus list the models in this order:

1. **Automatic (Apple)**: Apple Intelligence on your Mac, as always, with [Private Cloud Compute](/guide/apple-intelligence#private-cloud-compute) for long catch-ups where you've turned it on.
2. **Apple Intelligence on this Mac**: always on your Mac, even for long catch-ups.
3. **Private Cloud Compute**: always with Private Cloud Compute (where it's on; in a later version).
4. **Your providers' models**, each provider under its own name, with Vela's **recommended** pick first.

Vela's recommended picks:

| Provider | Recommended | Also offered before the list is fetched |
| --- | --- | --- |
| OpenAI | GPT-6.2 Sol | GPT-6.2 Astra, GPT-6 Luna |
| Anthropic | Claude Opus 5.5 | Claude Sonnet 5.5, Claude Haiku 5.5 |
| Google Gemini | Gemini 3.8 Flash | Gemini 3.5 Flash-Lite |

Once Vela has fetched a provider's list, its menus offer every model that writes text (not image, speech or embedding models). Lists are fetched when you test a key or **Connect**, when you click **Test**, when you change a key, and when Settings → AI Providers shows a list that's more than a day old. They're kept between launches.

### For Catch me up or Recap only {#per-feature}

**Catch me up** and **Recap** each have a **Model** setting in their own section of **Settings → Intelligence**. It starts as **Same as default**; choose a model to use it for that feature only. The setting appears once there's a model to choose besides Apple's.

### For one summary {#change}

Under a finished Catch me up card, and at the end of a Recap, Vela says which model wrote it, such as "Summarized by Claude Opus 5.5 (Anthropic)." **Change** (or **Change Model** in a Recap) lists the models; choose one to write it again with that model. The card keeps the model you chose when you **Regenerate**.

From the [command palette](/guide/command-palette), **Buffer: Catch Me Up With…** and **Buffer: Recap With…** let you pick the model first, and **AI: Set Default Model…** changes the default. They list the models the same way, with the one in use checked.

## The first time: what's sent {#consent}

A provider is never sent anything until you've agreed. If you added it with the setup sheet, you agreed there. Otherwise (a server you added by hand, say), the first time Catch me up or a Recap would use it, Vela shows the same sheet and sends nothing until you click **Allow and Continue**. **Cancel** sends nothing; the card or Recap says it's waiting for your OK, with **Review…** to see the sheet again and **Use Apple Intelligence** where it can run.

What's sent, what never is, and how to take your OK back are in [AI privacy](/guide/ai-privacy).

## Other servers {#local-servers}

Vela talks to any server with OpenAI's Chat Completions API and its model list (`/v1/models`): Ollama, LM Studio, llama.cpp's server, vLLM and others. To add one by hand, click **Add Provider**, then **Ollama on This Mac**, **LM Studio on This Mac** or **Other OpenAI-Compatible Server**, and open its row:

- **Address:** the server's API address, such as `http://127.0.0.1:11434/v1` for Ollama or `http://127.0.0.1:1234/v1` for LM Studio on your Mac. Typing `localhost:11434` is enough: Vela adds `http://` and `/v1`.
- **http or https:** over plain http, use `localhost`, a `.local` name or an IP address. Any other name needs https.
- **On your network:** the first time Vela connects to a server on another Mac, macOS asks whether Vela may find devices on your local network. Choose **Allow**; you can change it later in **System Settings → Privacy & Security → Local Network**. Servers on your own Mac don't need it.
- **Context:** how much the server reads at once, in tokens. Set it to the context length the server loads models with (it's 4,096 unless you change it). Local servers often load models with a short context and quietly drop what doesn't fit, so Vela reads a long stretch in parts that fit.
- **Key:** optional, for a server that asks for one.
- **Thinking models:** their thinking (`<think>…</think>`) is left out of the summary.

## How it works {#how-it-works}

- **The same instructions as Apple Intelligence.** Your model gets the same prompts, so summaries look the same: an overview, topics with who took part, and what was said to you. Heated channels are summarized neutrally.
- **Fewer passes.** Hosted models read far more at once than the model on your Mac, so a long stretch is usually read in one pass, and a Recap of 2,000 messages too.
- **Low effort.** Models that think before they answer are asked to keep it short, so summaries come quickly and cost less.
- **Streamed and stoppable.** Words appear as they're written. Dismissing a card, closing a Recap or quitting stops the request.
- **Retries.** When a provider is busy or limiting requests, Vela waits as long as it asks (up to 20 seconds) and tries again, twice at most.
- **Nothing is logged or tracked.** Vela keeps no record of what it sends or gets back, and no analytics of any kind.

## When something goes wrong {#problems}

The card or Recap says what happened, with **Try Again**, **Try with Apple Intelligence** where Apple's model can run, and **Open Settings** (Settings → AI Providers) when Settings can fix it:

| Message | What to do |
| --- | --- |
| Couldn't reach … Check your internet connection. | Get back online, then **Try Again**. |
| Couldn't connect to … Make sure the server is running | Start the server (open Ollama, or turn on LM Studio's server), and check its address. |
| … didn't accept your API key. | Paste a new key in **Settings → AI Providers**. |
| There's no API key for … | Add one in **Settings → AI Providers**. |
| Your … account is out of credit or over its usage limit. | Check billing with the provider. |
| … is limiting requests right now. / … is busy or having problems. | Wait a moment and **Try Again**. |
| … declined to summarize this conversation. | Its safety checks turned it down. Try another model, or Apple Intelligence. |
| … doesn't offer the model … to your account. | Choose another model, or **Test** to refresh the list. |
| … is turned off in Settings → AI Providers. | Turn it back on, or choose another model. |
| Vela needs your OK before it sends messages to … | **Review…**, or **Allow…** in **Settings → AI Privacy**. |

**Vela never falls back to another provider on its own.** If your chosen model can't do it, you decide what to try instead.

**Ollama or LM Studio isn't found?** Make sure it's running: Ollama's icon is in the menu bar, and LM Studio's server is on in its **Developer** tab. Vela looks on their usual ports (11434 and 1234); for another port, add it by hand under [Other servers](#local-servers).

## In settings.json {#settings-json}

- [`intelligence.model`](/reference/settings#intelligence.model): the default model, `"apple"` (Automatic), `"apple/on-device"`, or `"<provider id>/<model id>"`, such as `"anthropic/claude-opus-5-5"`.
- [`intelligence.catchUpModel`](/reference/settings#intelligence.catchUpModel) and [`intelligence.recapModel`](/reference/settings#intelligence.recapModel): the same, for one feature; empty follows the default.
- [`intelligence.providers`](/reference/settings#intelligence.providers): your providers, each with its `id`, `kind` (`"openai"`, `"anthropic"`, `"gemini"` or `"openAICompatible"`), `name`, `baseURL` (servers), `enabled`, `consent` and `contextTokens` (servers). Never a key.

```jsonc
"intelligence.model": "anthropic/claude-opus-5-5",
"intelligence.catchUpModel": "ollama/llama3.3",
"intelligence.providers": [
  { "id": "anthropic", "kind": "anthropic", "name": "Anthropic", "enabled": true, "consent": true },
  { "id": "ollama", "kind": "openAICompatible", "name": "Ollama", "baseURL": "http://127.0.0.1:11434/v1",
    "enabled": true, "consent": true, "contextTokens": 16384 }
]
```

Setting `"consent": true` in settings.json counts as agreeing, as the sheet does. In the [settings editor](/customize/settings-editor), `@pane:aiProviders` shows the default model and your providers.
