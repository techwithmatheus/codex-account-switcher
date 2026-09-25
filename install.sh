#!/bin/bash

set -e

INSTALL_DIR="$HOME/.config/codex-switcher"
INSTALL_FILE="$INSTALL_DIR/codex-switcher.zsh"
CONFIG_FILE="$INSTALL_DIR/config"
CODEX_CONFIG="$HOME/.codex/config.toml"
ZSHRC="$HOME/.zshrc"

SOURCE_START="# >>> codex-switcher >>>"
SOURCE_END="# <<< codex-switcher <<<"
BEDROCK_START="# >>> codex-bedrock-switcher >>>"
BEDROCK_END="# <<< codex-bedrock-switcher <<<"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

fail() {
    echo ""
    echo "$1"
    exit 1
}

backup_codex_config() {
    cp -p "$CODEX_CONFIG" "${CODEX_CONFIG}.switcher-backup"
    echo "Safety backup updated: ${CODEX_CONFIG}.switcher-backup"
}

active_provider() {
    awk -F '=' '
        /^[[:space:]]*model_provider[[:space:]]*=/ {
            value = $2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^"|"$/, "", value)
            print value
            exit
        }
    ' "$CODEX_CONFIG"
}

top_level_model() {
    awk -F '=' '
        /^[[:space:]]*model[[:space:]]*=/ {
            value = $2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^"|"$/, "", value)
            print value
            exit
        }
    ' "$CODEX_CONFIG"
}

bedrock_value() {
    local key="$1"

    awk -F '=' -v wanted="$key" '
        /^\[model_providers\.amazon-bedrock\.aws\][[:space:]]*$/ {
            in_section = 1
            next
        }

        in_section && /^[[:space:]]*\[/ {
            exit
        }

        in_section {
            key = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)

            if (key == wanted) {
                value = $2
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                gsub(/^"|"$/, "", value)
                print value
                exit
            }
        }
    ' "$CODEX_CONFIG"
}

validate_switcher_markers() {
    local starts
    local ends

    starts=$(grep -Fc "$BEDROCK_START" "$CODEX_CONFIG" || true)
    ends=$(grep -Fc "$BEDROCK_END" "$CODEX_CONFIG" || true)

    if [[ "$starts" == "0" && "$ends" == "0" ]]; then
        return 0
    fi

    if [[ "$starts" == "1" && "$ends" == "1" ]]; then
        return 0
    fi

    fail "Existing Codex switcher markers look malformed. No changes were made."
}

adopt_existing_bedrock() {
    local model
    local profile
    local region
    local wire_api

    model=$(top_level_model)
    profile=$(bedrock_value profile)
    region=$(bedrock_value region)
    wire_api=$(bedrock_value wire_api)

    if [[ -z "$model" || -z "$profile" || -z "$region" || "$wire_api" != "responses" ]]; then
        fail "An Amazon Bedrock provider is active, but its configuration does not match the standard layout this installer can safely adopt.

No changes were made.

You can still install the switcher manually. See the Manual installation section in README.md."
    fi

    echo ""
    echo "Existing Amazon Bedrock configuration found."
    echo ""
    echo "Model:       $model"
    echo "AWS profile: $profile"
    echo "Region:      $region"
    echo ""
    echo "These provider settings will be adopted by the switcher and will not be replaced."
    echo ""
    read -r -p "Continue? [Y/n] " reply

    case "$reply" in
        n|N|no|No|NO)
            echo "Installation cancelled."
            exit 0
            ;;
    esac

    mkdir -p "$INSTALL_DIR"
    cp "$SCRIPT_DIR/codex-switcher.zsh" "$INSTALL_FILE"

    backup_codex_config

    local tmp
    tmp=$(mktemp)

    awk '
        BEGIN {
            in_bedrock = 0
        }

        /^[[:space:]]*model[[:space:]]*=/ {
            next
        }

        /^[[:space:]]*model_provider[[:space:]]*=/ {
            next
        }

        /^\[model_providers\.amazon-bedrock\.aws\][[:space:]]*$/ {
            in_bedrock = 1
            next
        }

        in_bedrock && /^[[:space:]]*\[/ {
            in_bedrock = 0
        }

        !in_bedrock {
            print
        }
    ' "$CODEX_CONFIG" > "$tmp"

    local rewritten
    rewritten=$(mktemp)

    awk -v model="$model" -v profile="$profile" -v region="$region" '
        BEGIN {
            inserted = 0
        }

        !inserted && /^[[:space:]]*\[/ {
            print "# >>> codex-bedrock-switcher >>>"
            print "model = \"" model "\""
            print "model_provider = \"amazon-bedrock\""
            print ""
            print "[model_providers.amazon-bedrock.aws]"
            print "profile = \"" profile "\""
            print "region = \"" region "\""
            print "wire_api = \"responses\""
            print "# <<< codex-bedrock-switcher <<<"
            print ""
            inserted = 1
        }

        {
            print
        }

        END {
            if (!inserted) {
                print ""
                print "# >>> codex-bedrock-switcher >>>"
                print "model = \"" model "\""
                print "model_provider = \"amazon-bedrock\""
                print ""
                print "[model_providers.amazon-bedrock.aws]"
                print "profile = \"" profile "\""
                print "region = \"" region "\""
                print "wire_api = \"responses\""
                print "# <<< codex-bedrock-switcher <<<"
            }
        }
    ' "$tmp" > "$rewritten"

    cat "$rewritten" > "$CODEX_CONFIG"
    rm -f "$tmp" "$rewritten"

    cat > "$CONFIG_FILE" <<EOF
CODEX_BEDROCK_MODEL="$model"
CODEX_BEDROCK_PROFILE="$profile"
CODEX_BEDROCK_REGION="$region"
EOF

    echo "Existing Bedrock configuration adopted."
}

echo "Installing Codex Account Switcher..."

[[ "$(uname -s)" == "Darwin" ]] || fail "This installer currently supports macOS only."
[[ -d "/Applications/ChatGPT.app" ]] || fail "ChatGPT.app was not found in /Applications."
[[ -f "$CODEX_CONFIG" ]] || fail "Codex config not found at ~/.codex/config.toml. Open the ChatGPT desktop app at least once before installing."

validate_switcher_markers

provider=$(active_provider)

if [[ -n "$provider" && "$provider" != "amazon-bedrock" ]]; then
    fail "A custom model provider is currently active: $provider

The automatic installer only handles configurations that currently use
personal ChatGPT/OpenAI or Amazon Bedrock.

No changes were made to ~/.codex/config.toml.

You can still install the switcher manually alongside your existing
provider configuration. See the Manual installation section in README.md."
fi

if [[ "$provider" == "amazon-bedrock" ]]; then
    if grep -Fq "$BEDROCK_START" "$CODEX_CONFIG"; then
        mkdir -p "$INSTALL_DIR"
        cp "$SCRIPT_DIR/codex-switcher.zsh" "$INSTALL_FILE"
        echo "Existing switcher-managed Bedrock configuration found."

        if [[ ! -f "$CONFIG_FILE" ]]; then
            model=$(top_level_model)
            profile=$(bedrock_value profile)
            region=$(bedrock_value region)

            cat > "$CONFIG_FILE" <<EOF
CODEX_BEDROCK_MODEL="$model"
CODEX_BEDROCK_PROFILE="$profile"
CODEX_BEDROCK_REGION="$region"
EOF
        fi
    else
        adopt_existing_bedrock
    fi
else
    mkdir -p "$INSTALL_DIR"
    cp "$SCRIPT_DIR/codex-switcher.zsh" "$INSTALL_FILE"
    echo ""
    echo "No active Amazon Bedrock configuration found."
    echo "The current personal ChatGPT/OpenAI configuration will be left unchanged."

    if [[ ! -f "$CONFIG_FILE" ]]; then
        cp "$SCRIPT_DIR/config.example" "$CONFIG_FILE"
        echo "Created switcher config from config.example."
    else
        echo "Existing switcher config preserved."
    fi
fi

touch "$ZSHRC"

if grep -Fq "$SOURCE_START" "$ZSHRC"; then
    echo "Shell integration is already present in ~/.zshrc."
else
    {
        echo ""
        echo "$SOURCE_START"
        echo '[[ -f "$HOME/.config/codex-switcher/codex-switcher.zsh" ]] && source "$HOME/.config/codex-switcher/codex-switcher.zsh"'
        echo "$SOURCE_END"
    } >> "$ZSHRC"

    echo "Added Codex switcher integration to ~/.zshrc."
fi

echo ""
echo "Installation complete."
echo ""
echo "Review your Bedrock settings at:"
echo "  ~/.config/codex-switcher/config"
echo ""
echo "Reload your shell with:"
echo "  source ~/.zshrc"
echo ""
echo "Then use:"
echo "  codex-personal"
echo "  codex-bedrock"
