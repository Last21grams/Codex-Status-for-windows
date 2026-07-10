import json
import os
import re
import sqlite3
import sys


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


def main() -> None:
    db_path = os.path.expanduser(r"~/.codex/logs_2.sqlite").replace("\\", "/")
    connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=0.25)
    query = """
        SELECT feedback_log_body, ts
        FROM logs
        WHERE thread_id = ?
          AND target = 'codex_core::stream_events_utils'
          AND feedback_log_body LIKE ?
          AND feedback_log_body LIKE '%content: [OutputText%'
          AND feedback_log_body LIKE '%phase: Some(FinalAnswer)%'
        ORDER BY ts DESC, ts_nanos DESC, id DESC
        LIMIT 1
    """

    for line in sys.stdin:
        try:
            request = json.loads(line)
            results = {}
            for item in request.get("turns", []):
                thread_id = str(item.get("threadId") or "")
                turn_id = str(item.get("turnId") or "")
                if not thread_id or not turn_id:
                    continue
                pattern = "%turn.id=" + turn_id + "%"
                row = connection.execute(query, (thread_id, pattern)).fetchone()
                if row:
                    results[turn_id] = {
                        "completed": True,
                        "finalText": extract_final_text(row[0] or ""),
                        "timestamp": int(row[1]),
                    }
            print(json.dumps({"results": results}, ensure_ascii=False), flush=True)
        except Exception as exc:
            print(json.dumps({"error": type(exc).__name__, "results": {}}), flush=True)


if __name__ == "__main__":
    main()
