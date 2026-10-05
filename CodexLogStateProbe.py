import json
import os
import re
import sqlite3
import sys


def tail_lines(path, count=600):
    # Read backwards in blocks. Windows PowerShell's UTF-8 Get-Content -Tail
    # can spend minutes traversing long image/tool-output lines.
    with open(path, "rb") as stream:
        position = stream.seek(0, os.SEEK_END)
        chunks = []
        newlines = 0
        while position and newlines <= count:
            size = min(position, 65536)
            position -= size
            stream.seek(position)
            chunk = stream.read(size)
            chunks.append(chunk)
            newlines += chunk.count(b"\n")
        return b"".join(reversed(chunks)).splitlines()[-count:]


def compact_event(item):
    outer = item.get("type")
    payload = item.get("payload") or {}
    if not isinstance(payload, dict):
        return None
    keys = ("type", "turn_id", "internal_chat_message_metadata_passthrough")
    compact = {key: payload[key] for key in keys if key in payload}
    if outer == "turn_context":
        compact["collaboration_mode"] = payload.get("collaboration_mode")
    elif outer == "event_msg":
        if payload.get("type") == "thread_settings_applied":
            settings = payload.get("thread_settings") or {}
            compact["thread_settings"] = {"collaboration_mode": settings.get("collaboration_mode")}
        elif payload.get("type") == "token_count":
            compact["rate_limits"] = payload.get("rate_limits")
    elif outer == "response_item":
        kind = payload.get("type")
        if kind == "message":
            compact.update(role=payload.get("role"), phase=payload.get("phase"))
            if payload.get("role") == "assistant" and payload.get("phase") in ("final", "final_answer"):
                compact["content"] = [{"text": part.get("text", "")} for part in payload.get("content", []) if isinstance(part, dict) and "text" in part]
        elif kind in ("custom_tool_call", "function_call"):
            for key in ("name", "call_id", "input", "arguments"):
                compact[key] = payload.get(key)
        elif kind in ("custom_tool_call_output", "function_call_output"):
            compact["call_id"] = payload.get("call_id")
    return {"timestamp": item.get("timestamp"), "type": outer, "payload": compact}


def read_session(path):
    settings = []
    with open(path, "r", encoding="utf-8-sig") as stream:
        for index, line in enumerate(stream):
            if index >= 80:
                break
            try:
                item = json.loads(line)
            except (ValueError, TypeError):
                continue
            if item.get("type") == "turn_context" or (item.get("payload") or {}).get("type") == "thread_settings_applied":
                settings.append(compact_event(item))
    events = []
    for raw in tail_lines(path):
        try:
            event = compact_event(json.loads(raw.decode("utf-8-sig")))
            if event:
                events.append(event)
        except (ValueError, UnicodeError, TypeError):
            continue
    return {"settings": settings, "events": events}


def extract_final_text(body: str) -> str:
    match = re.search(
        r'content: \[OutputText \{ text: "(.*)" \}\], phase: Some\(FinalAnswer\)',
        body,
        re.DOTALL,
    )
    if not match:
        return ""
    raw = match.group(1)
    try:
        return json.loads('"' + raw + '"')
    except Exception:
        return raw.replace(r"\n", "\n").replace(r'\"', '"').replace(r"\\", "\\")


def find_completion(connection: sqlite3.Connection, thread_id: str, turn_id: str):
    turn_pattern = "%turn.id=" + turn_id + "%"
    legacy_query = """
        SELECT feedback_log_body, ts
        FROM logs
        WHERE thread_id = ?
          AND target = 'codex_core::stream_events_utils'
          AND feedback_log_body LIKE ?
          AND feedback_log_body LIKE '%handle_output_item_done: Output item item=Message {%'
          AND feedback_log_body LIKE '%content: [OutputText%'
          AND feedback_log_body LIKE '%phase: Some(FinalAnswer)%'
        ORDER BY ts DESC, ts_nanos DESC, id DESC
        LIMIT 1
    """
    row = connection.execute(legacy_query, (thread_id, turn_pattern)).fetchone()
    if row:
        return {
            "completed": True,
            "finalText": extract_final_text(row[0] or ""),
            "timestamp": int(row[1]),
        }

    # item_type="message" does not identify the phase. Commentary can precede
    # a long reasoning/tool step, so it is not proof that the turn finished.
    return None


def main() -> None:
    db_path = os.path.expanduser(r"~/.codex/logs_2.sqlite").replace("\\", "/")
    connection = None
    for line in sys.stdin:
        try:
            request = json.loads(line)
            if "sessionPaths" in request:
                sessions = {}
                for path in request["sessionPaths"]:
                    try:
                        sessions[path] = read_session(path)
                    except OSError:
                        continue
                print(json.dumps({"sessions": sessions}, ensure_ascii=True), flush=True)
                continue
            if connection is None:
                connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=0.25)
            results = {}
            for item in request.get("turns", []):
                thread_id = str(item.get("threadId") or "")
                turn_id = str(item.get("turnId") or "")
                if not thread_id or not turn_id:
                    continue
                completion = find_completion(connection, thread_id, turn_id)
                if completion:
                    results[turn_id] = completion
            print(json.dumps({"results": results}, ensure_ascii=False), flush=True)
        except Exception as exc:
            print(json.dumps({"error": type(exc).__name__, "results": {}}), flush=True)


if __name__ == "__main__":
    main()
