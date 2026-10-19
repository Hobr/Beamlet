#!/usr/bin/env python3
"""执行器本地、确定性的 HTTP 夹具：仿 OpenAI 兼容端点，绝不访问真实提供方。

它先要求一次 workspace_read(marker.txt) Tool 调用，收到 Tool 观察后再输出完整
Tool 内容的 SHA256，便于调用方比对“确实读到了标记”。
Opt-in executor-local deterministic HTTP fixture; never contacts a provider.
"""
import argparse
import hashlib
import json
import socket
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def handle(self):
        # Cover headers as well as body IO, including clients sending slow bytes.
        timer = threading.Timer(10, self.expire)
        timer.start()
        try:
            super().handle()
        except OSError:
            pass  # Deadline/disconnected clients end this fixture request.
        finally:
            timer.cancel()
            timer.join()

    def expire(self):
        try:
            self.connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass

    def log_message(self, format, *args):
        pass  # Do not log headers, bearer keys or prompts.

    def do_POST(self):
        self.connection.settimeout(5)
        try:
            size = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_error(400)
            return
        if self.path != "/v1/chat/completions" or not 0 < size <= 1_048_576:
            self.send_error(400)
            return
        try:
            request = json.loads(self.rfile.read(size))
            tools = [m for m in request["messages"] if m.get("role") == "tool"]
            if tools:
                content = tools[-1]["content"]
                print("tool observation sha256=" + hashlib.sha256(content.encode()).hexdigest(), flush=True)
                message = {"role": "assistant", "content": "fixture completed; inspect observation digest"}
                finish = "stop"
            else:
                message = {"role": "assistant", "content": None, "tool_calls": [{
                    "id": "physical-marker", "type": "function", "function": {
                        "name": "workspace_read", "arguments": json.dumps({"path": "marker.txt"})}}]}
                finish = "tool_calls"
            body = json.dumps({"choices": [{"finish_reason": finish, "message": message}]}).encode()
        except (ValueError, KeyError, TypeError):
            self.send_error(400)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--requests", type=int, default=16)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535 or not 1 <= args.requests <= 64:
        parser.error("port 1024..65535 and requests 1..64 required")
    with HTTPServer(("127.0.0.1", args.port), Handler) as server:
        server.timeout = 30
        for _ in range(args.requests):
            server.handle_request()


if __name__ == "__main__":
    main()
