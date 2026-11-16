---
title: Theme tokens
description: The complete list of Vela theme color tokens, with what each one colors and its default for dark and light themes, plus the nick and mIRC color palettes.
---

# Theme tokens

Every color in Vela comes from one of these tokens. Use them in a [theme file](/customize/creating-themes)'s `colors`, in [`appearance.colorCustomizations`](/customize/settings-json#color-customizations), or find them in the [theme editor](/customize/theme-editor).

Defaults are written as expressions over other tokens:

| Expression | Meaning |
| --- | --- |
| `#RRGGBB` | A fixed color. |
| `token.name` | The value of another token. |
| `mix(a, b, 30%)` | `a` blended 30% of the way toward `b`. |
| `transparent(a, 20%)` | `a` with its opacity multiplied by 20%. |
| `contrast(a)` | White, or a near-black tinted with `a`'s hue, whichever reads better on `a`. |

So you only need to set the tokens you care about; the rest follow. See [How defaults work](/customize/creating-themes#how-defaults-work).

::: info Always current
This reference is generated from Vela's token registry (the same table as in [THEMES.md](https://github.com/r3volution11/Vela-IRC/blob/main/docs/THEMES.md#token-reference)) each time the site is built.
:::

<!--@include: ../_generated/theme-tokens.md-->
