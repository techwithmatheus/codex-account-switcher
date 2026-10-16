#!/bin/bash

set -e

INSTALL_DIR="$HOME/.config/codex-switcher"
PERSONAL_STATE="$INSTALL_DIR/personal-provider-state"
CODEX_CONFIG="$HOME/.codex/config.toml"
ZSHRC="$HOME/.zshrc"

SOURCE_START="# >>> codex-switcher >>>"
SOURCE_END="# <<< codex-switcher <<<"
BEDROCK_START="# >>> codex-bedrock-switcher >>>"
BEDROCK_END="# <<< codex-bedrock-switcher <<<"

backup_codex_config() {
    if [[ -f "$CODEX_CONFIG" ]]; then
        cp -p "$CODEX_CONFIG" "${CODEX_CONFIG}.switcher-backup"
        echo "Safety backup updated: ${CODEX_CONFIG}.switcher-backup"
    fi
}

remove_bedrock_block() {
    local tmp
    tmp=$(mktemp)

    awk '
        $0 == "# >>> codex-bedrock-switcher >>>" {
            skipping = 1
            next
        }

        $0 == "# <<< codex-bedrock-switcher <<<" {
            skipping = 0
            next
        }

        !skipping {
            print
        }
    ' "$CODEX_CONFIG" > "$tmp"

    cat "$tmp" > "$CODEX_CONFIG"
    rm -f "$tmp"
}

strip_top_level_provider_keys() {
    local source="$1"
    local destination="$2"

    awk '
        BEGIN {
            top_level = 1
        }

        top_level && /^[[:space:]]*\[/ {
            top_level = 0
        }

        top_level && /^[[:space:]]*model[[:space:]]*=/ {
            next
        }

        top_level && /^[[:space:]]*model_provider[[:space:]]*=/ {
            next
        }

        {
            print
        }
    ' "$source" > "$destination"
}

restore_personal_state() {
    [[ -s "$PERSONAL_STATE" ]] || return 0

    local stripped
    local restored
    stripped=$(mktemp)
    restored=$(mktemp)

    strip_top_level_provider_keys "$CODEX_CONFIG" "$stripped"

    awk -v state_file="$PERSONAL_STATE" '
        BEGIN {
            inserted = 0
        }

        !inserted && /^[[:space:]]*\[/ {
            while ((getline line < state_file) > 0) {
                print line
            }
            close(state_file)
            print ""
            inserted = 1
        }

        {
            print
        }

        END {
            if (!inserted) {
                print ""
                while ((getline line < state_file) > 0) {
                    print line
                }
                close(state_file)
            }
        }
    ' "$stripped" > "$restored"

    cat "$restored" > "$CODEX_CONFIG"
    rm -f "$stripped" "$restored"
}

keep_bedrock_without_markers() {
    local tmp
    tmp=$(mktemp)

    awk '
        $0 == "# >>> codex-bedrock-switcher >>>" {
            next
        }

        $0 == "# <<< codex-bedrock-switcher <<<" {
            next
        }

        {
            print
        }
    ' "$CODEX_CONFIG" > "$tmp"

    cat "$tmp" > "$CODEX_CONFIG"
    rm -f "$tmp"
}

remove_zshrc_block() {
    [[ -f "$ZSHRC" ]] || return 0

    local tmp
    tmp=$(mktemp)

    awk '
        $0 == "# >>> codex-switcher >>>" {
            skipping = 1
            next
        }

        $0 == "# <<< codex-switcher <<<" {
            skipping = 0
            next
        }

        !skipping {
            print
        }
    ' "$ZSHRC" > "$tmp"

    cat "$tmp" > "$ZSHRC"
    rm -f "$tmp"
}

echo "Uninstall Codex Account Switcher"
echo ""

if [[ -f "$CODEX_CONFIG" ]] && grep -Fq "$BEDROCK_START" "$CODEX_CONFIG"; then
    echo "Removing the switcher means ChatGPT will be left configured for a single provider."
    echo ""
    echo "Which provider would you like to keep?"
    echo ""
    echo "1) Personal ChatGPT / OpenAI"
    echo "2) Amazon Bedrock"
    echo "3) Cancel"
    echo ""
    read -r -p "Choose [1-3]: " choice

    case "$choice" in
        1)
            backup_codex_config
            remove_bedrock_block
            restore_personal_state
            echo "Personal ChatGPT/OpenAI configuration selected."
            ;;
        2)
            backup_codex_config
            keep_bedrock_without_markers
            echo "Amazon Bedrock configuration selected."
            ;;
        3)
            echo "Uninstall cancelled."
            exit 0
            ;;
        *)
            echo "Invalid choice. No changes were made."
            exit 1
            ;;
    esac
else
    echo "No switcher-managed Bedrock block is currently active."
    echo "Your Codex provider configuration will be left unchanged."
fi

remove_zshrc_block
rm -rf "$INSTALL_DIR"

echo ""
echo "Codex Account Switcher removed."
echo ""
echo "Reload your shell with:"
echo "  source ~/.zshrc"
