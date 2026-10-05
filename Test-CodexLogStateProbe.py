import json
import os
import sqlite3
import tempfile
import unittest
import sys

sys.dont_write_bytecode = True
from CodexLogStateProbe import find_completion, read_session, tail_lines


class LogProbeTests(unittest.TestCase):
    def test_large_utf8_tool_output_preserves_completion(self):
        events = [
            {"timestamp": "2026-10-05T07:00:00Z", "type": "turn_context", "payload": {"turn_id": "turn", "collaboration_mode": {"mode": "default"}}},
            {"timestamp": "2026-10-05T07:00:01Z", "type": "response_item", "payload": {"type": "function_call_output", "call_id": "tool", "output": "\u6c49" * 500000}},
            {"timestamp": "2026-10-05T07:00:02Z", "type": "response_item", "payload": {"type": "message", "role": "assistant", "phase": "final_answer", "content": [{"text": "\u8bf7\u786e\u8ba4"}]}},
            {"timestamp": "2026-10-05T07:00:03Z", "type": "event_msg", "payload": {"type": "task_complete", "turn_id": "turn"}},
        ]
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", suffix=".tmp", dir=os.path.dirname(os.path.abspath(__file__)), delete=False) as stream:
            path = stream.name
            for event in events:
                stream.write(json.dumps(event, ensure_ascii=False) + "\n")
        try:
            self.assertEqual(len(tail_lines(path, 2)), 2)
            session = read_session(path)
        finally:
            os.unlink(path)
        self.assertEqual(session["settings"][0]["payload"]["turn_id"], "turn")
        self.assertEqual(session["events"][1]["payload"], {"type": "function_call_output", "call_id": "tool"})
        self.assertEqual(session["events"][2]["payload"]["content"][0]["text"], "\u8bf7\u786e\u8ba4")
        self.assertEqual(session["events"][-1]["payload"]["type"], "task_complete")
        self.assertLess(len(json.dumps(session)), 2000)

    def test_message_without_final_phase_is_not_completion(self):
        connection = sqlite3.connect(":memory:")
        self.addCleanup(connection.close)
        connection.execute("CREATE TABLE logs (id INTEGER, thread_id TEXT, target TEXT, feedback_log_body TEXT, ts INTEGER, ts_nanos INTEGER)")
        connection.execute("INSERT INTO logs VALUES (1, 'thread', 'codex_core::stream_events_utils', 'turn.id=turn Output item item_type=\"message\"', 100, 0)")
        self.assertIsNone(find_completion(connection, "thread", "turn"))
        body = 'turn.id=turn handle_output_item_done: Output item item=Message { content: [OutputText { text: "Done." }], phase: Some(FinalAnswer) }'
        connection.execute("INSERT INTO logs VALUES (2, 'thread', 'codex_core::stream_events_utils', ?, 101, 0)", (body,))
        completion = find_completion(connection, "thread", "turn")
        self.assertEqual(completion["finalText"], "Done.")


if __name__ == "__main__":
    unittest.main()
