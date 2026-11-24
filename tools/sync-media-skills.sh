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
trap 'rm -rf "$TMP_PARENT"' EXIT

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

if [ "$CHANGE_COUNT" -eq 0 ]; then
  echo "SKILLS_CONTENT unchanged"
  echo "VERSION_BUMP none"
  exit 0
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "SKILLS_CONTENT changed $CHANGE_COUNT files"
  head -n 40 "$DIFF_FILE"
  if [ "$CHANGE_COUNT" -gt 40 ]; then
    echo "… +$((CHANGE_COUNT - 40)) more"
  fi
  exit 1
fi

# Validate three-way consistency and compute target version BEFORE modifying anything in the repo.
BUMP_PLAN="$TMP_PARENT/bump-plan.txt"
python3 - "$REPO_ROOT" "$BUMP_PLAN" <<'PY'
import json
import re
import subprocess
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
plan_path = Path(sys.argv[2])

SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
README_VER_RE = re.compile(
    r"^\|\s*Plugin version\s*\|\s*\*\*([0-9]+\.[0-9]+\.[0-9]+)\*\*\s*\|$",
    re.MULTILINE,
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


pj_path = repo_root / "plugins/vagaa-media/.claude-plugin/plugin.json"
mp_path = repo_root / ".claude-plugin/marketplace.json"
rm_path = repo_root / "plugins/vagaa-media/README.md"

try:
    pj_doc = json.loads(pj_path.read_text(encoding="utf-8"))
    mp_doc = json.loads(mp_path.read_text(encoding="utf-8"))
    rm_text = rm_path.read_text(encoding="utf-8")
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

plan_path.write_text(f"{status}\n{pj_ver}\n{new_ver}\n", encoding="utf-8")
PY

{
  IFS= read -r BUMP_STATUS
  IFS= read -r OLD_VER
  IFS= read -r NEW_VER
} < "$BUMP_PLAN"

mkdir -p "$SKILLS_DIR"
rsync -a --delete --checksum "$NEW_DIR/" "$SKILLS_DIR/"

if [ "$BUMP_STATUS" = "bumped" ]; then
  python3 - "$REPO_ROOT" "$OLD_VER" "$NEW_VER" <<'PY'
import json
import re
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
old_ver = sys.argv[2]
new_ver = sys.argv[3]

JSON_TOKEN_RE = re.compile(
    r'"(?:\\.|[^"\\])*"|\s+|[{}\[\]:,]|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null'
)


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
        tok, start, end = tokens[i]
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
        tok, start, end = tokens[i]
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


def replace_span_single_line(path: Path, span: tuple[int, int], new_literal: str) -> None:
    text = path.read_text(encoding="utf-8")
    updated = text[: span[0]] + new_literal + text[span[1] :]
    old_lines = text.splitlines()
    new_lines = updated.splitlines()
    if len(old_lines) != len(new_lines):
        raise ValueError(f"{path}: line count changed during single-value update")
    changed = sum(1 for a, b in zip(old_lines, new_lines) if a != b)
    if changed != 1:
        raise ValueError(f"{path}: expected 1 changed line, got {changed}")
    path.write_text(updated, encoding="utf-8")


new_literal = json.dumps(new_ver)

pj_path = repo_root / "plugins/vagaa-media/.claude-plugin/plugin.json"
pj_text = pj_path.read_text(encoding="utf-8")
pj_span = find_top_level_version_span(pj_text)
if json.loads(pj_text[pj_span[0] : pj_span[1]]) != old_ver:
    raise ValueError("plugin.json version changed unexpectedly")
replace_span_single_line(pj_path, pj_span, new_literal)

mp_path = repo_root / ".claude-plugin/marketplace.json"
mp_text = mp_path.read_text(encoding="utf-8")
mp_span = find_marketplace_plugin_version_span(mp_text, "vagaa-media")
if json.loads(mp_text[mp_span[0] : mp_span[1]]) != old_ver:
    raise ValueError("marketplace.json vagaa-media version changed unexpectedly")
replace_span_single_line(mp_path, mp_span, new_literal)

rm_path = repo_root / "plugins/vagaa-media/README.md"
rm_text = rm_path.read_text(encoding="utf-8")
rm_updated, n = re.subn(
    r"^(\|\s*Plugin version\s*\|\s*\*\*)([0-9]+\.[0-9]+\.[0-9]+)(\*\*\s*\|)$",
    rf"\g<1>{new_ver}\g<3>",
    rm_text,
    flags=re.MULTILINE,
)
if n != 1:
    raise ValueError(f"README.md: expected 1 Plugin version replacement, got {n}")
rm_path.write_text(rm_updated, encoding="utf-8")
PY
fi

BASE_REF="${KIT_BASE_REF:-HEAD}"
if ! CHECK_OUT=$(KIT_BASE_REF="$BASE_REF" python3 "$CHECK_VERSIONS" all "$REPO_ROOT" "$BASE_REF" 2>&1); then
  echo "$CHECK_OUT" >&2
  exit 2
fi

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
