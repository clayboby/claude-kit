"""Stub MCP gateway used by the offline test suite. Localhost only.

Started by run-offline-tests.sh; it binds 127.0.0.1 and answers on paths that
exercise every branch of a preflight probe. No real endpoint is ever contacted.

  Port 8792, paths:
  /ok/mcp        -> 200 SSE-framed JSON-RPC result (authenticated)
  /401/mcp       -> 401
  /404/mcp       -> 404
  /garbage/mcp   -> 200 text/html, not JSON-RPC
  /slow/mcp      -> sleeps past the 3s timeout
Health: /ok/healthz etc. all 200.
"""
import http.server, json, threading, time, sys

class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def _send(self, code, body=b"", ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)
    def do_GET(self):
        if self.path.endswith(("/healthz", "/health")):
            self._send(200, b'{"ok":true}')
        else:
            self._send(404, b"nope", "text/plain")
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        self.rfile.read(n)
        kind = self.path.strip("/").split("/")[0]
        if kind == "401":
            self._send(401, b'{"error":"unauthorized"}')
        elif kind == "404":
            self._send(404, b"no such endpoint", "text/plain")
        elif kind == "garbage":
            self._send(200, b"<html><body>hello from a proxy</body></html>", "text/html")
        elif kind == "slow":
            time.sleep(6)
            self._send(200, b'{"jsonrpc":"2.0","id":1,"result":{}}')
        else:
            payload = json.dumps({"jsonrpc": "2.0", "id": 1,
                                  "result": {"resultType": "complete", "serverInfo": {"name": "stub"}}})
            body = ("event: message\ndata: " + payload + "\n\n").encode()
            self._send(200, body, "text/event-stream")
    def log_message(self, *a):
        pass

srv = http.server.ThreadingHTTPServer(("127.0.0.1", 8792), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
time.sleep(float(sys.argv[1]) if len(sys.argv) > 1 else 40)
