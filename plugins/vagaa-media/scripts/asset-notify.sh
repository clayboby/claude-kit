#!/usr/bin/env bash
# PostToolUse hook for the media *_fetch tools.
#
# Emits the stable asset-library URLs of whatever was just fetched as
# hookSpecificOutput.additionalContext — a PostToolUse hook's plain stdout does
# NOT reach the model, only that field does. The transcript then keeps the
# permanent /assets/<id> link rather than the 24h presigned one.
#
# A tool response is remote data. Only URLs that are http(s), share the exact
# origin of the configured gateway, and whose path is /assets/<id> are relayed;
# at most 5 of them, at most 1 KB in total.
#
# Dependencies: python3.
set -euo pipefail

# The gateway origin is all the child needs. Drop every credential the harness
# injected before starting python3, so a token cannot leak through the child's
# environment, /proc, or a crash dump.
while IFS='=' read -r _name _rest; do
  case "$_name" in
    CLAUDE_PLUGIN_OPTION_*TOKEN*|CLAUDE_PLUGIN_OPTION_*CREDENTIAL*|CLAUDE_PLUGIN_OPTION_*SECRET*|CLAUDE_PLUGIN_OPTION_*KEY*|CLAUDE_PLUGIN_OPTION_*PASSWORD*)
      unset "$_name" || true
      ;;
  esac
done < <(env | grep '^CLAUDE_PLUGIN_OPTION_' || true)
unset _name _rest

python3 -c '
import json
import re
import sys
from urllib.parse import urlsplit

MAX_URLS = 5
MAX_TOTAL_BYTES = 1024
ASSET_PATH = re.compile(r"^/assets/[A-Za-z0-9_-]{6,64}(/.*)?$")
CONTROL = re.compile(r"[\x00-\x1f\x7f]")
DEFAULT_PORTS = {"http": "80", "https": "443"}


def origin(url):
    """Scheme + host + explicit port, or None when the URL is unusable."""
    if not isinstance(url, str) or CONTROL.search(url):
        return None
    try:
        parts = urlsplit(url.strip())
    except ValueError:
        return None
    scheme = parts.scheme.lower()
    if scheme not in ("http", "https"):
        return None
    if parts.username or parts.password:
        return None
    host = (parts.hostname or "").lower()
    if not host:
        return None
    port = str(parts.port) if parts.port else DEFAULT_PORTS[scheme]
    return scheme + "://" + host + ":" + port


def collect(node, out):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "asset_url" and isinstance(value, str) and value.strip():
                out.append(value.strip())
            else:
                collect(value, out)
    elif isinstance(node, list):
        for item in node:
            collect(item, out)
    elif isinstance(node, str):
        text = node.strip()
        if text[:1] in "{[" and "asset_url" in text:
            try:
                collect(json.loads(text), out)
            except (ValueError, TypeError):
                pass


import os

trusted = origin(os.environ.get("CLAUDE_PLUGIN_OPTION_MEDIA_MCP_URL", ""))
if trusted is None:
    sys.exit(0)

try:
    payload = json.load(sys.stdin)
except (ValueError, TypeError):
    sys.exit(0)
if not isinstance(payload, dict):
    sys.exit(0)

candidates = []
collect(payload.get("tool_response"), candidates)

accepted = []
seen = set()
budget = MAX_TOTAL_BYTES
for url in candidates:
    if len(accepted) >= MAX_URLS or url in seen:
        continue
    if origin(url) != trusted:
        continue
    try:
        parts = urlsplit(url)
    except ValueError:
        continue
    if parts.query or parts.fragment:
        continue
    if not ASSET_PATH.match(parts.path):
        continue
    if any(seg in (".", "..") for seg in parts.path.split("/")):
        continue
    line = "作品已入库:" + url
    cost = len(line.encode("utf-8")) + 1
    if cost > budget:
        break
    budget -= cost
    seen.add(url)
    accepted.append(line)

if not accepted:
    sys.exit(0)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": "\n".join(accepted),
    }
}, ensure_ascii=False))
' || true

exit 0
