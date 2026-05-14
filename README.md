# Cryptography Skills
This repo is inspired by  ljagiello.github.io/ctf-skills, but we will focus only on Crypto challenges 

## Crypto workbench

Repo: https://github.com/bacharKachouh/crypto-workbench 

A codex plugin for a paper-to-implementation workflow specific to cryptography papers.

To get started, clone this repository into a stable directory and set the environment variable. For example: 
```bash
export CODEX_PLUGIN_ROOT="$HOME/tools/crypto-workbench"
```

Then to use the plugin, move to your working directory and start codex, make sure to export the path to plugin once again.
```bash
cd workbench-test
export CODEX_PLUGIN_ROOT="$HOME/tools/crypto-workbench"
codex
```
Run `crypto-init`:

<img width="1920" height="528" alt="image" src="https://github.com/user-attachments/assets/3e6fdbfb-91c2-4968-bf74-a8993012ac03" />

## Refreshing the local Codex plugin

If you edit this repo, Codex does not automatically refresh the installed copy
under `~/.codex/plugins/cryptography-skills` or the versioned cache under
`~/.codex/plugins/cache/`.

Use the helper script from the repo root:

```bash
chmod +x ./scripts/reinstall_codex_plugin.sh
./scripts/reinstall_codex_plugin.sh --dry-run
./scripts/reinstall_codex_plugin.sh
```

Notes:

- This syncs the repo into `~/.codex/plugins/cryptography-skills`.
- It also refreshes the matching cache path under
  `~/.codex/plugins/cache/personal-local-plugins/cryptography-skills/<version>`.
- If you want a new cache directory instead of refreshing the current one in
  place, bump `"version"` in [`.codex-plugin/plugin.json`](./.codex-plugin/plugin.json)
  first.
