#!/usr/bin/env bash
set -euo pipefail

paths=(
    README.md
    .env.example
    config
    docs
    prompts
    quickshell
    bin
    scripts
    requirements.txt
    .gitignore
)

google_prefix="AI""za"
telegram_token='[0-9]{8,10}:[A-Za-z0-9_-]{30,}'
pattern="${google_prefix}[A-Za-z0-9_-]{20,}|${telegram_token}"

if rg -n "$pattern" "${paths[@]}"; then
    echo "Potential real secret found. Remove it before pushing." >&2
    exit 1
fi

echo "No high-confidence API or Telegram tokens found in publishable files."
