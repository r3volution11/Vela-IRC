---
title: Your own AI models
description: Use OpenAI, Anthropic (Claude), Google Gemini or a local server such as Ollama or LM Studio for Vela's Catch me up summaries and Recaps, with your own API key, alongside Apple Intelligence.
---

# Your own AI models

[Catch me up](/guide/apple-intelligence#catch-me-up) and [Recap](/guide/recap) use Apple Intelligence on your Mac by default. You can also have them written by a model of your own choosing:

- **OpenAI**, **Anthropic (Claude)** or **Google Gemini**, with your own API key. Usage is billed to your account with them.
- **A server that speaks OpenAI's API**, such as [Ollama](https://ollama.com) or [LM Studio](https://lmstudio.ai), on this Mac, on your network or elsewhere. With one on your Mac, nothing leaves it.

A model of your own also works on a Mac that can't run Apple Intelligence (an Intel Mac, say), so Catch me up and Recap's summaries are there too.

**Translation stays with Apple's Translation framework**, on your Mac, and **Writing Tools** is part of macOS: neither uses your models.

## Add a provider {#add}

<!-- Screenshot to come: Settings → Intelligence → Models. -->

1. Open **Settings → Intelligence** (<kbd>⌘,</kbd>) and find **Models**, or run **AI: Manage Providers…** from the [command palette](/guide/command-palette).
2. Click **Add Provider** and choose **OpenAI**, **Anthropic (Claude)**, **Google Gemini**, **Ollama on This Mac**, **LM Studio on This Mac** or **Other OpenAI-Compatible Server**.
3. For OpenAI, Anthropic and Gemini, paste your **API key** and click **Save**. **Get a key** opens the page where you make one: [OpenAI](https://platform.openai.com/api-keys), [Anthropic](https://platform.claude.com/settings/keys) or [Google AI Studio](https://aistudio.google.com/apikey). For a server, check its **Address** and, if it needs one, add its key.
4. Vela tests the key right away by fetching the provider's models. **Test** does it again at any time: **Connected** says how many models it found; otherwise it says what went wrong.
5. Choose a model as the **Default model** (above the providers), or for [one feature](#per-feature).

Each provider row shows where it stands (**No key**, **Asks first**, **Allowed** or **Off**) and opens to show its key, its models, its permission and **Remove**. The switch on the row turns a provider off without removing it: its models aren't offered, and its key stays.

You can add each of OpenAI, Anthropic and Gemini once, and as many servers as you like.

### Keys {#keys}

**Your keys are kept in your Keychain,** under Vela's own entry, and never in settings.json or anywhere else. Once saved, a key is never shown again: **Remove Key** deletes it, and removing a provider deletes its key too. Vela reads a key only when it needs it, and sends it only to its own provider.

## Choose a model {#choose}

The **Default model** is **Automatic (Apple)** until you choose another. Menus list the models in this order:

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

Once Vela has fetched a provider's list, its menus offer every model that writes text (not image, speech or embedding models). Lists are refreshed when you click **Test**, when you change a key, and when Settings → Intelligence shows a list that's more than a day old. They're kept between launches.

### For Catch me up or Recap only {#per-feature}

**Catch me up** and **Recap** each have a **Model** setting in their own section of **Settings → Intelligence**. It starts as **Same as default**; choose a model to use it for that feature only. The setting appears once there's a model to choose besides Apple's.

### For one summary {#change}

Under a finished Catch me up card, and at the end of a Recap, Vela says which model wrote it, such as "Summarized by Claude Opus 5.5 (Anthropic)." **Change** (or **Change Model** in a Recap) lists the models; choose one to write it again with that model. The card keeps the model you chose when you **Regenerate**.

From the [command palette](/guide/command-palette), **Buffer: Catch Me Up With…** and **Buffer: Recap With…** let you pick the model first, and **AI: Set Default Model…** changes the default. They list the models the same way, with the one in use checked.

## The first time: what's sent {#consent}

The first time Catch me up or a Recap would use a provider, Vela asks first, and sends nothing until you agree. The sheet says exactly what goes:

- **What's sent:** the text and nicks of the messages you ask about, and your own nick, so the summary can say what was asked of "you". Links are reduced to the site they point to, as always.
- **What's never sent:** the names of channels, networks or servers, or your account.
- **Where it goes:** to that provider, under its data policy (the sheet links to it), and the usage is billed to your API key. On **Gemini's free tier**, Google may use what's sent to improve its products. For a server, the sheet says whether it's on this Mac, on your network or on the internet.

**Allow and Continue** remembers your answer for that provider. **Cancel** sends nothing; the card or Recap says it's waiting for your OK, with **Review…** to see the sheet again and **Use Apple Intelligence** where it can run.

To take it back, open the provider in **Settings → Intelligence** and click **Withdraw**: Vela asks again before sending it anything.

## Local servers {#local-servers}

Vela talks to any server with OpenAI's Chat Completions API and its model list (`/v1/models`): [Ollama](https://ollama.com), [LM Studio](https://lmstudio.ai), llama.cpp's server, vLLM and others.

- **Address:** the server's API address, such as `http://localhost:11434/v1` for Ollama or `http://localhost:1234/v1` for LM Studio. Typing `localhost:11434` is enough: Vela adds `http://` and `/v1`.
- **http or https:** over plain http, use `localhost`, a `.local` name or an IP address. Any other name needs https.
- **On your network:** the first time Vela connects to a server on another Mac, macOS asks whether Vela may find devices on your local network. Choose **Allow**; you can change it later in **System Settings → Privacy & Security → Local Network**.
- **Context:** how much the server reads at once, in tokens. Set it to the context length the server loads models with (it's 4,096 unless you change it). Local servers often load models with a short context and quietly drop what doesn't fit, so Vela reads a long stretch in parts that fit.
- **Key:** optional, for a server that asks for one.
- **Thinking models:** their thinking (`<think>…</think>`) is left out of the summary.

A summary from a local model can take a while on a slower Mac: the server loads the model first, then reads the messages. Vela waits up to 5 minutes for it to start answering.

## How it works {#how-it-works}

- **The same instructions as Apple Intelligence.** Your model gets the same prompts, so summaries look the same: an overview, topics with who took part, and what was said to you. Heated channels are summarized neutrally.
- **Fewer passes.** Hosted models read far more at once than the model on your Mac, so a long stretch is usually read in one pass, and a Recap of 2,000 messages too.
- **Low effort.** Models that think before they answer are asked to keep it short, so summaries come quickly and cost less.
- **Streamed and stoppable.** Words appear as they're written. Dismissing a card, closing a Recap or quitting stops the request.
- **Retries.** When a provider is busy or limiting requests, Vela waits as long as it asks (up to 20 seconds) and tries again, twice at most.
- **Nothing is logged or tracked.** Vela keeps no record of what it sends or gets back, and no analytics of any kind.

## When something goes wrong {#problems}

The card or Recap says what happened, with **Try Again**, **Try with Apple Intelligence** where Apple's model can run, and **Open Settings** when Settings can fix it:

| Message | What to do |
| --- | --- |
| Couldn't reach … Check your internet connection. | Get back online, then **Try Again**. |
| Couldn't connect to … Make sure the server is running | Start the server (`ollama serve`, or LM Studio's server), and check its address. |
| … didn't accept your API key. | Paste a new key in **Settings → Intelligence**. |
| There's no API key for … | Add one in **Settings → Intelligence**. |
| Your … account is out of credit or over its usage limit. | Check billing with the provider. |
| … is limiting requests right now. / … is busy or having problems. | Wait a moment and **Try Again**. |
| … declined to summarize this conversation. | Its safety checks turned it down. Try another model, or Apple Intelligence. |
| … doesn't offer the model … to your account. | Choose another model, or **Test** to refresh the list. |
| … is turned off in Settings → Intelligence. | Turn it back on, or choose another model. |

**Vela never falls back to another provider on its own.** If your chosen model can't do it, you decide what to try instead.

## In settings.json {#settings-json}

- [`intelligence.model`](/reference/settings#intelligence.model): the default model, `"apple"` (Automatic), `"apple/on-device"`, or `"<provider id>/<model id>"`, such as `"anthropic/claude-opus-5-5"`.
- [`intelligence.catchUpModel`](/reference/settings#intelligence.catchUpModel) and [`intelligence.recapModel`](/reference/settings#intelligence.recapModel): the same, for one feature; empty follows the default.
- [`intelligence.providers`](/reference/settings#intelligence.providers): your providers, each with its `id`, `kind`, `name`, `baseURL` (servers), `enabled`, `consent` and `contextTokens` (servers). Never a key.

```jsonc
"intelligence.model": "anthropic/claude-opus-5-5",
"intelligence.catchUpModel": "ollama/llama3.3",
"intelligence.providers": [
  { "id": "anthropic", "kind": "anthropic", "name": "Anthropic", "enabled": true, "consent": true },
  { "id": "ollama", "kind": "openaiCompatible", "name": "Ollama", "baseURL": "http://localhost:11434/v1",
    "enabled": true, "consent": true, "contextTokens": 16384 }
]
```

Setting `"consent": true` in settings.json counts as agreeing, as the sheet does.
