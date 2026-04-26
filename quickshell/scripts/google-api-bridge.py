#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
import sys
import time
import uuid
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from google import genai
from google.genai import types


HOME = Path.home()
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local" / "state")) / "caelestia"
CHAT_STORE_PATH = Path(os.environ.get("CAELESTIA_API_CHAT_STORE", STATE_DIR / "google-api-chats.json"))
CONFIG_PATH = Path(os.environ.get("CAELESTIA_API_CONFIG_PATH", HOME / ".config" / "caelestia-ai" / "api-config.json"))
DEFAULT_ENV_FILE = Path(os.environ.get("CAELESTIA_API_ENV_FILE", HOME / ".config" / "caelestia-ai" / ".env"))


def emit(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def emit_text_segments(session_id: str, text: str) -> None:
    value = text or ""
    if not value:
        return
    chunks = re.findall(r".{1,4}", value, flags=re.S)
    if not chunks:
        chunks = [value]
    for chunk in chunks:
        emit(
            {
                "type": "text",
                "timestamp": int(time.time() * 1000),
                "sessionID": session_id,
                "part": {
                    "id": f"text_{uuid.uuid4().hex[:10]}",
                    "sessionID": session_id,
                    "type": "text",
                    "text": chunk,
                },
            }
        )
        time.sleep(0.012)


def chunk_parts_to_texts(chunk: Any) -> tuple[str, str]:
    answer_parts: list[str] = []
    reasoning_parts: list[str] = []
    candidates = getattr(chunk, "candidates", None) or []
    for candidate in candidates:
        content = getattr(candidate, "content", None)
        parts = getattr(content, "parts", None) or []
        for part in parts:
            text = getattr(part, "text", None) or ""
            if not text:
                continue
            if getattr(part, "thought", False):
                reasoning_parts.append(text)
            else:
                answer_parts.append(text)
    if not answer_parts and not reasoning_parts:
        direct_text = getattr(chunk, "text", None) or ""
        if direct_text:
            answer_parts.append(direct_text)
    return ("".join(answer_parts), "".join(reasoning_parts))


def stream_delta(current: str, seen: str) -> tuple[str, str]:
    if not current:
        return "", seen
    if current.startswith(seen):
        delta = current[len(seen) :]
        return delta, current
    return current, seen + current


def json_error(message: str) -> int:
    emit({"ok": False, "error": message})
    return 1


def read_json(path: Path, fallback: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return fallback


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def load_config() -> dict[str, Any]:
    config = read_json(CONFIG_PATH, {})
    env_file = Path(config.get("env_file") or DEFAULT_ENV_FILE).expanduser()
    if env_file.exists():
        load_dotenv(env_file, override=False)
    api_key_env = config.get("api_key_env") or "GOOGLE_API_KEY"
    api_key = os.environ.get(api_key_env, "").strip()
    return {
        "env_file": str(env_file),
        "api_key_env": api_key_env,
        "api_key": api_key,
        "models": config.get("models") or [],
    }


def build_client(config: dict[str, Any]) -> genai.Client:
    api_key = (config.get("api_key") or "").strip()
    if not api_key:
        raise RuntimeError(f"Missing API key in env var {config.get('api_key_env') or 'GOOGLE_API_KEY'}")
    return genai.Client(api_key=api_key)


def load_store() -> dict[str, Any]:
    store = read_json(CHAT_STORE_PATH, {"sessions": []})
    if not isinstance(store, dict):
        return {"sessions": []}
    sessions = store.get("sessions")
    if not isinstance(sessions, list):
        sessions = []
    return {"sessions": sessions}


def save_store(store: dict[str, Any]) -> None:
    ensure_parent(CHAT_STORE_PATH)
    CHAT_STORE_PATH.write_text(json.dumps(store, ensure_ascii=False, indent=2), encoding="utf-8")


def sanitize_title(text: str) -> str:
    value = (text or "").replace("\r\n", "\n")
    while "[[" in value and "]]" in value:
        start = value.find("[[")
        end = value.find("]]", start)
        if end == -1:
            break
        value = (value[:start] + value[end + 2 :]).strip()
    value = value.replace("\n", " ").strip()
    if not value:
        return "New API chat"
    return value[:80]


def model_map(config: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {
        item["id"]: item
        for item in (config.get("models") or [])
        if isinstance(item, dict) and item.get("enabled", True) and item.get("id")
    }


def visible_model_list(config: dict[str, Any]) -> list[dict[str, Any]]:
    models: list[dict[str, Any]] = []
    for item in config.get("models") or []:
        if not isinstance(item, dict) or not item.get("enabled", True):
            continue
        models.append(
            {
                "id": item["id"],
                "label": item.get("label") or item["id"],
                "provider": item.get("provider") or "api",
                "reasoning": bool(item.get("reasoning", False)),
                "attachments": bool(item.get("attachments", True)),
                "variants": item.get("variants") or [],
                "sdkModel": item.get("sdk_model") or item["id"].split("/", 1)[-1],
            }
        )
    return models


def list_models() -> int:
    config = load_config()
    emit({"ok": True, "models": visible_model_list(config)})
    return 0


def list_sessions() -> int:
    store = load_store()
    sessions = sorted(store["sessions"], key=lambda item: item.get("updated", 0), reverse=True)
    emit(
        {
            "ok": True,
            "sessions": [
                {
                    "id": session.get("id", ""),
                    "title": session.get("title") or "New API chat",
                    "updated": session.get("updated", 0),
                    "directory": session.get("directory") or "",
                }
                for session in sessions
            ],
        }
    )
    return 0


def export_session(session_id: str) -> int:
    store = load_store()
    session = next((item for item in store["sessions"] if item.get("id") == session_id), None)
    if session is None:
        return json_error("Session not found")
    emit(
        {
            "ok": True,
            "session": {
                "id": session.get("id", ""),
                "title": session.get("title") or "New API chat",
                "updated": session.get("updated", 0),
                "directory": session.get("directory") or "",
            },
            "messages": session.get("messages") or [],
        }
    )
    return 0


def make_text_message(role: str, text: str, created: int, attachments: list[str] | None = None) -> dict[str, Any]:
    return {
        "role": role,
        "text": text,
        "reasoningText": "",
        "tools": [],
        "attachments": attachments or [],
        "error": "",
        "created": created,
    }


def ensure_session(store: dict[str, Any], session_id: str | None, model_id: str) -> dict[str, Any]:
    now = int(time.time() * 1000)
    if session_id:
        session = next((item for item in store["sessions"] if item.get("id") == session_id), None)
        if session:
            session["model_id"] = model_id
            return session

    session = {
        "id": session_id or f"api_{uuid.uuid4().hex[:12]}",
        "title": "New API chat",
        "directory": "",
        "created": now,
        "updated": now,
        "model_id": model_id,
        "messages": [],
    }
    store["sessions"].insert(0, session)
    return session


def file_part(path_str: str) -> types.Part:
    path = Path(path_str)
    mime_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    data = path.read_bytes()
    return types.Part.from_bytes(data=data, mime_type=mime_type)


def session_to_contents(messages: list[dict[str, Any]]) -> list[types.Content]:
    contents: list[types.Content] = []
    for message in messages:
        role = (message.get("role") or "").strip()
        if role not in {"user", "assistant"}:
            continue
        text = (message.get("text") or "").strip()
        attachments = message.get("attachments") or []
        parts: list[Any] = []
        if role == "user":
            for attachment in attachments:
                file_path = Path(attachment)
                if file_path.exists():
                    try:
                        parts.append(file_part(str(file_path)))
                    except Exception:
                        pass
        if text:
            parts.append(types.Part.from_text(text=text))
        if not parts:
            continue
        contents.append(types.Content(role="model" if role == "assistant" else "user", parts=parts))
    return contents


def run_message(args: argparse.Namespace) -> int:
    config = load_config()
    models = model_map(config)
    selected = models.get(args.model)
    if not selected:
        return json_error(f"Unknown API model: {args.model}")

    store = load_store()
    session = ensure_session(store, args.session, args.model)
    session_id = session["id"]
    sdk_model = selected.get("sdk_model") or args.model.split("/", 1)[-1]
    attachments = args.files or []
    visible_attachments = [str(Path(path)) for path in attachments]
    created = int(time.time() * 1000)

    user_message = make_text_message("user", args.message, created, visible_attachments)
    session_messages = list(session.get("messages") or [])
    session_messages.append(user_message)
    session["messages"] = session_messages
    session["updated"] = created
    if not session.get("title") or session.get("title") == "New API chat":
        session["title"] = sanitize_title(args.message)
    save_store(store)

    emit(
        {
            "type": "step_start",
            "timestamp": created,
            "sessionID": session_id,
            "part": {"id": f"start_{session_id}", "sessionID": session_id, "type": "step-start"},
        }
    )

    try:
        client = build_client(config)
        contents = session_to_contents(session_messages)
        response_text_parts: list[str] = []
        reasoning_text_parts: list[str] = []
        stream_failed = False
        answer_seen = ""
        reasoning_seen = ""
        stream_config = None
        if args.thinking and bool(selected.get("reasoning", False)):
            stream_config = types.GenerateContentConfig(
                thinking_config=types.ThinkingConfig(
                    include_thoughts=True
                )
            )

        try:
            for chunk in client.models.generate_content_stream(model=sdk_model, contents=contents, config=stream_config):
                answer_text, reasoning_text = chunk_parts_to_texts(chunk)
                answer_delta, answer_seen = stream_delta(answer_text, answer_seen)
                reasoning_delta, reasoning_seen = stream_delta(reasoning_text, reasoning_seen)
                if reasoning_delta:
                    reasoning_text_parts.append(reasoning_delta)
                    emit(
                        {
                            "type": "reasoning",
                            "timestamp": int(time.time() * 1000),
                            "sessionID": session_id,
                            "part": {
                                "id": f"reasoning_{uuid.uuid4().hex[:10]}",
                                "sessionID": session_id,
                                "type": "reasoning",
                                "text": reasoning_delta,
                            },
                        }
                    )
                if answer_delta:
                    response_text_parts.append(answer_delta)
                    emit_text_segments(session_id, answer_delta)
        except Exception:
            stream_failed = True

        if stream_failed and not response_text_parts:
            response = client.models.generate_content(model=sdk_model, contents=contents, config=stream_config)
            if getattr(response, "text", None):
                response_text_parts.append(response.text)
                emit_text_segments(session_id, response.text)
            candidates = getattr(response, "candidates", None) or []
            for candidate in candidates:
                content = getattr(candidate, "content", None)
                parts = getattr(content, "parts", None) or []
                for part in parts:
                    text = getattr(part, "text", None) or ""
                    if text and getattr(part, "thought", False):
                        reasoning_text_parts.append(text)

        final_text = "".join(response_text_parts).strip()
        final_reasoning = "".join(reasoning_text_parts).strip()
        finished = int(time.time() * 1000)
        assistant_message = make_text_message("assistant", final_text, finished)
        assistant_message["provider"] = "api"
        assistant_message["model"] = sdk_model
        assistant_message["reasoningText"] = final_reasoning
        session["messages"] = list(session.get("messages") or []) + [assistant_message]
        session["updated"] = finished
        session["model_id"] = args.model
        save_store(store)

        emit(
            {
                "type": "step_finish",
                "timestamp": finished,
                "sessionID": session_id,
                "part": {
                    "id": f"finish_{session_id}",
                    "sessionID": session_id,
                    "type": "step-finish",
                    "reason": "stop",
                },
            }
        )
        return 0
    except Exception as exc:
        finished = int(time.time() * 1000)
        error_message = str(exc)
        emit(
            {
                "type": "error",
                "timestamp": finished,
                "sessionID": session_id,
                "error": {"message": error_message},
            }
        )
        emit(
            {
                "type": "step_finish",
                "timestamp": finished,
                "sessionID": session_id,
                "part": {
                    "id": f"finish_{session_id}",
                    "sessionID": session_id,
                    "type": "step-finish",
                    "reason": "error",
                },
            }
        )
        return 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("list-models")
    subparsers.add_parser("list-sessions")

    export = subparsers.add_parser("export-session")
    export.add_argument("session_id")

    run = subparsers.add_parser("run")
    run.add_argument("--session", default="")
    run.add_argument("--model", required=True)
    run.add_argument("--message", required=True)
    run.add_argument("--file", dest="files", action="append", default=[])
    run.add_argument("--dir", default="")
    run.add_argument("--agent", default="")
    run.add_argument("--variant", default="")
    run.add_argument("--thinking", action="store_true")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.command == "list-models":
        return list_models()
    if args.command == "list-sessions":
        return list_sessions()
    if args.command == "export-session":
        return export_session(args.session_id)
    if args.command == "run":
        return run_message(args)
    return json_error("Unknown command")


if __name__ == "__main__":
    raise SystemExit(main())
