#!/usr/bin/env bash
# PostToolUse hook for the media *_fetch tools: pull every stable asset_url out
# of the tool response and print one line per asset, so the stable library URL
# (not the 24 h presigned one) is what ends up in the transcript.
#
# The hook payload arrives as JSON on stdin. python3 -c keeps the program in an
# argument so stdin stays free for that payload. Dependencies: python3.
set -euo pipefail

python3 -c '
import json
import sys

MAX_LINES = 20


def walk(node, out):
    """Collect every asset_url value anywhere in the response."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "asset_url" and isinstance(value, str) and value.strip():
                out.append(value.strip())
            else:
                walk(value, out)
    elif isinstance(node, list):
        for item in node:
            walk(item, out)
    elif isinstance(node, str):
        text = node.strip()
        if text[:1] in "{[" and "asset_url" in text:
            try:
                walk(json.loads(text), out)
            except (ValueError, TypeError):
                pass


try:
    payload = json.load(sys.stdin)
except (ValueError, TypeError):
    sys.exit(0)

if not isinstance(payload, dict):
    sys.exit(0)

urls = []
walk(payload.get("tool_response"), urls)

seen = set()
for url in urls:
    if url in seen:
        continue
    seen.add(url)
    print("作品已入库：" + url)
    if len(seen) >= MAX_LINES:
        break
' || true

exit 0
