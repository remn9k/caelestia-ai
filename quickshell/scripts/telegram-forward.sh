#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${CAELESTIA_AI_TELEGRAM_ENV:-${XDG_CONFIG_HOME:-$HOME/.config}/caelestia-ai/telegram.env}"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

TOKEN="${TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${TELEGRAM_CHAT_ID:-}"
MESSAGE="${1-}"

if [[ -z "$MESSAGE" || -z "$TOKEN" || -z "$CHAT_ID" ]]; then
    exit 0
fi

python - "$TOKEN" "$CHAT_ID" "$MESSAGE" <<'PY'
import json
import html
import re
import sys
import urllib.request

token, chat_id, message = sys.argv[1], sys.argv[2], sys.argv[3]
url = f"https://api.telegram.org/bot{token}/sendMessage"

def markdown_to_html(text: str) -> str:
    escaped = html.escape(text)
    escaped = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', escaped, flags=re.S)
    escaped = re.sub(r'(?<!\*)\*(?!\s)(.+?)(?<!\s)\*(?!\*)', r'<i>\1</i>', escaped, flags=re.S)
    escaped = re.sub(r'`([^`]+)`', r'<code>\1</code>', escaped, flags=re.S)
    escaped = re.sub(r'```([\s\S]*?)```', r'<pre>\1</pre>', escaped, flags=re.S)
    return escaped

payload = json.dumps({
    "chat_id": chat_id,
    "text": markdown_to_html(message),
    "parse_mode": "HTML",
}).encode("utf-8")

req = urllib.request.Request(
    url,
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST",
)

with urllib.request.urlopen(req, timeout=20) as resp:
    resp.read()
PY
