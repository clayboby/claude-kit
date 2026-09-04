#!/usr/bin/env bash
# SessionStart hook for vagaa-web-evidence.
#
# Two probes, 3s each, both unauthenticated-safe to fail:
#   1. the gateway's health path, derived from the configured MCP URL;
#   2. one authenticated MCP `server/discover` call, which lists nothing and
#      runs no job, purely to tell "wrong token" from "wrong URL" from "down".
#
# Anything on stdout becomes session context, so this prints at most one line
# per problem and never prints a URL, a token, or a response body. It writes no
# files, always exits 0, and never blocks a session.
#
# Dependencies: bash, curl, python3.
set -euo pipefail

TIMEOUT_S=3
LABEL="web-evidence router"
URL="${CLAUDE_PLUGIN_OPTION_NOLE_MCP_URL:-}"
PROFILE="${CLAUDE_PLUGIN_OPTION_PROFILE:-}"

say() { printf '[vagaa-web-evidence] %s\n' "$1"; }

if [ -z "$URL" ]; then
  say "${LABEL}: not configured — run /plugin, open vagaa-web-evidence and fill in its options."
  exit 0
fi
case "$URL" in
  http://*|https://*) ;;
  *)
    say "${LABEL}: the configured URL is not http(s) — run /plugin and fix nole_mcp_url."
    exit 0
    ;;
esac

base="${URL%/}"
base="${base%/mcp-compact}"
base="${base%/mcp}"

# --- 1. health -------------------------------------------------------------
http_code() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' \
    --max-time "$TIMEOUT_S" --connect-timeout "$TIMEOUT_S" \
    -H 'Accept: application/json' "$1" 2>/dev/null)" || true
  case "$code" in
    [0-9][0-9][0-9]) ;;
    *) code="000" ;;
  esac
  printf '%s' "$code"
}

health="$(http_code "${base}/health")"
if [ "$health" = "404" ]; then
  health="$(http_code "${base}/healthz")"
fi
case "$health" in
  2*) ;;
  000)
    say "${LABEL}: unreachable (no answer in ${TIMEOUT_S}s) — its tools will fail this session; check the network, the VPN or the service."
    exit 0
    ;;
  *)
    say "${LABEL}: health check answered HTTP ${health} — its tools may fail this session."
    ;;
esac

# --- 2. authenticated server/discover --------------------------------------
# The token goes to curl through a config file on stdin, never in argv, so it
# does not show up in `ps`. printf is a bash builtin, so the value is not in an
# argv of its own either. Nothing is written to disk.
probe_body='{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'
token="${CLAUDE_PLUGIN_OPTION_NOLE_CREDENTIAL:-}"
esc_url="${URL//\\/\\\\}"; esc_url="${esc_url//\"/\\\"}"
esc_token="${token//\\/\\\\}"; esc_token="${esc_token//\"/\\\"}"
esc_body="${probe_body//\\/\\\\}"; esc_body="${esc_body//\"/\\\"}"

discover="$(
  printf 'url = "%s"\nrequest = "POST"\nheader = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\nheader = "Accept: application/json, text/event-stream"\nheader = "MCP-Protocol-Version: 2026-07-28"\nheader = "Mcp-Method: server/discover"\ndata = "%s"\nmax-time = %s\nconnect-timeout = %s\nsilent\nwrite-out = "\\n%%{http_code}"\n' \
    "$esc_url" "$esc_token" "$esc_body" "$TIMEOUT_S" "$TIMEOUT_S" \
  | curl --config - 2>/dev/null
)" || true
unset token esc_token

# The classifier needs no credential: drop every one the harness injected
# before starting python3, so nothing can leak through the child's environment.
while IFS='=' read -r _name _rest; do
  case "$_name" in
    CLAUDE_PLUGIN_OPTION_*TOKEN*|CLAUDE_PLUGIN_OPTION_*CREDENTIAL*|CLAUDE_PLUGIN_OPTION_*SECRET*|CLAUDE_PLUGIN_OPTION_*KEY*|CLAUDE_PLUGIN_OPTION_*PASSWORD*)
      unset "$_name" || true
      ;;
  esac
done < <(env | grep '^CLAUDE_PLUGIN_OPTION_' || true)
unset _name _rest

# Classify without echoing anything from the response.
verdict="$(
  python3 -c '
import json
import sys

raw = sys.stdin.read().rstrip("\r\n")
idx = raw.rfind("\n")
body, code = (raw[:idx], raw[idx + 1:].strip()) if idx >= 0 else ("", raw.strip())
if not code.isdigit():
    code = "000"

def json_rpc(text):
    """True when the body is a JSON-RPC 2.0 envelope, SSE-framed or not."""
    candidates = [text.strip()]
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("data:"):
            candidates.append(line[5:].strip())
    for candidate in candidates:
        if not candidate:
            continue
        try:
            doc = json.loads(candidate)
        except ValueError:
            continue
        if isinstance(doc, dict) and doc.get("jsonrpc") == "2.0":
            return True
    return False

if code == "000":
    print("unreachable")
elif code in ("401", "403"):
    print("unauthorized")
elif code == "404":
    print("notfound")
elif json_rpc(body):
    print("ok")
else:
    print("protocol")
' <<<"$discover"
)" || verdict="protocol"
unset discover

case "$verdict" in
  ok) ;;
  unreachable)
    say "${LABEL}: the MCP endpoint did not answer in ${TIMEOUT_S}s even though its health path did — the service may be starting or a proxy is in the way."
    ;;
  unauthorized)
    say "${LABEL}: rejected the configured credential (HTTP 401/403). 直连填服务令牌,公网填网关密钥,不可互换 — with profile=lan nole_credential must be the router service token, with profile=public the gateway API key; run /plugin and update it."
    ;;
  notfound)
    say "${LABEL}: no MCP endpoint at the configured URL (HTTP 404) — check that nole_mcp_url ends in /mcp-compact (one tool) or /mcp (six tools)."
    ;;
  *)
    say "${LABEL}: answered, but not with MCP JSON-RPC — nole_mcp_url probably points at the REST API, a proxy or the wrong path."
    ;;
esac

# --- 3. profile sanity note ------------------------------------------------
if [ "$verdict" = "ok" ]; then
  case "$PROFILE" in
    lan|public) ;;
    "")
      say "note: profile is not set. Set it to lan (direct address, router service token) or public (gateway address, gateway API key) so this check can name the right credential."
      ;;
    *)
      say "note: profile is neither lan nor public — set one of those two values."
      ;;
  esac
  case "$PROFILE:$URL" in
    public:http://*)
      say "note: profile is public but the URL is plain http — a gateway address should be https."
      ;;
  esac
fi

exit 0
