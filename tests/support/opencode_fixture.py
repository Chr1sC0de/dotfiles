"""Deterministic OpenAI-compatible streaming endpoint for real OpenCode tests."""

import http.server
import json


def handler_for(answer):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            result = answer(body)
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            delta = {"role": "assistant", **result}
            if "tool_calls" in delta:
                delta["tool_calls"] = [dict(index=i, **v) for i, v in enumerate(delta["tool_calls"])]
            for value, reason in [(delta, None), ({}, "tool_calls" if "tool_calls" in delta else "stop")]:
                chunk = {"id": "fixture", "object": "chat.completion.chunk", "created": 1,
                         "model": body["model"], "choices": [{"index": 0, "delta": value, "finish_reason": reason}]}
                self.wfile.write(("data: " + json.dumps(chunk) + "\n\n").encode())
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()

    return Handler


def config(port):
    return {
        "model": "fixture/test",
        "providers": {"fixture": {
            "name": "Local test fixture",
            "package": "@opencode/ai/providers/openai-compatible",
            "settings": {"baseURL": f"http://127.0.0.1:{port}/v1", "apiKey": "fixture"},
            "models": {"test": {"name": "Fixture", "limit": {"context": 128000, "output": 4096}}},
        }},
        "policies": [
            {"action": "provider.use", "resource": "*", "effect": "deny"},
            {"action": "provider.use", "resource": "fixture", "effect": "allow"},
        ],
    }
