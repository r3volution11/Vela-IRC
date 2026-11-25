# Integrations

Vela's Alfred workflow and Raycast extension live in their own repositories:

- **Alfred workflow:** [r3volution11/vela-alfred-workflow](https://github.com/r3volution11/vela-alfred-workflow). Its releases carry `Vela.alfredworkflow`, which the Alfred Gallery updates from.
- **Raycast extension:** [r3volution11/vela-raycast-extension](https://github.com/r3volution11/vela-raycast-extension), published to the Raycast Store as `vela-irc` (author `r3volution11`).

Both talk to Vela through its AppleScript dictionary (`Vela/Vela.sdef`) and its `vela://` links. **Settings → Integrations** lists them, with Siri and Shortcuts, Spotlight, and AppleScript and links. See [Integrations](https://velairc.app/guide/integrations) on the website.

## The bundled Alfred workflow

Vela carries a built copy of the workflow, so **Settings → Integrations → Install Workflow…** can open it in Alfred:

- `Vela/Integrations/Vela.alfredworkflow` is the file. The Vela target copies it into the app's Resources.
- `integrations/alfred-workflow.json` records it: its `version`, `sha256`, `source` (the release it came from, or `local build` with the `commit` it was built from) and the date it was `updated`. It stays out of the app.

Don't change either by hand. `scripts/update-alfred-workflow.sh` writes both:

```sh
scripts/update-alfred-workflow.sh --release latest     # the workflow's newest release
scripts/update-alfred-workflow.sh --release v1.0.0     # a given release
scripts/update-alfred-workflow.sh --local              # build ../Vela Alfred Workflow with its scripts/build.sh
scripts/update-alfred-workflow.sh --local <dir>        # build a checkout somewhere else
scripts/update-alfred-workflow.sh --check              # the bundled file matches its record
```

Then commit both files. CI, the release preflight and the release's post-build checks fail when the bundled file doesn't match its record. Before a release, bundle a published release of the workflow rather than a local build. See [docs/RELEASING.md](../docs/RELEASING.md#the-alfred-workflow).

## Working across Vela and the extensions

See [CONTRIBUTING.md](../CONTRIBUTING.md#working-across-vela-and-the-extensions): change Vela's dictionary first, keep it compatible, and refresh the bundled workflow last.
