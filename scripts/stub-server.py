#!/usr/bin/env python3
"""Gemini 없이 E2E를 돌리는 /v1/analyze 스텁 (stdlib only).
Tests/Fixtures/analyze-response.json을 돌려주되 video_id·duration은 요청값을 반영하고,
타임스탬프를 duration 안으로 클램프해 실영상 캡처 E2E에도 쓸 수 있게 한다.
사용: python3 scripts/stub-server.py [포트=8787]
"""
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = json.loads(
    (ROOT / "Tests" / "Fixtures" / "analyze-response.json").read_text(encoding="utf-8"))
VIDEO_ID = re.compile(r"(?:v=|youtu\.be/|shorts/)([\w-]{11})")


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/v1/analyze":
            return self._send(404, {"detail": "not found"})
        if not self.headers.get("X-Gemini-Key"):
            return self._send(401, {"detail": "X-Gemini-Key 헤더가 필요합니다."})
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        match = VIDEO_ID.search(body.get("url", ""))
        duration = body.get("duration")
        if not match or not duration:
            return self._send(422, {"detail": "url 또는 duration 확인"})
        reply = json.loads(json.dumps(FIXTURE, ensure_ascii=False))
        reply["video_id"] = match.group(1)
        analysis = reply["analysis"]
        analysis["_duration"] = duration
        for step in analysis["steps"]:
            step["t_start"] = min(step["t_start"], max(0, duration - 10))
            step["t_end"] = min(step["t_end"], max(1, duration - 2))
        for guide in analysis["visual_guides"]:
            if guide["best_visual_timestamp"] is not None:
                guide["best_visual_timestamp"] = min(
                    guide["best_visual_timestamp"], max(1, duration - 5))
        self._send(200, reply)

    def do_GET(self):
        if self.path == "/healthz":
            self._send(200, {"status": "stub"})
        else:
            self._send(404, {"detail": "not found"})

    def _send(self, code, obj):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        print("[stub]", fmt % args)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
    print(f"stub stepkeeper-server on http://127.0.0.1:{port}")
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
