#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
qs_dir="${QS_CAELESTIA_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia}"
config_dir="${CAELESTIA_AI_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/caelestia-ai}"

mkdir -p "$qs_dir" "$config_dir" "$HOME/.local/bin"

cp -r "$repo_dir/quickshell/"* "$qs_dir/"
install -m 755 "$repo_dir/bin/caelestia-blob" "$HOME/.local/bin/caelestia-blob"

if [[ ! -f "$config_dir/.env" ]]; then
    cp "$repo_dir/.env.example" "$config_dir/.env"
fi

if [[ ! -f "$config_dir/api-config.json" ]]; then
    sed "s#~#$HOME#g" "$repo_dir/config/api-config.example.json" > "$config_dir/api-config.json"
fi

if [[ ! -f "$config_dir/telegram.env" ]]; then
    cp "$repo_dir/config/telegram.example.env" "$config_dir/telegram.env"
fi

mkdir -p "$HOME/opencode/prompts"
for prompt in sys special special2 special3 bot; do
    if [[ ! -f "$HOME/opencode/prompts/${prompt}.md" ]]; then
        cp "$repo_dir/prompts/${prompt}.md" "$HOME/opencode/prompts/${prompt}.md"
    fi
done

echo "Installed Caelestia AI module files."
echo "Now edit:"
echo "  $config_dir/.env"
echo "  $config_dir/api-config.json"
echo "  $config_dir/telegram.env (optional)"
echo "Then restart Quickshell: pkill quickshell; quickshell -c caelestia &"

