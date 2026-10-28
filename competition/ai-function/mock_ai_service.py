#!/usr/bin/env python3
"""Minimal mock AI service for seekdb AI function tests.

Serves the endpoints used by the 2026-competition ai_function suite:
  POST /compatible-mode/v1/chat/completions  (openai style complete)
  POST /compatible-mode/v1/embeddings        (openai style embed)
  POST /v1/rerank                            (siliconflow style rerank)
  POST /api/generate                         (ollama complete)
  POST /api/embed                            (ollama embed)
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DIM = 768


def embedding():
    return [round(0.01 + (i % 7) * 0.001, 6) for i in range(DIM)]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw.decode("utf-8")) if raw else {}
        except Exception:
            return {}

    def _send(self, payload, code=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        path = self.path.split("?")[0]
        body = self._read_body()
        if path.endswith("/chat/completions"):
            self._send({
                "id": "chatcmpl-mock",
                "object": "chat.completion",
                "model": body.get("model", "mock-model"),
                "choices": [{
                    "index": 0,
                    "message": {"role": "assistant", "content": "mock completion result"},
                    "finish_reason": "stop",
                }],
                "usage": {"prompt_tokens": 1, "completion_tokens": 3, "total_tokens": 4},
            })
        elif path.endswith("/embeddings"):
            inputs = body.get("input")
            if isinstance(inputs, str):
                inputs = [inputs]
            if not isinstance(inputs, list):
                inputs = [""]
            data = [{"object": "embedding", "index": i, "embedding": embedding()}
                    for i in range(len(inputs))]
            self._send({
                "object": "list",
                "model": body.get("model", "mock-embed"),
                "data": data,
                "usage": {"prompt_tokens": 1, "total_tokens": 1},
            })
        elif path.endswith("/rerank"):
            docs = body.get("documents") or []
            results = [{"index": i, "relevance_score": round(1.0 - i * 0.1, 4)}
                       for i in range(len(docs))]
            self._send({
                "id": "rerank-mock",
                "results": results,
                "meta": {"tokens": {"input_tokens": 1, "output_tokens": 1}},
            })
        elif path.endswith("/api/generate"):
            self._send({
                "model": body.get("model", "mock-ollama"),
                "created_at": "2026-10-29T00:00:00Z",
                "response": "mock ollama completion",
                "done": True,
                "done_reason": "stop",
            })
        elif path.endswith("/api/embed"):
            inputs = body.get("input")
            if isinstance(inputs, str):
                inputs = [inputs]
            if not isinstance(inputs, list):
                inputs = [""]
            self._send({
                "model": body.get("model", "mock-ollama-embed"),
                "embeddings": [embedding() for _ in inputs],
            })
        else:
            self._send({"error": "unknown path: %s" % path}, 404)

    def do_GET(self):
        self._send({"status": "ok"})


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
