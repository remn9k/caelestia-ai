#!/usr/bin/env bash

set -uo pipefail

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia"
LOG_FILE="${LOG_DIR}/opencode-bridge.log"
OPENCODE_DB="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/opencode.db"
mkdir -p "$LOG_DIR"

log_bridge() {
    {
        printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
    } >> "$LOG_FILE"
}

json_error() {
    jq -nc --arg error "${1:-Unknown error}" '{ ok: false, error: $error }'
}

strip_export_prefix() {
    sed '1{/^Exporting session:/d;}'
}

list_sessions() {
    local db_path

    log_bridge "list-sessions"
    db_path="$OPENCODE_DB"
    if [[ ! -f "$db_path" ]]; then
        jq -nc '{ ok: true, sessions: [] }'
        return
    fi

    python - "$db_path" <<'PY'
import json, sqlite3, sys

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
rows = conn.execute(
    """
    select id, title, directory, time_updated
    from session
    where time_archived is null
    order by time_updated desc
    """
).fetchall()
print(json.dumps({
    "ok": True,
    "sessions": [
        {
            "id": row["id"],
            "title": row["title"] or row["id"],
            "directory": row["directory"] or "",
            "updated": row["time_updated"] or 0,
        }
        for row in rows
    ],
}, ensure_ascii=False))
PY
}

list_models() {
    local raw attempt

    log_bridge "list-models"
    raw=""
    for attempt in 1 2 3; do
        raw="$(opencode models --verbose 2>/dev/null || true)"
        [[ -n "$raw" ]] && break
        sleep 0.2
    done
    if [[ -z "$raw" ]]; then
        jq -nc '{
            ok: true,
            models: [
                {
                    id: "opencode/gpt-5-nano",
                    label: "GPT-5 Nano",
                    provider: "opencode",
                    reasoning: true,
                    attachments: true,
                    variants: ["minimal", "low", "medium", "high"]
                }
            ]
        }'
        return
    fi

    RAW_MODELS="$raw" OPENCODE_CONFIG_PATH="${OPENCODE_CONFIG_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json}" OPENCODE_DESKTOP_STATE_PATH="${OPENCODE_DESKTOP_STATE_PATH:-$HOME/.config/ai.opencode.desktop/opencode.global.dat.json}" python - <<'PY'
import json
import os
import re

raw = os.environ.get("RAW_MODELS", "")
config_path = os.environ.get("OPENCODE_CONFIG_PATH", "")
desktop_state_path = os.environ.get("OPENCODE_DESKTOP_STATE_PATH", "")
header_re = re.compile(r"^[A-Za-z0-9._-]+/[A-Za-z0-9._:-]+$")
parsed_models = {}
current_id = None
buffer = []
depth = 0

for line in raw.splitlines():
    stripped = line.strip()
    if header_re.match(stripped):
        current_id = stripped
        buffer = []
        depth = 0
        continue

    if not current_id:
        continue

    if not buffer and not stripped.startswith("{"):
        continue

    buffer.append(line)
    depth += line.count("{") - line.count("}")
    if depth == 0 and buffer:
        try:
            data = json.loads("\n".join(buffer))
        except Exception:
            current_id = None
            buffer = []
            depth = 0
            continue

        model = {
            "id": data.get("fullID") or current_id or f'{data.get("providerID", "opencode")}/{data.get("id", "")}',
            "label": data.get("name") or data.get("id") or "Model",
            "provider": data.get("providerID") or (current_id.split("/", 1)[0] if "/" in current_id else "opencode"),
            "reasoning": (((data.get("capabilities") or {}).get("reasoning")) or False),
            "attachments": ((((data.get("capabilities") or {}).get("input") or {}).get("image")) or False),
            "variants": list(((data.get("variants") or {}).keys())),
        }
        parsed_models[model["id"]] = model
        current_id = None
        buffer = []
        depth = 0

provider_order = []
enabled_models = []
ui_models = []

if desktop_state_path and os.path.exists(desktop_state_path):
    try:
        with open(desktop_state_path, "r", encoding="utf-8") as fh:
            desktop_state = json.load(fh)
        model_blob = desktop_state.get("model")
        if isinstance(model_blob, str) and model_blob.strip():
            parsed_blob = json.loads(model_blob)
            for item in parsed_blob.get("user", []) or []:
                if (item or {}).get("visibility") != "show":
                    continue
                provider = (item or {}).get("providerID") or ""
                model_id = (item or {}).get("modelID") or ""
                if not provider or not model_id:
                    continue
                ui_models.append({
                    "provider": provider,
                    "model_id": model_id,
                    "full_id": f"{provider}/{model_id}",
                })
    except Exception:
        ui_models = []

if config_path and os.path.exists(config_path):
    try:
        with open(config_path, "r", encoding="utf-8") as fh:
            config = json.load(fh)
        providers = (config.get("provider") or {})
        disabled_providers = set(config.get("disabled_providers") or [])
        for provider_id, provider_config in providers.items():
            if provider_id in disabled_providers:
                continue
            provider_order.append(provider_id)
            provider_models = ((provider_config or {}).get("models") or {})
            for model_id, model_config in provider_models.items():
                enabled_models.append({
                    "provider": provider_id,
                    "model_id": model_id,
                    "full_id": f"{provider_id}/{model_id}",
                    "label": ((model_config or {}).get("name") or model_id),
                })
    except Exception:
        provider_order = []
        enabled_models = []

models = []
if ui_models:
    config_name_map = {}
    for entry in enabled_models:
        config_name_map[entry["full_id"]] = entry["label"]
    for entry in ui_models:
        parsed = parsed_models.get(entry["full_id"], {})
        models.append({
            "id": entry["full_id"],
            "label": parsed.get("label") or config_name_map.get(entry["full_id"]) or entry["model_id"],
            "provider": entry["provider"],
            "reasoning": parsed.get("reasoning", False),
            "attachments": parsed.get("attachments", False),
            "variants": parsed.get("variants", []),
        })
elif enabled_models:
    for entry in enabled_models:
        parsed = parsed_models.get(entry["full_id"], {})
        models.append({
            "id": entry["full_id"],
            "label": parsed.get("label") or entry["label"],
            "provider": entry["provider"],
            "reasoning": parsed.get("reasoning", False),
            "attachments": parsed.get("attachments", False),
            "variants": parsed.get("variants", []),
        })
else:
    def sort_key(item):
        provider = item.get("provider", "")
        try:
            provider_index = provider_order.index(provider)
        except ValueError:
            provider_index = 999999
        return (provider_index, provider, item.get("label", ""))

    models = sorted(parsed_models.values(), key=sort_key)

if not models:
    models = [{
        "id": "opencode/gpt-5-nano",
        "label": "GPT-5 Nano",
        "provider": "opencode",
        "reasoning": True,
        "attachments": True,
        "variants": ["minimal", "low", "medium", "high"],
    }]

print(json.dumps({"ok": True, "models": models}, ensure_ascii=False))
PY
}

export_session() {
    local session_id db_path

    session_id="${1:-}"
    if [[ -z "$session_id" ]]; then
        json_error "Missing session id"
        return
    fi

    log_bridge "export-session session_id=${session_id}"
    db_path="$OPENCODE_DB"
    if [[ ! -f "$db_path" ]]; then
        json_error "Opencode database not found"
        return
    fi

    python - "$db_path" "$session_id" <<'PY'
import json, os, sqlite3, sys
from collections import defaultdict

db_path, session_id = sys.argv[1], sys.argv[2]
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row

session = conn.execute(
    """
    select id, title, directory, time_updated
    from session
    where id = ?
    limit 1
    """,
    (session_id,),
).fetchone()

if session is None:
    print(json.dumps({"ok": False, "error": "Session not found"}, ensure_ascii=False))
    raise SystemExit(0)

message_rows = conn.execute(
    """
    select id, time_created, data
    from message
    where session_id = ?
    order by time_created asc, id asc
    """,
    (session_id,),
).fetchall()

part_rows = conn.execute(
    """
    select id, message_id, time_created, data
    from part
    where session_id = ?
    order by time_created asc, id asc
    """,
    (session_id,),
).fetchall()

parts_by_message = defaultdict(list)
for row in part_rows:
    try:
        part = json.loads(row["data"])
    except Exception:
        continue
    parts_by_message[row["message_id"]].append(part)

def build_tool(part):
    state = part.get("state") or {}
    state_input = state.get("input") or {}
    state_output = state.get("output")
    metadata = state.get("metadata") or {}
    return {
        "tool": part.get("tool", ""),
        "title": state.get("title") or state_input.get("description") or part.get("tool") or "Tool",
        "command": state_input.get("command", ""),
        "description": state_input.get("description", ""),
        "output": state_output or metadata.get("output", ""),
        "status": state.get("status", ""),
        "exitCode": metadata.get("exit"),
    }

messages = []
for row in message_rows:
    try:
        meta = json.loads(row["data"])
    except Exception:
        meta = {}

    role = meta.get("role", "assistant")
    parts = parts_by_message.get(row["id"], [])
    text_parts = [p.get("text", "") for p in parts if p.get("type") == "text" and not p.get("synthetic")]
    synthetic_text_parts = [p.get("text", "") for p in parts if p.get("type") == "text" and p.get("synthetic")]
    reasoning_parts = [p.get("text", "") for p in parts if p.get("type") == "reasoning" and p.get("text")]
    file_parts = [p for p in parts if p.get("type") == "file"]
    tool_parts = [build_tool(p) for p in parts if p.get("type") == "tool"]

    text = "\n\n".join([t for t in text_parts if t])
    if role == "user" and not text and synthetic_text_parts:
        text = synthetic_text_parts[-1]

    attachments = []
    for part in file_parts:
        filename = part.get("filename") or os.path.basename(part.get("filePath", "") or "") or "Attachment"
        attachments.append(filename)

    message = {
        "role": role,
        "text": text,
        "reasoningText": "\n\n".join(reasoning_parts),
        "tools": tool_parts,
        "attachments": attachments,
        "error": (((meta.get("error") or {}).get("data") or {}).get("message")) or "",
        "created": ((meta.get("time") or {}).get("created")) or row["time_created"] or 0,
        "model": ((meta.get("model") or {}).get("modelID")) or meta.get("modelID") or "",
        "provider": ((meta.get("model") or {}).get("providerID")) or meta.get("providerID") or "",
    }

    if message["role"] == "assistant" and not message["text"] and message["error"]:
        message["text"] = message["error"]

    if message["role"] != "assistant" or message["text"] or message["reasoningText"] or message["tools"] or message["error"]:
        messages.append(message)

print(json.dumps({
    "ok": True,
    "session": {
        "id": session["id"],
        "title": session["title"] or session["id"],
        "updated": session["time_updated"] or 0,
        "directory": session["directory"] or "",
    },
    "messages": messages,
}, ensure_ascii=False))
PY
}

run_message() {
    local session_id="" model_id="" agent_name="" variant_name="" work_dir="" message=""
    local thinking_enabled=0
    local -a args
    local stream_fifo=""
    local child_pid=""

    args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --session)
                session_id="${2:-}"
                shift 2
                ;;
            --model)
                model_id="${2:-}"
                shift 2
                ;;
            --dir)
                work_dir="${2:-}"
                shift 2
                ;;
            --agent)
                agent_name="${2:-}"
                shift 2
                ;;
            --variant)
                variant_name="${2:-}"
                shift 2
                ;;
            --thinking)
                thinking_enabled=1
                shift
                ;;
            --message)
                message="${2:-}"
                shift 2
                ;;
            --file)
                args+=("--file" "${2:-}")
                shift 2
                ;;
            *)
                json_error "Unknown argument: $1"
                return
                ;;
        esac
    done

    if [[ -z "$message" ]]; then
        json_error "Missing message"
        return
    fi

    local -a cli_args file_args

    cli_args=(run --format json)
    file_args=()

    if [[ -n "$work_dir" ]]; then
        cli_args+=(--dir "$work_dir")
    fi
    if [[ -n "$session_id" ]]; then
        cli_args+=(--session "$session_id")
    fi
    if [[ -n "$model_id" ]]; then
        cli_args+=(--model "$model_id")
    fi
    if [[ -n "$agent_name" ]]; then
        cli_args+=(--agent "$agent_name")
    fi
    if [[ -n "$variant_name" ]]; then
        cli_args+=(--variant "$variant_name")
    fi
    if [[ "$thinking_enabled" -eq 1 ]]; then
        cli_args+=(--thinking)
    fi

    if [[ "${#args[@]}" -gt 0 ]]; then
        file_args=("${args[@]}")
    fi

    cli_args+=("$message" "${file_args[@]}")
    log_bridge "run session_id=${session_id:-new} model=${model_id:-default} variant=${variant_name:-default} agent=${agent_name:-default} dir=${work_dir:-unset}"

    if [[ -f /etc/ssl/certs/ca-certificates.crt ]]; then
        export NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS:-/etc/ssl/certs/ca-certificates.crt}"
        export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
    fi

    stream_fifo="$(mktemp -u)"
    mkfifo "$stream_fifo"

    cleanup() {
        if [[ -n "$child_pid" ]]; then
            kill -TERM "$child_pid" 2>/dev/null || true
            wait "$child_pid" 2>/dev/null || true
        fi
        [[ -n "$stream_fifo" ]] && rm -f "$stream_fifo"
    }

    trap 'cleanup; exit 130' INT TERM

    opencode "${cli_args[@]}" > "$stream_fifo" 2>&1 &
    child_pid="$!"

    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s\n' "$line"
        printf '%s\n' "$line" >> "$LOG_FILE"
    done < "$stream_fifo"

    wait "$child_pid" 2>/dev/null || true
    cleanup
}

case "${1:-}" in
    list-sessions)
        shift
        list_sessions "$@"
        ;;
    list-models)
        shift
        list_models "$@"
        ;;
    export-session)
        shift
        export_session "$@"
        ;;
    run)
        shift
        run_message "$@"
        ;;
    *)
        json_error "Unknown command"
        ;;
esac
