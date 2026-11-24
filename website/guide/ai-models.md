---
title: AI providers
description: Use OpenAI, Anthropic (Claude), Google Gemini, or Ollama or LM Studio on your Mac, for Catch me up and Recap. Vela finds local models and walks you through getting a key.
---

# AI providers

[Catch me up](/guide/apple-intelligence#catch-me-up) and [Recap](/guide/recap) use Apple Intelligence on your Mac by default. You can also have them written by a model of your own choosing:

- **A model on your Mac**, with [Ollama](https://ollama.com) or [LM Studio](https://lmstudio.ai): free, no key, no account, and nothing leaves your Mac. Vela finds them for you.
- **OpenAI**, **Anthropic (Claude)** or **Google Gemini**, with your own API key. Usage is billed by the provider to your account; Gemini has a free tier, with limits.
- **Another server that speaks OpenAI's API**, on your network or elsewhere.

**Nothing changes until you add one.** Apple Intelligence stays the default (**Automatic (Apple)**) until you choose another model, and with no provider added, Vela never contacts one.

A model of your own also works on a Mac that can't run Apple Intelligence (an Intel Mac, say), so Catch me up and Recap's summaries are there too. When you ask Siri to catch you up, it uses the same model as Catch me up.

**Translation stays with Apple's Translation framework**, on your Mac, and **Writing Tools** is part of macOS: neither uses your models.

## Settings → AI Providers {#settings}

<Screenshot src="/screenshots/settings-ai-providers.webp" alt="Settings → AI Providers: a green box saying Apple Intelligence is on, the Default model menu, the Providers section with no providers yet, and On this Mac with links to ollama.com and lmstudio.ai" caption="Settings → AI Providers before you add a provider." />

Open **Settings → AI Providers** (<kbd>⌘,</kbd>), or run **AI: Manage Providers…** or **Settings: AI Providers** from the [command palette](/guide/command-palette). From top to bottom:

- **Apple Intelligence:** a box that says whether it's ready on this Mac, with **Open System Settings** when it needs turning on.
- **Default model:** the model Catch me up and Recap use, **Automatic (Apple)** until you choose another. See [Choose a model](#choose).
- **Providers:** the ones you've added. With none yet, **Add a Provider…** walks you through adding OpenAI, Anthropic or Gemini; **Add Provider**, at the top of the section, adds any kind. See [Add OpenAI, Anthropic or Gemini](#add) and [Other servers](#local-servers).
- **On this Mac:** Ollama or LM Studio, found for you. See [Models on your Mac](#on-this-mac).

Each feature's own model is in **Settings → Intelligence**, in the feature's section; what each provider is sent, and whether it may be, is in **Settings → [AI Privacy](/guide/ai-privacy)**.

Demo mode never goes online, so providers can't be added there: **Providers** says **Not in demo mode**.

## Models on your Mac {#on-this-mac}

When **Settings → AI Providers** opens, Vela looks for [Ollama](https://ollama.com) and [LM Studio](https://lmstudio.ai) on your Mac ("Looking for Ollama and LM Studio…"), and **On this Mac** says what it found:

| What it says | What to do |
| --- | --- |
| **Ollama is running on this Mac, with 3 models.** | Click **Connect**. Ollama is added as a provider, with its models, in one click: no key, no account. |
| **LM Studio is running on this Mac, with no models yet.** | Download a model in LM Studio first, or **Connect** now and **Test** it later. |
| **LM Studio is installed, but isn't running.** | Click **Open LM Studio**, and turn on its server in its **Developer** tab. (Ollama's server starts when you open Ollama.) |
| **Ollama is connected as Ollama.** | It's set up. Its models are in the model menus. |
| **Ollama is connected as Ollama, but isn't running.** | Click **Open Ollama**, so Catch me up and Recap can reach it. |
| Neither is installed | **ollama.com** and **lmstudio.ai** take you to them. Once one is running, Vela finds it. |

**When Vela looks:** when the pane opens, when you click **Look Again**, when you come back to Vela with the pane open, and 3 seconds after you click **Open Ollama** or **Open LM Studio**. Never on a timer, and never in demo mode. It asks only your Mac (`127.0.0.1`, on Ollama's port 11434 and LM Studio's port 1234), only for the list of models, and gives up after a second. Whether each app is installed, it asks macOS.

After **Connect**, a sheet asks "Send messages to Ollama?". It shows what Ollama or LM Studio will be sent (it stays on your Mac), and whether Catch me up and Recap should use it: **Use it for Catch me up and Recap** makes the model you pick the default. **Allow** gives your OK. **Not Now** keeps it connected, and Vela asks the first time it's used.

A model on your Mac can take a while to answer on a slower Mac: the server loads it first, then reads the messages. Vela waits up to 5 minutes for it to start answering. See [Other servers](#local-servers) for its **Context**.

## Add OpenAI, Anthropic or Gemini {#add}

Never made an API key? The setup sheet walks you through it. In **Settings → AI Providers**, click **Add a Provider…** (there while you have no providers), or **Add Provider**, then **OpenAI…**, **Anthropic (Claude)…** or **Google Gemini…** to start at step 2:

1. **Choose the provider:** **OpenAI**, **Anthropic (Claude)** or **Google Gemini**. Each says what it costs you: **OpenAI** and **Anthropic** bill your account, which needs credit; **Gemini** has a free tier, with limits, and bills your account beyond it. One you've already added says **Added**.
2. **Get a key.** **Get a Key** opens the provider's page for keys, in your browser:
   - OpenAI: [platform.openai.com/api-keys](https://platform.openai.com/api-keys). Sign in, choose **Create new secret key**, and copy the key.
   - Anthropic: [platform.claude.com/settings/keys](https://platform.claude.com/settings/keys), in the Claude Console. Sign in, choose **Create Key**, and copy the key.
   - Google Gemini: [aistudio.google.com/apikey](https://aistudio.google.com/apikey), in Google AI Studio. Sign in with your Google account, choose **Create API key**, and copy the key.
3. **Paste it.** Vela checks its shape as you paste: "Looks like an OpenAI key.", or what's wrong, such as a key that's cut short ("OpenAI keys start with sk-. Check that you copied the whole key."), or one that belongs to another provider, with **Use Anthropic Instead**, say. Another provider's key can't be tested here.
4. **Test Connection.** Vela asks the provider for its list of models with the key, and says **Connected. 42 models are available.**, or, under **Couldn't connect**, what went wrong: a key it didn't accept, an account out of credit, or no internet connection. Testing sends nothing but the key and the request for the list, and saves nothing. **Continue** tests the key first if you haven't. When the problem isn't the key (no connection, or the provider is busy or slow), **Continue Anyway** goes on, and Vela tries the key when it's first used.
5. **Allow it.** "Send messages to OpenAI?" shows exactly what the provider will be sent, and never sent (see [AI privacy](/guide/ai-privacy#sent)), with a link to its data policy. **Use it for Catch me up and Recap** makes it the default model, with its recommended model picked; choose another from **Model**, or turn it off to keep your default. It starts on unless your default is already another provider's model.
6. **Allow and Add** adds the provider, with your OK, and saves the key in your Keychain. **Cancel**, at any step, adds nothing and saves nothing; **Back** goes back a step.

You can add each of OpenAI, Anthropic and Gemini once, and as many servers as you like.

::: tip Costs
Vela doesn't charge anything, and doesn't see your bill. What a summary costs depends on the provider, the model and how much there is to read: check your provider's pricing and usage pages. Vela asks models to keep their thinking short, which keeps summaries quick and cheaper.
:::

### Your providers {#providers}

Each provider in the list shows where it stands: **Allowed**, **Asks first** (Vela asks before sending it anything), **No key**, **No address** (a server without one yet) or **Off**. The switch on the row turns a provider off without removing it: its models aren't offered, and its key stays.

Click a provider to open it:

- **Name**, **Address** and **Context**, for a server. See [Other servers](#local-servers).
- **API key:** **Saved in your Keychain**, with **Remove Key**; or a field to paste one, with **Save** and **Get a key**. A key you save is tested right away.
- **Models:** how many it has and Vela's recommended one (**Vela's picks** until its list is fetched), with **Test**, which fetches the list again: **Connected** says how many it found, or **Couldn't connect** says what went wrong.
- **Permission:** whether it may be sent messages, with a link to **AI Privacy**, where you allow it or take it back.
- **Remove Anthropic…** (with the provider's name) asks first, then removes it: its key is deleted from your Keychain, and Catch me up and Recap go back to the default model (or Apple Intelligence) if they used it.

### Keys {#keys}

**Your keys are kept in your Keychain,** under Vela's own entry, and never in settings.json or anywhere else. Once saved, a key is never shown again: **Remove Key** deletes it, and removing a provider deletes its key too. Vela reads a key the first time it needs it, and sends it only to its own provider (the setup sheet's **Test Connection** too), in the request's headers, never in its address.

## Choose a model {#choose}

The **Default model**, in **Settings → AI Providers**, is **Automatic (Apple)** until you choose another. Menus list the models under **Apple**, then each provider's name:

1. **Automatic (Apple)**: Apple Intelligence on your Mac. (In a later version, it will also send long catch-ups to [Private Cloud Compute](/guide/apple-intelligence#private-cloud-compute) if you turn that on.)
2. **Apple Intelligence on this Mac**: always on your Mac. In this version, it's the same as Automatic.
3. **Your providers' models**, for each provider that's on, with Vela's pick first, marked **(recommended)**.

Apple's models are dimmed in **Change** menus while Apple Intelligence can't run, and left out of the command palette's list.

Vela's recommended picks:

| Provider | Recommended | Also offered before the list is fetched |
| --- | --- | --- |
| OpenAI | GPT-6.2 Sol | GPT-6.2 Astra, GPT-6 Luna |
| Anthropic | Claude Opus 5.5 | Claude Sonnet 5.5, Claude Haiku 5.5 |
| Google Gemini | Gemini 3.8 Flash | Gemini 3.5 Flash-Lite |

Once Vela has fetched a provider's list, its menus offer every model that writes text (not image, speech or embedding models). Lists are fetched when you test a key or **Connect**, when you click **Test** or save a key, and when Settings → AI Providers shows a provider whose list is missing or more than a day old. They're kept between launches, in Vela's cache folder (model names and limits only).

### For Catch me up or Recap only {#per-feature}

**Catch me up** and **Recap** each have a **Model** setting in their own section of **Settings → Intelligence**. It starts as **Same as default**; choose a model to use it for that feature only. The setting appears once you've added a provider that's on.

### For one summary {#change}

Under a finished Catch me up card, and at the end of a Recap, Vela says which model wrote it, such as "Summarized by Claude Opus 5.5 (Anthropic)." or "Summarized on this Mac by Apple Intelligence." Once you've added a provider, **Change** (**Change Model** in a Recap) lists the models, with the one that wrote it checked: choose one to write it again with that model, or **Manage Models…** to open **Settings → AI Providers**. The card keeps the model you chose when you **Regenerate**, and a Recap's **More detail** asks the model that wrote it.

From the [command palette](/guide/command-palette), **Buffer: Catch Me Up With…** and **Buffer: Recap With…** (there once you've added a provider) let you pick the model first, and **AI: Set Default Model…** changes the default. They list the models the same way, with the one in use checked.

## The first time: what's sent {#consent}

A provider is never sent anything until you've agreed. If you added it with the setup sheet, or clicked **Allow** after **Connect**, you agreed there. Otherwise (a server you added from **Add Provider**, say, or one you chose **Not Now** for), the first time Catch me up or a Recap would use it, Vela shows the same sheet, "Send messages to Ollama?", and sends nothing until you click **Allow and Continue**. **Cancel** sends nothing: the card or Recap says "Vela needs your OK before it sends messages to Ollama.", with **Review…** to see the sheet again and **Use Apple Intelligence** where it can run (a Recap also has **Show Log**).

Siri can't ask for your OK. If catching up from Siri would use a provider you haven't allowed, Siri says so: catch up in Vela once, and allow it there.

What's sent, what never is, and how to take your OK back are in [AI privacy](/guide/ai-privacy).

## Other servers {#local-servers}

Vela talks to any server with OpenAI's Chat Completions API and its model list (`/v1/models`): Ollama, LM Studio, llama.cpp's server, vLLM and others. To add one by hand, click **Add Provider**, then:

- **Ollama on This Mac** or **LM Studio on This Mac**: adds it at its usual address (`http://127.0.0.1:11434/v1` or `http://127.0.0.1:1234/v1`) and opens its row. Click **Test** to list its models.
- **Other OpenAI-Compatible Server**: adds a "Custom server" with no address yet, and opens its row. Fill in its **Name** and **Address**, click **Save**, then **Test**.

On the server's row:

- **Address:** the server's API address, such as `http://127.0.0.1:11434/v1` for Ollama or `http://127.0.0.1:1234/v1` for LM Studio on your Mac. Typing `localhost:11434` is enough: Vela adds `http://` and `/v1`.
- **http or https:** over plain http, use `localhost`, a `.local` name or an IP address. Any other name needs https.
- **On your network:** the first time Vela connects to a server on another Mac, macOS asks whether Vela may find devices on your local network. Choose **Allow**; you can change it later in **System Settings → Privacy & Security → Local Network**. Servers on your own Mac don't need it.
- **Context:** how much the server reads at once, in tokens: 4,096 unless you change it, up to 131,072. Set it to the context length the server loads models with. Local servers often load models with a short context and quietly drop what doesn't fit, so Vela reads a long stretch in parts that fit.
- **API key (optional):** for a server that asks for one. It's kept in your Keychain, like the others.
- **Thinking models:** their thinking (`<think>…</think>`) is left out of the summary.

## How it works {#how-it-works}

- **The same instructions as Apple Intelligence.** Your model gets the same prompts, so summaries look the same: an overview, topics with who took part, and what was said to you. Heated channels are summarized neutrally.
- **Fewer passes.** Hosted models read far more at once than the model on your Mac, so a long stretch is usually read in one pass, and a Recap of 2,000 messages too.
- **Low effort.** Models that think before they answer (OpenAI's, Claude and Gemini) are asked to keep it short, so summaries come quickly and cost less.
- **Streamed and stoppable.** Words appear as they're written. Dismissing a card, closing a Recap or quitting stops the request.
- **Patience.** Vela waits up to 90 seconds for a hosted provider to start answering (or to go on, once it has), and up to 5 minutes for a server, whose model may need loading first.
- **Retries.** When a provider is busy or limiting requests, Vela waits as long as it asks, up to 20 seconds (1 second, then 2, if it doesn't say), and tries again, twice at most.
- **A part it won't summarize is skipped.** If the provider's safety checks turn down part of a long stretch, the rest is still summarized, and the footer says how many messages were skipped.
- **One catch-up at a time.** Catch me up cards still take turns, whatever their model. A Recap with a model of your own doesn't wait for Apple Intelligence.
- **Nothing is logged or tracked.** Vela keeps no record of what it sends or gets back, and no analytics of any kind. Requests carry no cookies and leave nothing on disk.

## When something goes wrong {#problems}

The card or Recap says what happened, with **Try Again**, **Try with Apple Intelligence** where Apple's model can run, and **Open Settings** (Settings → AI Providers) when Settings can fix it: a key, an address, a model, or a provider that's off or gone. A Recap also has **Show Log**.

| Message | What to do |
| --- | --- |
| Couldn't reach … Check your internet connection. | Get back online, then **Try Again**. |
| Couldn't connect to … Make sure the server is running and its address is right in Settings → AI Providers. | Start the server (open Ollama, or turn on LM Studio's server), and check its address. |
| … took too long to answer. | **Try Again**. For a server on a slow Mac, a smaller model answers sooner. |
| … didn't accept your API key. Check it in Settings → AI Providers. | **Remove Key** on the provider's row, and paste a new one. |
| There's no API key for … Add one in Settings → AI Providers. | Paste the key on the provider's row. |
| Your … account is out of credit or over its usage limit. | Check billing with the provider. |
| … is limiting requests right now. / … is busy or having problems. | Wait a moment and **Try Again**. |
| … declined to summarize this conversation. | Its safety checks turned it down. Try another model, or Apple Intelligence. |
| … doesn't offer the model … to your account. | Choose another model, or **Test** to refresh the list. |
| … didn't return a summary. | **Try Again**, or try another model. |
| … is turned off in Settings → AI Providers. | Turn it back on, or choose another model. |
| The model chosen for this isn't set up any more. | The provider was removed (or isn't in settings.json): choose another model in **Settings → AI Providers**. |
| Vela needs your OK before it sends messages to … | **Review…**, or **Allow…** in **Settings → AI Privacy**. |
| … couldn't do it: … | The provider's own message follows. "This address needs https" means a server's address needs `https://`, or a `localhost`, `.local` or IP address. |

**Vela never falls back to another provider on its own.** If your chosen model can't do it, you decide what to try instead.

**Ollama or LM Studio isn't found?** Make sure it's running: Ollama's icon is in the menu bar, and LM Studio's server is on in its **Developer** tab. Vela looks on their usual ports (11434 and 1234); for another port, add it by hand under [Other servers](#local-servers). A key that doesn't pass **Test Connection**: see [Troubleshooting](/help/troubleshooting#api-key).

## In settings.json {#settings-json}

- [`intelligence.model`](/reference/settings#intelligence.model): the default model, `"apple"` (Automatic, the default), `"apple/on-device"`, or `"<provider id>/<model id>"`, such as `"anthropic/claude-opus-5-5"`. A provider's id is `openai`, `anthropic` or `gemini`, or for a server, its name in lowercase with dashes (`ollama`, `lm-studio`). A model's id can contain slashes: the provider is everything before the first one.
- [`intelligence.catchUpModel`](/reference/settings#intelligence.catchUpModel) and [`intelligence.recapModel`](/reference/settings#intelligence.recapModel): the same, for one feature; empty (the default) follows `intelligence.model`.
- [`intelligence.providers`](/reference/settings#intelligence.providers): your providers, each with its `id`, `kind` (`"openai"`, `"anthropic"`, `"gemini"` or `"openAICompatible"`), `name`, `baseURL` (servers), `enabled`, `consent` and `contextTokens` (servers; left out, it's 4,096). Never a key.

```jsonc
"intelligence.model": "anthropic/claude-opus-5-5",
"intelligence.catchUpModel": "ollama/llama3.3",
"intelligence.providers": [
  { "id": "anthropic", "kind": "anthropic", "name": "Anthropic", "enabled": true, "consent": true },
  { "id": "ollama", "kind": "openAICompatible", "name": "Ollama", "baseURL": "http://127.0.0.1:11434/v1",
    "enabled": true, "consent": true, "contextTokens": 16384 }
]
```

Setting `"consent": true` in settings.json counts as agreeing, as the sheet does. OpenAI, Anthropic or Gemini added here still needs its key, pasted on its row in **Settings → AI Providers**. In the [settings editor](/customize/settings-editor), `@pane:aiProviders` shows the default model and your providers.
