#!/usr/bin/env bash
# PostToolUse hook for the media *_fetch and tts tools.
#
# Emits the stable asset-library URLs of whatever was just fetched or synthesized
# as hookSpecificOutput.additionalContext — a PostToolUse hook's plain stdout
# does NOT reach the model, only that field does. The transcript then keeps the
# stable /assets/<id> record (asset_url) rather than treating a presigned link
# (about 1 hour by default) as permanent.
# The record still needs authorization and is subject to asset retention.
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
    try:
        port = str(parts.port) if parts.port else DEFAULT_PORTS[scheme]
    except ValueError:
        return None
    return scheme + "://" + host + ":" + port


def parse_json_object(text):
    """Parse a JSON string only when the entire string is a JSON object."""
    if not isinstance(text, str):
        return None
    s = text.strip()
    if not s.startswith("{"):
        return None
    try:
        obj = json.loads(s)
    except (ValueError, TypeError):
        return None
    return obj if isinstance(obj, dict) else None


def unwrap_mcp_results(tool_response):
    """Unwrap only known MCP tool_response shapes; never recurse into arbitrary fields."""
    results = []
    if isinstance(tool_response, dict):
        if tool_response.get("isError") is True:
            return results
        unwrapped_wrapper = False
        content = tool_response.get("content")
        if isinstance(content, list):
            unwrapped_wrapper = True
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    obj = parse_json_object(block.get("text"))
                    if obj is not None:
                        results.append(obj)
        structured = tool_response.get("structuredContent")
        if isinstance(structured, dict):
            unwrapped_wrapper = True
            results.append(structured)
        if not unwrapped_wrapper:
            results.append(tool_response)
    elif isinstance(tool_response, list):
        for item in tool_response:
            if not isinstance(item, dict):
                continue
            if item.get("type") == "text" and isinstance(item.get("text"), str):
                obj = parse_json_object(item.get("text"))
                if obj is not None:
                    results.append(obj)
            else:
                results.append(item)
    return results


def short_tool_name(tool_name):
    if not isinstance(tool_name, str) or not tool_name:
        return ""
    return tool_name.rsplit("__", 1)[-1] if "__" in tool_name else tool_name


def extract_asset_urls(doc, tool_short):
    """Extract documented top-level artifact asset_url fields for *_fetch and tts only."""
    out = []
    is_tts = tool_short == "tts" or (not tool_short and doc.get("service") == "tts")
    if is_tts:
        status = doc.get("status")
        if status is not None and (not isinstance(status, str) or status.strip().lower() != "completed"):
            return out
        if doc.get("done") is False or doc.get("asset_pending") is True:
            return out
        val = doc.get("asset_url")
        if isinstance(val, str) and val.strip():
            out.append(val.strip())
        return out

    val = doc.get("asset_url")
    if isinstance(val, str) and val.strip():
        out.append(val.strip())
    for list_key in ("shots", "assets", "items", "artifacts"):
        entries = doc.get(list_key)
        if isinstance(entries, list):
            for entry in entries:
                if isinstance(entry, dict):
                    ev = entry.get("asset_url")
                    if isinstance(ev, str) and ev.strip():
                        out.append(ev.strip())
    return out


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

tool_short = short_tool_name(payload.get("tool_name"))
candidates = []
for doc in unwrap_mcp_results(payload.get("tool_response")):
    candidates.extend(extract_asset_urls(doc, tool_short))

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
    line = "作品记录（需鉴权；浏览器请用 fetch 的 url）:" + url
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
