"""Shared offline version-metadata and skills-export bump checks for claude-kit.

Used by both tests/run-offline-tests.sh and tests/test_hook_manifests.py so
there is a single source of truth for:
  1. Uniqueness of plugin names in .claude-plugin/marketplace.json and three-way
     version consistency across plugin.json, marketplace.json, and plugin README.
  2. Ensuring plugins/vagaa-media/skills/ changes relative to KIT_BASE_REF
     (default: origin/main, local git objects only, no network) are accompanied
     by a strictly higher vagaa-media plugin.json version.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import sys

SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
README_VER_RE = re.compile(
    r"^\|\s*Plugin version\s*\|\s*\*\*([0-9]+\.[0-9]+\.[0-9]+)\*\*\s*\|$",
    re.MULTILINE,
)


def parse_semver(version: object) -> tuple[int, int, int] | None:
    if not isinstance(version, str):
        return None
    m = SEMVER_RE.match(version)
    if not m:
        return None
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)))


def check_three_way_consistency(repo_root: Path) -> list[str]:
    """Validate marketplace uniqueness and plugin.json == marketplace.json == README.md."""
    errors: list[str] = []
    marketplace_path = repo_root / ".claude-plugin/marketplace.json"
    marketplace = json.loads(marketplace_path.read_text(encoding="utf-8"))
    raw_plugins = marketplace.get("plugins")
    if not isinstance(raw_plugins, list):
        return ["marketplace.json: 'plugins' must be a list"]

    counts: dict[str, int] = {}
    market: dict[str, object] = {}
    for idx, entry in enumerate(raw_plugins):
        if not isinstance(entry, dict):
            errors.append(f"marketplace.json: plugins[{idx}] is not an object")
            continue
        name = entry.get("name")
        if not isinstance(name, str) or not name:
            errors.append(f"marketplace.json: plugins[{idx}] missing valid 'name'")
            continue
        counts[name] = counts.get(name, 0) + 1
        if name not in market:
            market[name] = entry.get("version")

    dups = sorted(name for name, cnt in counts.items() if cnt != 1)
    if dups:
        errors.append(
            "marketplace.json: duplicate plugin entries: "
            + ", ".join(f"{n} (x{counts[n]})" for n in dups)
        )

    plugins_dir = repo_root / "plugins"
    dirs = sorted(p.name for p in plugins_dir.iterdir() if p.is_dir()) if plugins_dir.is_dir() else []
    if set(market) != set(dirs):
        errors.append(f"plugin set mismatch: marketplace={sorted(market)} dirs={dirs}")

    for name in dirs:
        p_json_path = plugins_dir / name / ".claude-plugin/plugin.json"
        readme_path = plugins_dir / name / "README.md"
        p_ver = json.loads(p_json_path.read_text(encoding="utf-8")).get("version")
        m_ver = market.get(name)
        r_matches = README_VER_RE.findall(readme_path.read_text(encoding="utf-8"))
        if parse_semver(p_ver) is None:
            errors.append(f"{name}: plugin.json version {p_ver!r} is not X.Y.Z semver")
        if len(r_matches) != 1:
            errors.append(f"{name}/README.md: expected 1 Plugin version row, found {len(r_matches)}")
            continue
        r_ver = r_matches[0]
        if not (p_ver == m_ver == r_ver):
            errors.append(f"{name}: plugin.json={p_ver} marketplace={m_ver} README={r_ver}")

    return errors


def _git_offline(repo_root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    env = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith(("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_TRACE"))
    }
    env["GIT_ALLOW_PROTOCOL"] = ""
    env["GIT_NO_LAZY_FETCH"] = "1"
    return subprocess.run(
        ["git", "-C", str(repo_root), "-c", "protocol.allow=never", *args],
        capture_output=True,
        text=True,
        env=env,
        timeout=10,
    )


def check_skills_bump_against_base(repo_root: Path, base_ref: str | None = None) -> tuple[str, str]:
    """Check that vagaa-media skills changes vs base_ref also bump plugin.json version.

    Returns (status, detail) where status is 'ok', 'skip', or 'fail'.
    Only inspects local git objects; never fetches.
    """
    ref = (base_ref if base_ref is not None else os.environ.get("KIT_BASE_REF", "")).strip() or "origin/main"

    rev = _git_offline(repo_root, "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
    if rev.returncode != 0:
        return ("skip", f"base ref {ref!r} not available locally (no fetch performed)")

    diff = _git_offline(repo_root, "diff", "--quiet", ref, "--", "plugins/vagaa-media/skills")
    untracked = _git_offline(
        repo_root, "ls-files", "--others", "--exclude-standard", "--", "plugins/vagaa-media/skills"
    )
    if diff.returncode not in (0, 1) or untracked.returncode != 0:
        return ("fail", f"git diff failed against {ref!r}: {(diff.stderr or untracked.stderr).strip()}")

    skills_changed = (diff.returncode == 1) or bool(untracked.stdout.strip())
    if not skills_changed:
        return ("ok", f"plugins/vagaa-media/skills/ unchanged vs {ref}")

    base_pj = _git_offline(repo_root, "show", f"{ref}:plugins/vagaa-media/.claude-plugin/plugin.json")
    if base_pj.returncode != 0:
        return ("skip", f"vagaa-media plugin.json absent at base ref {ref!r}")
    try:
        base_ver = json.loads(base_pj.stdout).get("version")
        cur_ver = json.loads(
            (repo_root / "plugins/vagaa-media/.claude-plugin/plugin.json").read_text(encoding="utf-8")
        ).get("version")
    except (ValueError, OSError) as exc:
        return ("fail", f"failed reading plugin.json version: {exc}")

    base_tuple = parse_semver(base_ver)
    cur_tuple = parse_semver(cur_ver)
    if base_tuple is None or cur_tuple is None:
        return ("fail", f"non-semver vagaa-media version (base={base_ver!r}, current={cur_ver!r})")
    if cur_tuple <= base_tuple:
        return (
            "fail",
            f"plugins/vagaa-media/skills/ changed vs {ref} but vagaa-media version did not increase ({base_ver} -> {cur_ver})",
        )
    return ("ok", f"skills changed vs {ref} and vagaa-media version bumped {base_ver} -> {cur_ver}")


def main(argv: list[str]) -> int:
    mode = argv[1] if len(argv) > 1 else "all"
    repo_root = Path(argv[2]).resolve() if len(argv) > 2 else Path(__file__).resolve().parents[1]
    base_ref = argv[3] if len(argv) > 3 else None

    if mode in ("consistency", "all"):
        errs = check_three_way_consistency(repo_root)
        if errs:
            print("; ".join(errs))
            return 1
        if mode == "consistency":
            print("clean")
            return 0

    if mode in ("skills-bump", "all"):
        status, detail = check_skills_bump_against_base(repo_root, base_ref=base_ref)
        print(f"{status}: {detail}")
        if status == "fail":
            return 1
        return 0

    print(f"unknown mode: {mode}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
