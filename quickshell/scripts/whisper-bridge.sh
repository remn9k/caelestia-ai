#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${HOME}/.local/state/caelestia/whisper"
PID_FILE="${STATE_DIR}/recording.pid"
WAV_FILE="${STATE_DIR}/recording.wav"
OUT_PREFIX="${STATE_DIR}/transcript"
LEVEL_FILE="${STATE_DIR}/level.log"
MODEL_PATH="${WHISPER_MODEL_PATH:-${HOME}/opencode/whisper.cpp/models/ggml-base.bin}"
CLI_PATH="${WHISPER_CLI_PATH:-${HOME}/opencode/whisper.cpp/build/bin/whisper-cli}"

mkdir -p "$STATE_DIR"

json_escape() {
    python - "$1" <<'PY'
import json, sys
print(json.dumps(sys.argv[1], ensure_ascii=False))
PY
}

emit_json() {
    local ok="$1"
    local state="$2"
    local text="${3-}"
    local error="${4-}"
    local level="${5-0}"
    printf '{"ok":%s,"state":"%s","text":%s,"error":%s,"level":%s}\n' \
        "$ok" \
        "$state" \
        "$(json_escape "$text")" \
        "$(json_escape "$error")" \
        "$level"
}

cleanup_pid() {
    rm -f "$PID_FILE"
}

read_level() {
    if [[ ! -f "$LEVEL_FILE" ]]; then
        echo "0"
        return 0
    fi

    python - "$LEVEL_FILE" <<'PY'
import math
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(errors="ignore") if path.exists() else ""
matches = re.findall(r'lavfi\.astats\.Overall\.RMS_level=([-\d.]+|inf|-inf)', text)
if not matches:
    print("0")
    raise SystemExit

value = matches[-1]
if value in {"inf", "-inf"}:
    print("0")
    raise SystemExit

db = float(value)
level = max(0.0, min(1.0, (db + 55.0) / 45.0))
print(f"{level:.4f}")
PY
}

record_start() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ -n "${pid}" ]] && kill -0 "$pid" 2>/dev/null; then
            emit_json true "recording" "" "" "$(read_level)"
            return 0
        fi
        cleanup_pid
    fi

    rm -f "$WAV_FILE" "${OUT_PREFIX}.txt" "$LEVEL_FILE"
    nohup ffmpeg -nostdin -loglevel error -y -f pulse -i default \
        -filter_complex "[0:a]asplit=2[record][meter];[meter]astats=metadata=1:reset=1,ametadata=mode=print:file=${LEVEL_FILE}[metered]" \
        -map "[record]" -ac 1 -ar 16000 -c:a pcm_s16le "$WAV_FILE" \
        -map "[metered]" -f null - >/dev/null 2>&1 &
    echo "$!" > "$PID_FILE"
    emit_json true "recording" "" "" "$(read_level)"
}

record_stop() {
    if [[ ! -x "$CLI_PATH" ]]; then
        emit_json false "error" "" "whisper-cli not found at $CLI_PATH" "0"
        return 1
    fi
    if [[ ! -f "$MODEL_PATH" ]]; then
        emit_json false "error" "" "whisper base model not found at $MODEL_PATH" "0"
        return 1
    fi
    if [[ ! -f "$PID_FILE" ]]; then
        emit_json false "idle" "" "No active recording" "0"
        return 1
    fi

    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    cleanup_pid

    if [[ -n "${pid}" ]] && kill -0 "$pid" 2>/dev/null; then
        kill -INT "$pid" 2>/dev/null || true
        for _ in $(seq 1 50); do
            if ! kill -0 "$pid" 2>/dev/null; then
                break
            fi
            sleep 0.1
        done
        kill -TERM "$pid" 2>/dev/null || true
    fi

    if [[ ! -s "$WAV_FILE" ]]; then
        emit_json false "idle" "" "Recorded audio file is empty" "0"
        return 1
    fi

    rm -f "${OUT_PREFIX}.txt"
    "$CLI_PATH" -m "$MODEL_PATH" -f "$WAV_FILE" -l auto -otxt -of "$OUT_PREFIX" -np -nt >/dev/null 2>&1
    local text=""
    if [[ -f "${OUT_PREFIX}.txt" ]]; then
        text="$(tr '\n' ' ' < "${OUT_PREFIX}.txt" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    fi

    if [[ -z "$text" ]]; then
        emit_json true "idle" "" "" "0"
    else
        emit_json true "idle" "$text" "" "0"
    fi
}

status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ -n "${pid}" ]] && kill -0 "$pid" 2>/dev/null; then
            emit_json true "recording" "" "" "$(read_level)"
            return 0
        fi
        cleanup_pid
    fi
    emit_json true "idle" "" "" "0"
}

case "${1-}" in
    start) record_start ;;
    stop) record_stop ;;
    status) status ;;
    *)
        emit_json false "error" "" "Usage: whisper-bridge.sh {start|stop|status}"
        exit 1
        ;;
esac
