#!/usr/bin/env bash
# SessionStart hook: check that the two gateways this plugin talks to answer
# their unauthenticated health endpoints. Anything printed on stdout is added to
# the session context, so this prints at most two short lines and never prints a
# URL or a token. Dependencies: curl.
set -euo pipefail

TIMEOUT_S=3

# Derive a health URL from an MCP endpoint by stripping the MCP path suffix.
health_url() {
  local url="${1%/}"
  url="${url%/mcp-compact}"
  url="${url%/mcp}"
  printf '%s%s' "$url" "$2"
}

# Echo the HTTP status code of an unauthenticated GET, or 000 when unreachable.
probe() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' \
    --max-time "$TIMEOUT_S" --connect-timeout "$TIMEOUT_S" \
    -H 'Accept: application/json' \
    "$1" 2>/dev/null)" || true
  case "$code" in
    [0-9][0-9][0-9]) ;;
    *) code="000" ;;
  esac
  printf '%s' "$code"
}

# $1 label, $2 configured URL, $3 primary health path, $4 fallback health path
check() {
  local label="$1" url="${2:-}" primary="$3" fallback="$4" code

  if [ -z "$url" ]; then
    printf '%s\n' "[vagaa-dgx] ${label}: not configured — run /plugin, open vagaa-dgx and fill in its options."
    return 0
  fi

  case "$url" in
    http://*|https://*) ;;
    *)
      printf '%s\n' "[vagaa-dgx] ${label}: the configured URL is not http(s) — run /plugin and fix the plugin options."
      return 0
      ;;
  esac

  code="$(probe "$(health_url "$url" "$primary")")"
  if [ "$code" = "404" ] && [ -n "$fallback" ]; then
    code="$(probe "$(health_url "$url" "$fallback")")"
  fi

  case "$code" in
    2*) return 0 ;;
    000)
      printf '%s\n' "[vagaa-dgx] ${label}: unreachable (no response in ${TIMEOUT_S}s). Its tools will fail this session — check the network, the VPN or the service before using them."
      ;;
    *)
      printf '%s\n' "[vagaa-dgx] ${label}: health check answered HTTP ${code}. Its tools may fail this session."
      ;;
  esac
  return 0
}

check "media gateway" "${CLAUDE_PLUGIN_OPTION_MEDIA_MCP_URL:-}" "/healthz" "/health"
check "web-evidence router" "${CLAUDE_PLUGIN_OPTION_NOLE_MCP_URL:-}" "/health" "/healthz"

exit 0
