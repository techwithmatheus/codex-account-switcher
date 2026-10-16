# Codex / ChatGPT provider switcher for macOS + zsh.
#
# Commands:
#   codex-personal
#   codex-bedrock
#
# Add -f or --force to close ChatGPT automatically without prompting.

_codex_switcher_dir="$HOME/.config/codex-switcher"
_codex_switcher_config="$_codex_switcher_dir/config"
_codex_personal_state="$_codex_switcher_dir/personal-provider-state"
_codex_config="$HOME/.codex/config.toml"
_codex_app="/Applications/ChatGPT.app"

_codex_switcher_start='# >>> codex-bedrock-switcher >>>'
_codex_switcher_end='# <<< codex-bedrock-switcher <<<'

_codex_load_settings() {
    if [[ ! -f "$_codex_switcher_config" ]]; then
        echo "Switcher config not found: $_codex_switcher_config"
        return 1
    fi

    source "$_codex_switcher_config"

    if [[ -z "$CODEX_BEDROCK_MODEL" || -z "$CODEX_BEDROCK_PROFILE" || -z "$CODEX_BEDROCK_REGION" ]]; then
        echo "Switcher config is incomplete."
        echo "Check: $_codex_switcher_config"
        return 1
    fi
}

_codex_validate_environment() {
    if [[ ! -f "$_codex_config" ]]; then
        echo "Codex config not found: $_codex_config"
        return 1
    fi

    if [[ ! -d "$_codex_app" ]]; then
        echo "ChatGPT app not found at $_codex_app"
        return 1
    fi
}

_codex_prepare_switch() {
    local force="$1"

    if ! pgrep -x "ChatGPT" >/dev/null 2>&1; then
        return 0
    fi

    if [[ "$force" == "-f" || "$force" == "--force" ]]; then
        echo "Closing ChatGPT..."
        osascript -e 'tell application "ChatGPT" to quit'
    else
        echo "ChatGPT is currently running."
        read "reply?Would you like me to close it and continue? [y/N] "

        case "$reply" in
            y|Y|yes|Yes|YES)
                echo "Closing ChatGPT..."
                osascript -e 'tell application "ChatGPT" to quit'
                ;;
            *)
                echo "Switch cancelled."
                return 1
                ;;
        esac
    fi

    local attempts=0

    while pgrep -x "ChatGPT" >/dev/null 2>&1; do
        sleep 0.2
        (( attempts++ ))

        if (( attempts >= 50 )); then
            echo "ChatGPT did not close. Switch cancelled."
            return 1
        fi
    done
}

_codex_validate_markers() {
    local start_count
    local end_count

    start_count=$(grep -Fc "$_codex_switcher_start" "$_codex_config")
    end_count=$(grep -Fc "$_codex_switcher_end" "$_codex_config")

    if [[ "$start_count" == "0" && "$end_count" == "0" ]]; then
        return 0
    fi

    if [[ "$start_count" == "1" && "$end_count" == "1" ]]; then
        return 0
    fi

    echo "The Codex switcher block in config.toml looks malformed."
    echo "No changes were made."
    return 1
}

_codex_backup_config() {
    local backup="${_codex_config}.switcher-backup"

    cp -p "$_codex_config" "$backup" || {
        echo "Could not create config backup."
        return 1
    }

    echo "Safety backup updated: $backup"
}

_codex_launch() {
    open -a ChatGPT
}

_codex_active_provider() {
    awk -F '=' '
        /^[[:space:]]*\[/ {
            exit
        }

        /^[[:space:]]*model_provider[[:space:]]*=/ {
            value = $2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^"|"$/, "", value)
            print value
            exit
        }
    ' "$_codex_config"
}

_codex_has_managed_bedrock() {
    grep -Fq "$_codex_switcher_start" "$_codex_config"
}

_codex_refuse_conflicting_provider() {
    local provider
    provider=$(_codex_active_provider)

    if [[ -n "$provider" && "$provider" != "amazon-bedrock" ]]; then
        echo "A custom model provider is currently active: $provider"
        echo "The switcher will not overwrite it automatically."
        echo "Switch back to your personal ChatGPT/OpenAI configuration first,"
        echo "or follow the manual installation guidance in the repository README."
        return 1
    fi
}

_codex_save_personal_provider_state() {
    awk '
        /^[[:space:]]*\[/ {
            exit
        }

        /^[[:space:]]*model[[:space:]]*=/ ||
        /^[[:space:]]*model_provider[[:space:]]*=/ {
            print
        }
    ' "$_codex_config" > "$_codex_personal_state" || {
        echo "Could not save the personal provider state."
        return 1
    }
}

_codex_strip_top_level_provider_keys() {
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

_codex_restore_personal_state() {
    local source="$1"
    local destination="$2"

    if [[ ! -s "$_codex_personal_state" ]]; then
        cp "$source" "$destination"
        return $?
    fi

    awk -v state_file="$_codex_personal_state" '
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
    ' "$source" > "$destination"
}

codex-personal() {
    _codex_validate_environment || return 1
    _codex_load_settings || return 1
    _codex_prepare_switch "$1" || return 1
    _codex_validate_markers || return 1

    if ! _codex_has_managed_bedrock; then
        local provider
        provider=$(_codex_active_provider)

        if [[ "$provider" == "amazon-bedrock" ]]; then
            echo "Amazon Bedrock is active, but this configuration is not managed by the switcher."
            echo "No changes were made."
            return 1
        fi

        if [[ -n "$provider" ]]; then
            echo "A custom model provider is currently active: $provider"
            echo "No changes were made."
            return 1
        fi

        echo "Already using personal ChatGPT/OpenAI."
        _codex_launch
        return 0
    fi

    _codex_backup_config || return 1

    local without_block
    local stripped
    local restored
    without_block=$(mktemp) || return 1
    stripped=$(mktemp) || {
        rm -f "$without_block"
        return 1
    }
    restored=$(mktemp) || {
        rm -f "$without_block" "$stripped"
        return 1
    }

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
    ' "$_codex_config" > "$without_block" || {
        echo "Could not prepare personal configuration."
        rm -f "$without_block" "$stripped" "$restored"
        return 1
    }

    _codex_strip_top_level_provider_keys "$without_block" "$stripped" || {
        echo "Could not prepare personal configuration."
        rm -f "$without_block" "$stripped" "$restored"
        return 1
    }

    _codex_restore_personal_state "$stripped" "$restored" || {
        echo "Could not restore personal provider settings."
        rm -f "$without_block" "$stripped" "$restored"
        return 1
    }

    cat "$restored" > "$_codex_config" || {
        echo "Could not update Codex configuration."
        rm -f "$without_block" "$stripped" "$restored"
        return 1
    }

    rm -f "$without_block" "$stripped" "$restored"

    echo "Switched to personal ChatGPT/OpenAI."
    _codex_launch
}

codex-bedrock() {
    _codex_validate_environment || return 1
    _codex_load_settings || return 1
    _codex_prepare_switch "$1" || return 1
    _codex_validate_markers || return 1

    if _codex_has_managed_bedrock; then
        echo "Already using Amazon Bedrock."
        _codex_launch
        return 0
    fi

    local provider
    provider=$(_codex_active_provider)

    if [[ "$provider" == "amazon-bedrock" ]]; then
        echo "Amazon Bedrock is already active, but this configuration is not managed by the switcher."
        echo "Run the installer again to adopt it, or follow the manual installation guidance."
        return 1
    fi

    _codex_refuse_conflicting_provider || return 1
    _codex_backup_config || return 1
    _codex_save_personal_provider_state || return 1

    local stripped
    local rewritten
    stripped=$(mktemp) || return 1
    rewritten=$(mktemp) || {
        rm -f "$stripped"
        return 1
    }

    _codex_strip_top_level_provider_keys "$_codex_config" "$stripped" || {
        echo "Could not prepare Bedrock configuration."
        rm -f "$stripped" "$rewritten"
        return 1
    }

    awk -v model="$CODEX_BEDROCK_MODEL" -v profile="$CODEX_BEDROCK_PROFILE" -v region="$CODEX_BEDROCK_REGION" '
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
    ' "$stripped" > "$rewritten" || {
        echo "Could not prepare Bedrock configuration."
        rm -f "$stripped" "$rewritten"
        return 1
    }

    cat "$rewritten" > "$_codex_config" || {
        echo "Could not update Codex configuration."
        rm -f "$stripped" "$rewritten"
        return 1
    }

    rm -f "$stripped" "$rewritten"

    echo "Switched to Amazon Bedrock."
    _codex_launch
}
