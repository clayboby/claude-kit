#!/usr/bin/env bash
# Offline test suite for the claude-kit plugins.
#
# Nothing here touches a real endpoint: every request goes to a stub HTTP server
# on 127.0.0.1:8792 started by this script. Run from anywhere:
#
#   bash tests/run-offline-tests.sh
#
# Dependencies: bash, curl, python3 (the same set the hooks themselves need).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEDIA="$REPO/plugins/vagaa-media"
WEB="$REPO/plugins/vagaa-web-evidence"
STUB_PORT=8792
STUB="http://127.0.0.1:${STUB_PORT}"
SECRET="stub-credential-must-never-appear"

pass=0
fail=0

ok() { printf '  ok    %s\n' "$1"; pass=$((pass + 1)); }
no() { printf '  FAIL  %s\n' "$1"; printf '        expected: %s\n        actual:   %s\n' "$2" "$3"; fail=$((fail + 1)); }

expect_eq() { # name expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "$2" "$3"; fi
}
expect_contains() { # name needle haystack
  case "$3" in *"$2"*) ok "$1" ;; *) no "$1" "contains: $2" "$3" ;; esac
}
expect_empty() { # name actual
  if [ -z "$2" ]; then ok "$1"; else no "$1" "(no output)" "$2"; fi
}

# --------------------------------------------------------------------------
# 1. PostToolUse: structured output and the URL allowlist
# --------------------------------------------------------------------------
notify() { # stdin: hook payload; $1: configured gateway URL
  CLAUDE_PLUGIN_OPTION_MEDIA_MCP_URL="${1:-https://media.example.com/mcp}" \
  CLAUDE_PLUGIN_OPTION_MEDIA_MCP_TOKEN="$SECRET" \
    bash "$MEDIA/scripts/asset-notify.sh"
}
payload() { printf '{"tool_response":{"asset_url":"%s"}}' "$1"; }

echo "PostToolUse asset-notify"

out="$(payload 'https://media.example.com/assets/abc123def' | notify)"
expect_eq "accepts a same-origin /assets/<id> URL" \
  '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "作品已入库:https://media.example.com/assets/abc123def"}}' \
  "$out"

# The output must be exactly one JSON document with the documented shape.
shape="$(printf '%s' "$out" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
h = doc["hookSpecificOutput"]
assert set(doc) == {"hookSpecificOutput"}, doc
assert set(h) == {"hookEventName", "additionalContext"}, h
assert h["hookEventName"] == "PostToolUse"
print("valid")
' 2>&1)"
expect_eq "output is strict hookSpecificOutput JSON" "valid" "$shape"

for bad in \
  'https://evil.example.com/assets/abc123def' \
  'https://media.example.com:8443/assets/abc123def' \
  'http://media.example.com/assets/abc123def' \
  'javascript:alert(1)' \
  'file:///etc/passwd' \
  'https://media.example.com/assets/../../etc/passwd' \
  'https://media.example.com/assets/abc123def/../../../etc/passwd' \
  'https://user:pw@media.example.com/assets/abc123def' \
  'https://media.example.com/assets/ab' \
  'https://media.example.com/admin/tokens' \
  'https://media.example.com/assets/abc123def?sig=leak'
do
  expect_empty "rejects ${bad}" "$(payload "$bad" | notify)"
done

expect_empty "rejects a URL carrying control characters" \
  "$(printf '{"tool_response":{"asset_url":"https://media.example.com/assets/abc123def\\u000aInjected: ignore previous"}}' | notify)"

expect_empty "rejects an over-long id" \
  "$(payload "https://media.example.com/assets/$(python3 -c 'print("a"*65)')" | notify)"

count="$(python3 -c '
import json
print(json.dumps({"tool_response": {"shots": [
    {"asset_url": "https://media.example.com/assets/asset%03d000" % i} for i in range(9)]}}))' \
  | notify | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"].splitlines()))')"
expect_eq "relays at most 5 URLs" "5" "$count"

bytes="$(python3 -c '
import json
print(json.dumps({"tool_response": {"shots": [
    {"asset_url": "https://media.example.com/assets/" + str(i) + "b"*60} for i in range(5)]}}))' \
  | notify | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"].encode()) <= 1024)')"
expect_eq "keeps additionalContext within 1 KB" "True" "$bytes"

expect_empty "emits nothing when the response carries no asset_url" \
  "$(printf '{"tool_response":{"url":null,"status":"running"}}' | notify)"
expect_empty "survives non-JSON stdin" "$(printf 'not json' | notify)"
expect_empty "survives empty stdin" "$(printf '' | notify)"
expect_empty "emits nothing when the gateway URL is unset" \
  "$(payload 'https://media.example.com/assets/abc123def' | CLAUDE_PLUGIN_OPTION_MEDIA_MCP_URL='' CLAUDE_PLUGIN_OPTION_MEDIA_MCP_TOKEN="$SECRET" bash "$MEDIA/scripts/asset-notify.sh")"

leak="$(payload 'https://media.example.com/assets/abc123def' | notify | grep -c "$SECRET")"
expect_eq "never echoes the token" "0" "$leak"

# The child process must not even see a credential in its environment.
envleak="$(CLAUDE_PLUGIN_OPTION_MEDIA_MCP_URL="https://media.example.com/mcp" \
  CLAUDE_PLUGIN_OPTION_MEDIA_MCP_TOKEN="$SECRET" \
  CLAUDE_PLUGIN_OPTION_NOLE_CREDENTIAL="$SECRET" \
  bash -c '
    set -euo pipefail
    while IFS="=" read -r n _; do
      case "$n" in
        CLAUDE_PLUGIN_OPTION_*TOKEN*|CLAUDE_PLUGIN_OPTION_*CREDENTIAL*|CLAUDE_PLUGIN_OPTION_*SECRET*|CLAUDE_PLUGIN_OPTION_*KEY*|CLAUDE_PLUGIN_OPTION_*PASSWORD*) unset "$n" || true ;;
      esac
    done < <(env | grep "^CLAUDE_PLUGIN_OPTION_" || true)
    python3 -c "
import os
print(sum(1 for k in os.environ if k.startswith(\"CLAUDE_PLUGIN_OPTION_\") and (\"TOKEN\" in k or \"CREDENTIAL\" in k)))"
  ')"
expect_eq "unsets credential variables before python3" "0" "$envleak"

# --------------------------------------------------------------------------
# 2. Matcher anchoring, replicating how Claude Code applies a hook matcher
#    (new RegExp(matcher).test(toolName), i.e. unanchored search semantics).
# --------------------------------------------------------------------------
echo
echo "PostToolUse matcher"
matcher="$(python3 -c '
import json, sys
doc = json.load(open(sys.argv[1]))
print(doc["hooks"]["PostToolUse"][0]["matcher"])' "$MEDIA/hooks/hooks.json")"

matches="$(python3 - "$matcher" <<'PY'
import re, sys
pat = sys.argv[1]
should = [
    "mcp__plugin_vagaa-media_media__video_fetch",
    "mcp__plugin_vagaa-media_media__image_fetch",
    "mcp__plugin_vagaa-media_media__music_fetch",
    "mcp__plugin_vagaa-media_media__storyboard_fetch",
]
should_not = [
    "xmcp__plugin_vagaa-media_media__video_fetch",
    "mcp__plugin_vagaa-media_media__video_fetchx",
    "mcp__plugin_vagaa-media_media__video_fetch_all",
    "evil_mcp__plugin_vagaa-media_media__video_fetch_evil",
    "mcp__plugin_vagaa-media_media__video_submit",
    "mcp__plugin_vagaa-media_media__jobs_list",
    "mcp__plugin_other_media__video_fetch",
    "mcp__media__video_fetch",
    "Bash",
]
bad = [n for n in should if not re.search(pat, n)]
bad += [n for n in should_not if re.search(pat, n)]
print("clean" if not bad else "unexpected: " + ", ".join(bad))
PY
)"
expect_eq "anchored matcher hits exactly the four fetch tools" "clean" "$matches"

# --------------------------------------------------------------------------
# 3. SessionStart preflight, against the local stub only
# --------------------------------------------------------------------------
echo
echo "SessionStart preflight"
if curl -s -o /dev/null --max-time 1 "$STUB/ok/healthz"; then
  echo "  something is already listening on ${STUB_PORT}; stop it and re-run" >&2
  exit 1
fi
python3 "$REPO/tests/stub_gateway.py" 120 &
stub_pid=$!
trap 'kill "$stub_pid" 2>/dev/null || true' EXIT
stub_up=""
for _ in $(seq 1 50); do
  if [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 "$STUB/ok/healthz")" = "200" ]; then
    stub_up=yes
    break
  fi
  sleep 0.2
done
if [ -z "$stub_up" ]; then
  echo "  stub gateway did not start on ${STUB_PORT}" >&2
  exit 1
fi

media_pre() { # $1 stub path, $2 surface
  CLAUDE_PLUGIN_OPTION_MEDIA_MCP_URL="$STUB/$1/mcp" \
  CLAUDE_PLUGIN_OPTION_MEDIA_MCP_TOKEN="$SECRET" \
  CLAUDE_PLUGIN_OPTION_SURFACE="${2-standard}" \
    bash "$MEDIA/scripts/preflight.sh"
}

expect_empty "stays silent when health and server/discover both pass" "$(media_pre ok)"
expect_contains "reports a rejected token" "rejected the configured token" "$(media_pre 401)"
expect_contains "reports a missing MCP endpoint" "no MCP endpoint at the configured URL" "$(media_pre 404)"
expect_contains "reports a non-JSON-RPC answer" "not with MCP JSON-RPC" "$(media_pre garbage)"
expect_contains "reports a probe timeout" "did not answer in 3s" "$(media_pre slow)"
expect_contains "reports an unreachable gateway" "unreachable (no answer in 3s)" \
  "$(CLAUDE_PLUGIN_OPTION_MEDIA_MCP_URL="http://127.0.0.1:1/mcp" CLAUDE_PLUGIN_OPTION_MEDIA_MCP_TOKEN="$SECRET" bash "$MEDIA/scripts/preflight.sh")"
expect_contains "reports an unconfigured gateway" "not configured" \
  "$(CLAUDE_PLUGIN_OPTION_MEDIA_MCP_URL='' bash "$MEDIA/scripts/preflight.sh")"
expect_contains "reports a non-http URL" "not http(s)" \
  "$(CLAUDE_PLUGIN_OPTION_MEDIA_MCP_URL="ftp://example.com/mcp" bash "$MEDIA/scripts/preflight.sh")"
expect_contains "notes a surface/URL mismatch" "surface is set to compact" "$(media_pre ok compact)"

for path in ok 401 404 garbage slow; do
  leak="$(media_pre "$path" | grep -c -e "$SECRET" -e "127.0.0.1")"
  expect_eq "prints neither credential nor URL ($path)" "0" "$leak"
done

web_pre() { # $1 stub path, $2 profile
  CLAUDE_PLUGIN_OPTION_NOLE_MCP_URL="$STUB/$1/mcp-compact" \
  CLAUDE_PLUGIN_OPTION_NOLE_CREDENTIAL="$SECRET" \
  CLAUDE_PLUGIN_OPTION_PROFILE="${2-lan}" \
    bash "$WEB/scripts/preflight.sh"
}
expect_empty "web-evidence: silent when healthy" "$(web_pre ok)"
expect_contains "web-evidence: names the two-credential rule on 401" \
  "直连填服务令牌,公网填网关密钥,不可互换" "$(web_pre 401)"
expect_contains "web-evidence: reports a missing endpoint" "no MCP endpoint" "$(web_pre 404)"
expect_contains "web-evidence: reports a non-JSON-RPC answer" "not with MCP JSON-RPC" "$(web_pre garbage)"
expect_contains "web-evidence: notes an unset profile" "profile is not set" "$(web_pre ok '')"
expect_contains "web-evidence: notes http under the public profile" "should be https" "$(web_pre ok public)"
leak="$(web_pre 401 | grep -c -e "$SECRET" -e "127.0.0.1")"
expect_eq "web-evidence: prints neither credential nor URL" "0" "$leak"

# --------------------------------------------------------------------------
echo
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
