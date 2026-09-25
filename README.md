# Codex Account Switcher

Switch the ChatGPT desktop app on macOS between your personal ChatGPT/OpenAI-backed Codex environment and an Amazon Bedrock-backed Codex configuration while keeping the same local Codex workspace.

> **Status:** early development. This repository is private while the installer and switching workflow are being validated.

## What it does

The switcher keeps a single `~/.codex` home so local Codex state can remain shared, and manages only the Amazon Bedrock provider block in `~/.codex/config.toml`.

It provides two zsh commands:

```bash
codex-personal
codex-bedrock
```

Both commands also accept `-f` / `--force` to close ChatGPT automatically before switching.

## Requirements

- macOS
- zsh
- ChatGPT desktop app installed as `/Applications/ChatGPT.app`
- an existing `~/.codex/config.toml`
- for Bedrock: a working AWS profile and Bedrock model configuration

## Install

Clone the repository:

```bash
git clone https://github.com/techwithmatheus/codex-account-switcher.git
cd codex-account-switcher
```

Then run:

```bash
bash install.sh
```

The installer places the switcher under:

```text
~/.config/codex-switcher/
├── codex-switcher.zsh
└── config
```

and adds a small marked block to `~/.zshrc` to load it.

If you are starting from your normal personal ChatGPT/OpenAI configuration, your existing `~/.codex/config.toml` is left untouched.

If Amazon Bedrock is already active using the standard `amazon-bedrock` provider configuration, the installer offers to adopt those settings and place switcher ownership markers around that block instead of creating a duplicate.

After installation, reload your shell:

```bash
source ~/.zshrc
```

## Configuration

The installed configuration lives at:

```text
~/.config/codex-switcher/config
```

The default values are:

```bash
CODEX_BEDROCK_MODEL="openai.gpt-6-astra"
CODEX_BEDROCK_PROFILE="codex-bedrock"
CODEX_BEDROCK_REGION="us-west-2"
```

Edit this file if your model, AWS profile, or Region differs.

Re-running `install.sh` updates the installed switcher script but preserves an existing switcher `config` file.

## Usage

Switch to Amazon Bedrock:

```bash
codex-bedrock
```

Switch back to your personal ChatGPT/OpenAI environment:

```bash
codex-personal
```

If ChatGPT is running, the switcher asks whether it should close the app and continue:

```text
ChatGPT is currently running.
Would you like me to close it and continue? [y/N]
```

To skip that prompt:

```bash
codex-bedrock -f
codex-personal --force
```

The app is asked to quit normally through macOS. The switcher waits for it to exit before editing `config.toml`.

## What gets changed

When Bedrock is active, the switcher owns only this marked block:

```toml
# >>> codex-bedrock-switcher >>>
model = "openai.gpt-6-astra"
model_provider = "amazon-bedrock"

[model_providers.amazon-bedrock.aws]
profile = "codex-bedrock"
region = "us-west-2"
wire_api = "responses"
# <<< codex-bedrock-switcher <<<
```

The values come from the switcher's own config file.

Everything outside those markers is left alone.

Before each automated change, the current Codex configuration is copied to:

```text
~/.codex/config.toml.switcher-backup
```

This is a rolling safety backup of the previous configuration, not an uninstall snapshot.

## Other custom providers

Other `model_providers` definitions can coexist in `config.toml`; the switcher does not remove them.

However, this tool only manages switching between:

```text
Personal ChatGPT / OpenAI
            ⇅
       Amazon Bedrock
```

It is not a general-purpose provider manager.

If another custom provider is currently active, the automatic installer stops rather than guessing how you want that configuration handled. The switcher also refuses to activate Bedrock if doing so would create a conflicting active `model_provider` entry.

You can still integrate the switcher manually alongside a more complex configuration. See **Manual installation** below.

When you later run `codex-personal`, the tool removes its Bedrock override and returns Codex to the normal personal ChatGPT/OpenAI behaviour. It does not remember or restore a third provider you were previously using.

## Manual installation

For configurations the automatic installer deliberately refuses to modify:

1. Create `~/.config/codex-switcher/`.
2. Copy `codex-switcher.zsh` there.
3. Copy `config.example` to `~/.config/codex-switcher/config` and edit the values.
4. Add the following block to `~/.zshrc`:

```bash
# >>> codex-switcher >>>
[[ -f "$HOME/.config/codex-switcher/codex-switcher.zsh" ]] && source "$HOME/.config/codex-switcher/codex-switcher.zsh"
# <<< codex-switcher <<<
```

5. Reload your shell with `source ~/.zshrc`.

If an existing Bedrock block is already active, either switch back to your personal/OpenAI configuration before using the switcher, or carefully place the switcher markers around the exact Bedrock block after ensuring its values match the switcher config.

Always make a manual backup of `~/.codex/config.toml` before changing a complex provider setup.

## Uninstall

Run:

```bash
bash uninstall.sh
```

The uninstaller asks which provider you want to leave configured:

```text
Removing the switcher means ChatGPT will be left configured for a single provider.

Which provider would you like to keep?

1) Personal ChatGPT / OpenAI
2) Amazon Bedrock
3) Cancel
```

Choosing Personal removes the switcher-owned Bedrock block.

Choosing Bedrock keeps the Bedrock configuration but removes the ownership marker comments so it becomes ordinary Codex configuration.

Cancel makes no changes.

The uninstaller does not restore an old install-time copy of `config.toml`, because the rest of that file may have legitimately changed since installation.

## Blog walkthrough

This project accompanies the techWithMatheus article:

**How to Switch Between Your Personal ChatGPT Account and Amazon Bedrock in the ChatGPT Desktop App**

The article explains why the switcher keeps a shared Codex home, how the mechanism was tested, and the practical trade-offs behind the implementation.

> Blog URL will be added when the article is published.

## Contributing

Want support for another provider?

Open a GitHub issue with the provider details and relevant Codex configuration, or submit a pull request if you would like to add support yourself.

The switcher currently focuses on Personal ChatGPT/OpenAI and Amazon Bedrock, so additional providers may require provider-specific handling.
