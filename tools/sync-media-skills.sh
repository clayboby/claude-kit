#!/usr/bin/env bash
# sync-media-skills.sh — sync exported media skills into plugins/vagaa-media/skills/
# and bump vagaa-media's patch version (three-way) only when normalized content changed.
#
# Usage:
#   tools/sync-media-skills.sh <media-repo-worktree> [--version X] [--check]
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: tools/sync-media-skills.sh <media-repo-worktree> [--version X] [--check]
EOF
  exit 2
}

MEDIA_REPO=""
VERSION=""
HAS_VERSION=0
CHECK_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --check)
      CHECK_ONLY=1
      shift
      ;;
    --version)
      [ $# -ge 2 ] || usage
      [ -n "$2" ] || usage
      [ "${2#-}" = "$2" ] || usage
      [ "$HAS_VERSION" -eq 0 ] || usage
      VERSION="$2"
      HAS_VERSION=1
      shift 2
      ;;
    --version=*)
      [ "$HAS_VERSION" -eq 0 ] || usage
      VERSION="${1#--version=}"
      [ -n "$VERSION" ] || usage
      [ "${VERSION#-}" = "$VERSION" ] || usage
      HAS_VERSION=1
      shift
      ;;
    -*)
      usage
      ;;
    *)
      if [ -z "$MEDIA_REPO" ]; then
        MEDIA_REPO="$1"
        shift
      else
        usage
      fi
      ;;
  esac
done

[ -n "$MEDIA_REPO" ] || usage

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SKILLS_DIR="$REPO_ROOT/plugins/vagaa-media/skills"
PLUGIN_JSON="$REPO_ROOT/plugins/vagaa-media/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
README_MD="$REPO_ROOT/plugins/vagaa-media/README.md"
CHECK_VERSIONS="$REPO_ROOT/tests/check_versions.py"
EXPORT_SCRIPT="$MEDIA_REPO/tools/export-skills.sh"

if [ ! -d "$MEDIA_REPO" ]; then
  echo "!! media repository worktree not found: $MEDIA_REPO" >&2
  exit 2
fi
if [ ! -f "$EXPORT_SCRIPT" ] || [ ! -x "$EXPORT_SCRIPT" ]; then
  echo "!! export script missing or not executable: $EXPORT_SCRIPT" >&2
  exit 2
fi

TMP_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/sync-media-skills.XXXXXX")
WRITES_STARTED=0
COMPLETED_OK=0
ROLLED_BACK_REPORTED=0
SKILLS_DIR_CLEAN_AT_START=0

do_rollback() {
  if [ "$ROLLED_BACK_REPORTED" -eq 1 ]; then
    return 0
  fi
  ROLLED_BACK_REPORTED=1
  set +e
  if [ "$SKILLS_DIR_CLEAN_AT_START" -ne 1 ]; then
    echo "!! partial change left in place (the skills directory was dirty before this run)" >&2
    echo "ROLLED_BACK no"
    return 0
  fi
  local ok=1
  if ! git -C "$REPO_ROOT" clean -fd -q -- plugins/vagaa-media/skills; then
    ok=0
  fi
  if ! git -C "$REPO_ROOT" checkout -q HEAD -- plugins/vagaa-media/skills; then
    ok=0
  fi
  if [ -f "$TMP_PARENT/orig/plugin.json" ]; then
    cat "$TMP_PARENT/orig/plugin.json" > "$PLUGIN_JSON" || ok=0
  fi
  if [ -f "$TMP_PARENT/orig/marketplace.json" ]; then
    cat "$TMP_PARENT/orig/marketplace.json" > "$MARKETPLACE_JSON" || ok=0
  fi
  if [ -f "$TMP_PARENT/orig/README.md" ]; then
    cat "$TMP_PARENT/orig/README.md" > "$README_MD" || ok=0
  fi
  local leftover
  leftover=$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all -- plugins/vagaa-media/skills 2>/dev/null || echo "git-error")
  if [ "$ok" -eq 1 ] && [ -z "$leftover" ]; then
    echo "ROLLED_BACK yes"
  else
    echo "ROLLED_BACK no"
  fi
}

cleanup() {
  if [ "$WRITES_STARTED" -eq 1 ] && [ "$COMPLETED_OK" -eq 0 ]; then
    do_rollback || true
  fi
  rm -rf "$TMP_PARENT"
}
trap cleanup EXIT

NEW_DIR="$TMP_PARENT/skills-new"
EXPORT_LOG="$TMP_PARENT/export.log"

VERSION_ARGS=()
if [ "$HAS_VERSION" -eq 1 ]; then
  VERSION_ARGS=(--version "$VERSION")
fi

if ! "$EXPORT_SCRIPT" "$NEW_DIR" ${VERSION_ARGS[@]+"${VERSION_ARGS[@]}"} >"$EXPORT_LOG" 2>&1; then
  cat "$EXPORT_LOG" >&2
  exit 2
fi

if [ ! -d "$NEW_DIR" ]; then
  echo "!! export script succeeded but did not create directory: $NEW_DIR" >&2
  exit 2
fi

DIFF_FILE="$TMP_PARENT/diff.txt"

python3 - "$NEW_DIR" "$SKILLS_DIR" "$DIFF_FILE" <<'PY'
import hashlib
import os
import sys
from pathlib import Path

new_root = Path(sys.argv[1])
old_root = Path(sys.argv[2])
diff_out = Path(sys.argv[3])


def scan_tree(root: Path) -> dict[str, bytes]:
    entries: dict[str, bytes] = {}
    if not root.exists():
        return entries
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames.sort()
        filenames.sort()
        for fname in filenames:
            full = Path(dirpath) / fname
            rel = full.relative_to(root).as_posix()
            if rel == "EXPORTED-FROM":
                continue
            if full.is_symlink():
                digest = hashlib.sha256(b"symlink:" + os.readlink(full).encode("utf-8", "surrogateescape")).digest()
            else:
                h = hashlib.sha256()
                with full.open("rb") as fh:
                    while True:
                        chunk = fh.read(65536)
                        if not chunk:
                            break
                        h.update(chunk)
                digest = h.digest()
            entries[rel] = digest
    return entries


new_map = scan_tree(new_root)
old_map = scan_tree(old_root)

changes: list[str] = []
for rel in sorted(set(new_map) | set(old_map)):
    in_new = rel in new_map
    in_old = rel in old_map
    if in_new and not in_old:
        changes.append(f"A {rel}")
    elif in_old and not in_new:
        changes.append(f"D {rel}")
    elif new_map[rel] != old_map[rel]:
        changes.append(f"M {rel}")

diff_out.write_text("\n".join(changes) + ("\n" if changes else ""), encoding="utf-8")
PY

CHANGE_COUNT=$(wc -l < "$DIFF_FILE" | tr -d ' ')

if [ "$CHANGE_COUNT" -gt 0 ] && [ "$CHECK_ONLY" -eq 1 ]; then
  echo "SKILLS_CONTENT changed $CHANGE_COUNT files"
  head -n 40 "$DIFF_FILE"
  if [ "$CHANGE_COUNT" -gt 40 ]; then
    echo "… +$((CHANGE_COUNT - 40)) more"
  fi
  exit 1
fi

# Validate three-way consistency, inspect HEAD state, and precompute staged edits in temp dir BEFORE any repo write.
BUMP_PLAN="$TMP_PARENT/bump-plan.txt"
ORIG_DIR="$TMP_PARENT/orig"
STAGED_DIR="$TMP_PARENT/staged"
mkdir -p "$ORIG_DIR" "$STAGED_DIR"

python3 - "$REPO_ROOT" "$BUMP_PLAN" "$ORIG_DIR" "$STAGED_DIR" <<'PY'
import json
import re
import subprocess
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
plan_path = Path(sys.argv[2])
orig_dir = Path(sys.argv[3])
staged_dir = Path(sys.argv[4])

SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
README_VER_RE = re.compile(
    r"^\|\s*Plugin version\s*\|\s*\*\*([0-9]+\.[0-9]+\.[0-9]+)\*\*\s*\|$",
    re.MULTILINE,
)
JSON_TOKEN_RE = re.compile(
    r'"(?:\\.|[^"\\])*"|\s+|[{}\[\]:,]|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null'
)


def parse_semver(ver: object) -> tuple[int, int, int] | None:
    if not isinstance(ver, str):
        return None
    m = SEMVER_RE.match(ver)
    if not m:
        return None
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)))


def fail(msg: str) -> None:
    print(f"!! {msg}", file=sys.stderr)
    raise SystemExit(2)


def tokenize_json(text: str) -> list[tuple[str, int, int]]:
    tokens: list[tuple[str, int, int]] = []
    pos = 0
    for m in JSON_TOKEN_RE.finditer(text):
        if m.start() != pos:
            raise ValueError(f"unexpected JSON token at offset {pos}")
        pos = m.end()
        tok = m.group(0)
        if not tok.isspace():
            tokens.append((tok, m.start(), m.end()))
    if pos != len(text):
        raise ValueError(f"trailing unparsed JSON at offset {pos}")
    return tokens


def find_top_level_version_span(text: str) -> tuple[int, int]:
    tokens = tokenize_json(text)
    depth = 0
    i = 0
    while i < len(tokens):
        tok, _, _ = tokens[i]
        if tok == "{":
            depth += 1
        elif tok == "}":
            depth -= 1
        elif tok == "[":
            depth += 1
        elif tok == "]":
            depth -= 1
        elif (
            depth == 1
            and tok.startswith('"')
            and json.loads(tok) == "version"
            and i + 2 < len(tokens)
            and tokens[i + 1][0] == ":"
            and tokens[i + 2][0].startswith('"')
        ):
            return tokens[i + 2][1], tokens[i + 2][2]
        i += 1
    raise ValueError("top-level 'version' string not found")


def find_marketplace_plugin_version_span(text: str, target_name: str) -> tuple[int, int]:
    tokens = tokenize_json(text)
    depth = 0
    in_plugins_array = False
    plugins_array_depth = -1
    cur_obj_name: str | None = None
    cur_obj_ver_span: tuple[int, int] | None = None
    i = 0
    while i < len(tokens):
        tok, _, _ = tokens[i]
        if tok == "{":
            depth += 1
            if in_plugins_array and depth == plugins_array_depth + 1:
                cur_obj_name = None
                cur_obj_ver_span = None
        elif tok == "}":
            if in_plugins_array and depth == plugins_array_depth + 1:
                if cur_obj_name == target_name:
                    if cur_obj_ver_span is None:
                        raise ValueError(f"plugin {target_name!r} has no 'version' string")
                    return cur_obj_ver_span
            depth -= 1
        elif tok == "[":
            depth += 1
            if (
                not in_plugins_array
                and depth == 2
                and i >= 2
                and tokens[i - 1][0] == ":"
                and tokens[i - 2][0].startswith('"')
                and json.loads(tokens[i - 2][0]) == "plugins"
            ):
                in_plugins_array = True
                plugins_array_depth = depth
        elif tok == "]":
            if in_plugins_array and depth == plugins_array_depth:
                in_plugins_array = False
                plugins_array_depth = -1
            depth -= 1
        elif (
            in_plugins_array
            and depth == plugins_array_depth + 1
            and tok.startswith('"')
            and i + 2 < len(tokens)
            and tokens[i + 1][0] == ":"
            and tokens[i + 2][0].startswith('"')
        ):
            key = json.loads(tok)
            if key == "name":
                cur_obj_name = json.loads(tokens[i + 2][0])
            elif key == "version":
                cur_obj_ver_span = (tokens[i + 2][1], tokens[i + 2][2])
        i += 1
    raise ValueError(f"plugin {target_name!r} version span not found in marketplace.json")


def render_single_line_span_update(text: str, span: tuple[int, int], new_literal: str, label: str) -> str:
    updated = text[: span[0]] + new_literal + text[span[1] :]
    old_lines = text.splitlines()
    new_lines = updated.splitlines()
    if len(old_lines) != len(new_lines):
        raise ValueError(f"{label}: line count changed during single-value update")
    changed = sum(1 for a, b in zip(old_lines, new_lines) if a != b)
    if changed != 1:
        raise ValueError(f"{label}: expected 1 changed line, got {changed}")
    json.loads(updated)
    return updated


pj_path = repo_root / "plugins/vagaa-media/.claude-plugin/plugin.json"
mp_path = repo_root / ".claude-plugin/marketplace.json"
rm_path = repo_root / "plugins/vagaa-media/README.md"

try:
    pj_text = pj_path.read_text(encoding="utf-8")
    mp_text = mp_path.read_text(encoding="utf-8")
    rm_text = rm_path.read_text(encoding="utf-8")
    pj_doc = json.loads(pj_text)
    mp_doc = json.loads(mp_text)
except (OSError, ValueError) as exc:
    fail(f"failed reading version metadata: {exc}")

pj_ver = pj_doc.get("version") if isinstance(pj_doc, dict) else None
plugins = mp_doc.get("plugins") if isinstance(mp_doc, dict) else None
if not isinstance(plugins, list):
    fail("marketplace.json: 'plugins' must be a list")

vagaa_entries = [p for p in plugins if isinstance(p, dict) and p.get("name") == "vagaa-media"]
if len(vagaa_entries) != 1:
    fail(f"marketplace.json: expected 1 'vagaa-media' entry, found {len(vagaa_entries)}")
mp_ver = vagaa_entries[0].get("version")

rm_matches = README_VER_RE.findall(rm_text)
if len(rm_matches) != 1:
    fail(f"plugins/vagaa-media/README.md: expected 1 Plugin version row, found {len(rm_matches)}")
rm_ver = rm_matches[0]

if not (pj_ver == mp_ver == rm_ver):
    fail(f"three-way version mismatch: plugin.json={pj_ver!r} marketplace.json={mp_ver!r} README.md={rm_ver!r}")

cur_tuple = parse_semver(pj_ver)
if cur_tuple is None:
    fail(f"non-semver vagaa-media version: {pj_ver!r}")

head_res = subprocess.run(
    ["git", "-C", str(repo_root), "show", "HEAD:plugins/vagaa-media/.claude-plugin/plugin.json"],
    capture_output=True,
    text=True,
    timeout=10,
)
if head_res.returncode != 0:
    fail(f"failed reading HEAD baseline plugin.json: {head_res.stderr.strip()}")

try:
    base_ver = json.loads(head_res.stdout).get("version")
except ValueError as exc:
    fail(f"invalid HEAD baseline plugin.json: {exc}")

base_tuple = parse_semver(base_ver)
if base_tuple is None:
    fail(f"non-semver HEAD baseline version: {base_ver!r}")

if cur_tuple < base_tuple:
    fail(f"working tree version {pj_ver} is behind HEAD baseline {base_ver}")

if cur_tuple > base_tuple:
    new_ver = pj_ver
    status = "already"
else:
    new_ver = f"{cur_tuple[0]}.{cur_tuple[1]}.{cur_tuple[2] + 1}"
    status = "bumped"

# Check whether skills directory is clean at start (for safe rollback) and whether normalized content differs from HEAD.
st_res = subprocess.run(
    ["git", "-C", str(repo_root), "status", "--porcelain", "--untracked-files=all", "--", "plugins/vagaa-media/skills"],
    capture_output=True,
    text=True,
    timeout=10,
)
if st_res.returncode != 0:
    fail(f"git status failed: {st_res.stderr.strip()}")
skills_dir_clean = "1" if not st_res.stdout.strip() else "0"

diff_res = subprocess.run(
    ["git", "-C", str(repo_root), "diff", "-z", "--name-only", "HEAD", "--", "plugins/vagaa-media/skills"],
    capture_output=True,
    timeout=10,
)
if diff_res.returncode != 0:
    fail(f"git diff HEAD failed: {diff_res.stderr.decode('utf-8', 'replace').strip()}")
untracked_res = subprocess.run(
    ["git", "-C", str(repo_root), "ls-files", "-z", "--others", "--exclude-standard", "--", "plugins/vagaa-media/skills"],
    capture_output=True,
    timeout=10,
)
if untracked_res.returncode != 0:
    fail(f"git ls-files failed: {untracked_res.stderr.decode('utf-8', 'replace').strip()}")

changed_vs_head = {
    p for p in (diff_res.stdout.decode("utf-8", "surrogateescape").split("\0") + untracked_res.stdout.decode("utf-8", "surrogateescape").split("\0"))
    if p and p != "plugins/vagaa-media/skills/EXPORTED-FROM"
}
skills_content_dirty_vs_head = "1" if changed_vs_head else "0"

# Save original metadata bytes and precompute + validate staged version edits before any repo write.
(orig_dir / "plugin.json").write_text(pj_text, encoding="utf-8")
(orig_dir / "marketplace.json").write_text(mp_text, encoding="utf-8")
(orig_dir / "README.md").write_text(rm_text, encoding="utf-8")

if status == "bumped":
    try:
        new_literal = json.dumps(new_ver)
        pj_span = find_top_level_version_span(pj_text)
        if json.loads(pj_text[pj_span[0] : pj_span[1]]) != pj_ver:
            raise ValueError("plugin.json version token mismatch")
        pj_updated = render_single_line_span_update(pj_text, pj_span, new_literal, "plugin.json")

        mp_span = find_marketplace_plugin_version_span(mp_text, "vagaa-media")
        if json.loads(mp_text[mp_span[0] : mp_span[1]]) != pj_ver:
            raise ValueError("marketplace.json vagaa-media version token mismatch")
        mp_updated = render_single_line_span_update(mp_text, mp_span, new_literal, "marketplace.json")

        rm_updated, n = re.subn(
            r"^(\|\s*Plugin version\s*\|\s*\*\*)([0-9]+\.[0-9]+\.[0-9]+)(\*\*\s*\|)$",
            rf"\g<1>{new_ver}\g<3>",
            rm_text,
            flags=re.MULTILINE,
        )
        if n != 1 or README_VER_RE.findall(rm_updated) != [new_ver]:
            raise ValueError(f"README.md: expected 1 Plugin version replacement, got {n}")
        if len(rm_text.splitlines()) != len(rm_updated.splitlines()):
            raise ValueError("README.md: line count changed during version update")
        if sum(1 for a, b in zip(rm_text.splitlines(), rm_updated.splitlines()) if a != b) != 1:
            raise ValueError("README.md: expected 1 changed line")
    except ValueError as exc:
        fail(f"failed precomputing version updates: {exc}")

    (staged_dir / "plugin.json").write_text(pj_updated, encoding="utf-8")
    (staged_dir / "marketplace.json").write_text(mp_updated, encoding="utf-8")
    (staged_dir / "README.md").write_text(rm_updated, encoding="utf-8")

plan_path.write_text(
    f"{status}\n{pj_ver}\n{new_ver}\n{skills_dir_clean}\n{skills_content_dirty_vs_head}\n",
    encoding="utf-8",
)
PY

{
  IFS= read -r BUMP_STATUS
  IFS= read -r OLD_VER
  IFS= read -r NEW_VER
  IFS= read -r SKILLS_DIR_CLEAN_AT_START
  IFS= read -r SKILLS_CONTENT_DIRTY_VS_HEAD
} < "$BUMP_PLAN"

apply_staged_versions() {
  if [ "$BUMP_STATUS" = "bumped" ]; then
    cat "$STAGED_DIR/plugin.json" > "$PLUGIN_JSON"
    cat "$STAGED_DIR/marketplace.json" > "$MARKETPLACE_JSON"
    cat "$STAGED_DIR/README.md" > "$README_MD"
  fi
}

run_check_versions() {
  local base_ref="${KIT_BASE_REF:-HEAD}"
  local check_out
  if ! check_out=$(KIT_BASE_REF="$base_ref" python3 "$CHECK_VERSIONS" all "$REPO_ROOT" "$base_ref" 2>&1); then
    echo "$check_out" >&2
    return 1
  fi
  return 0
}

if [ "$CHANGE_COUNT" -eq 0 ]; then
  if [ "$SKILLS_CONTENT_DIRTY_VS_HEAD" -eq 1 ] && [ "$BUMP_STATUS" = "bumped" ]; then
    if [ "$CHECK_ONLY" -eq 1 ]; then
      echo "SKILLS_CONTENT unchanged (resumed: version bump was missing)"
      exit 1
    fi
    WRITES_STARTED=1
    if ! apply_staged_versions; then
      echo "!! failed writing staged version files" >&2
      do_rollback
      exit 2
    fi
    if ! run_check_versions; then
      do_rollback
      exit 2
    fi
    COMPLETED_OK=1
    echo "SKILLS_CONTENT unchanged (resumed: version bump was missing)"
    echo "VERSION_BUMP $OLD_VER -> $NEW_VER"
    exit 0
  fi
  echo "SKILLS_CONTENT unchanged"
  echo "VERSION_BUMP none"
  exit 0
fi

WRITES_STARTED=1

if ! mkdir -p "$SKILLS_DIR" || ! rsync -a --delete --checksum "$NEW_DIR/" "$SKILLS_DIR/"; then
  echo "!! failed syncing skills directory" >&2
  do_rollback
  exit 2
fi

if ! apply_staged_versions; then
  echo "!! failed writing staged version files" >&2
  do_rollback
  exit 2
fi

if ! run_check_versions; then
  do_rollback
  exit 2
fi

COMPLETED_OK=1

EXPORTED_FROM_LINE="(none)"
if [ -f "$NEW_DIR/EXPORTED-FROM" ]; then
  EXPORTED_FROM_LINE=$(tr -d '\r\n' < "$NEW_DIR/EXPORTED-FROM")
fi

echo "SKILLS_CONTENT changed $CHANGE_COUNT files"
if [ "$BUMP_STATUS" = "bumped" ]; then
  echo "VERSION_BUMP $OLD_VER -> $NEW_VER"
else
  echo "VERSION_BUMP already $NEW_VER"
fi
echo "EXPORTED-FROM: $EXPORTED_FROM_LINE"
echo "NEXT: review git diff, run tests/run-offline-tests.sh, commit"
exit 0
