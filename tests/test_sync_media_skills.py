"""Offline tests for tools/sync-media-skills.sh using a stub media repo."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SYNC_SCRIPT = ROOT / "tools/sync-media-skills.sh"


def _git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    env = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith(("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY"))
    }
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        env=env,
        timeout=15,
    )


def _write_stub_export_script(media_repo: Path) -> Path:
    tools_dir = media_repo / "tools"
    tools_dir.mkdir(parents=True, exist_ok=True)
    script = tools_dir / "export-skills.sh"
    script.write_text(
        """#!/usr/bin/env bash
set -euo pipefail
if [ $# -lt 1 ]; then
  echo "usage: export-skills.sh <new-dir> [--version X]" >&2
  exit 2
fi
dest="$1"; shift
if [ -e "$dest" ] || [ -L "$dest" ]; then
  echo "!! $dest already exists" >&2
  exit 2
fi
if [ -n "${STUB_FAIL_CODE:-}" ]; then
  echo "${STUB_FAIL_MSG:-stub export failed}" >&2
  exit "$STUB_FAIL_CODE"
fi
if [ -n "${STUB_RECORD_ARGS:-}" ]; then
  printf '%s\\n' "$@" > "$STUB_RECORD_ARGS"
fi
here=$(cd "$(dirname "$0")/.." && pwd -P)
cp -Rp "$here/skills_fixture" "$dest"
marker="media-mcp ${STUB_MEDIA_VER:-0.9.99} @ deadbee (skills/ exported $(date '+%Y-%m-%d %H:%M:%S') ${RANDOM})"
printf '%s\\n' "$marker" > "$dest/EXPORTED-FROM"
echo "EXPORTED-FROM: $marker"
""",
        encoding="utf-8",
    )
    script.chmod(0o755)
    return script


def _build_workspace(base: Path) -> tuple[Path, Path, Path]:
    kit_repo = base / "kit 仓"
    kit_repo.mkdir(parents=True)
    shutil.copytree(ROOT / ".claude-plugin", kit_repo / ".claude-plugin")
    shutil.copytree(ROOT / "plugins", kit_repo / "plugins")
    (kit_repo / "tools").mkdir()
    shutil.copy2(SYNC_SCRIPT, kit_repo / "tools/sync-media-skills.sh")
    (kit_repo / "tools/sync-media-skills.sh").chmod(0o755)
    (kit_repo / "tests").mkdir()
    shutil.copy2(ROOT / "tests/check_versions.py", kit_repo / "tests/check_versions.py")

    for args in (
        ("init", "-b", "main"),
        ("config", "user.name", "test"),
        ("config", "user.email", "test@example.com"),
        ("add", "."),
        ("commit", "-m", "base"),
    ):
        res = _git(kit_repo, *args)
        assert res.returncode == 0, res.stderr

    media_repo = base / "媒体 repo"
    media_repo.mkdir(parents=True)
    fixture = media_repo / "skills_fixture"
    shutil.copytree(kit_repo / "plugins/vagaa-media/skills", fixture)
    (fixture / "EXPORTED-FROM").unlink()
    _write_stub_export_script(media_repo)

    isolated_tmp = base / "tmp_work"
    isolated_tmp.mkdir()
    return kit_repo, media_repo, isolated_tmp


def _run_sync(
    kit_repo: Path,
    args: list[str],
    *,
    tmpdir: Path,
    extra_env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    env = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith(("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "KIT_BASE_REF"))
    }
    env["TMPDIR"] = str(tmpdir)
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        ["bash", str(kit_repo / "tools/sync-media-skills.sh"), *args],
        cwd=str(kit_repo),
        capture_output=True,
        text=True,
        env=env,
        timeout=20,
    )


def _read_three_versions(kit_repo: Path) -> tuple[str, str, str]:
    pj = json.loads((kit_repo / "plugins/vagaa-media/.claude-plugin/plugin.json").read_text(encoding="utf-8"))
    mp = json.loads((kit_repo / ".claude-plugin/marketplace.json").read_text(encoding="utf-8"))
    mp_ver = next(p["version"] for p in mp["plugins"] if p["name"] == "vagaa-media")
    rm = (kit_repo / "plugins/vagaa-media/README.md").read_text(encoding="utf-8")
    m = re.search(r"^\|\s*Plugin version\s*\|\s*\*\*([0-9]+\.[0-9]+\.[0-9]+)\*\*\s*\|$", rm, re.MULTILINE)
    assert m is not None, "Plugin version row missing"
    return pj["version"], mp_ver, m.group(1)


def _bump_patch(ver: str) -> str:
    a, b, c = (int(x) for x in ver.split("."))
    return f"{a}.{b}.{c + 1}"


class SyncMediaSkillsTests(unittest.TestCase):
    def test_a_unchanged_content_different_exported_from_is_noop(self):
        with tempfile.TemporaryDirectory(prefix="sync test 中文 ") as tmp:
            kit_repo, media_repo, tmpdir = _build_workspace(Path(tmp))
            before_marker = (kit_repo / "plugins/vagaa-media/skills/EXPORTED-FROM").read_text(encoding="utf-8")

            res = _run_sync(kit_repo, [str(media_repo)], tmpdir=tmpdir)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertIn("SKILLS_CONTENT unchanged", res.stdout)
            self.assertIn("VERSION_BUMP none", res.stdout)
            self.assertEqual(_git(kit_repo, "status", "--porcelain").stdout.strip(), "")
            after_marker = (kit_repo / "plugins/vagaa-media/skills/EXPORTED-FROM").read_text(encoding="utf-8")
            self.assertEqual(after_marker, before_marker)
            self.assertEqual(list(tmpdir.iterdir()), [])

    def test_b_modified_skill_syncs_and_bumps_three_places_preserving_format(self):
        with tempfile.TemporaryDirectory(prefix="sync test 中文 ") as tmp:
            kit_repo, media_repo, tmpdir = _build_workspace(Path(tmp))
            old_ver, _, _ = _read_three_versions(kit_repo)
            expected_new = _bump_patch(old_ver)

            target_rel = "media-production/SKILL.md"
            src_file = media_repo / "skills_fixture" / target_rel
            src_file.write_text(src_file.read_text(encoding="utf-8") + "\n<!-- updated -->\n", encoding="utf-8")

            res = _run_sync(kit_repo, [str(media_repo)], tmpdir=tmpdir)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertIn("SKILLS_CONTENT changed 1 files", res.stdout)
            self.assertIn(f"VERSION_BUMP {old_ver} -> {expected_new}", res.stdout)
            self.assertIn("EXPORTED-FROM: media-mcp ", res.stdout)
            self.assertEqual(res.stdout.strip().splitlines()[-1], "NEXT: review git diff, run tests/run-offline-tests.sh, commit")

            dst_file = kit_repo / "plugins/vagaa-media/skills" / target_rel
            self.assertEqual(dst_file.read_text(encoding="utf-8"), src_file.read_text(encoding="utf-8"))
            self.assertEqual(_read_three_versions(kit_repo), (expected_new, expected_new, expected_new))

            cv = subprocess.run(
                ["python3", str(kit_repo / "tests/check_versions.py"), "all", str(kit_repo), "HEAD"],
                capture_output=True,
                text=True,
                timeout=10,
            )
            self.assertEqual(cv.returncode, 0, cv.stdout + cv.stderr)

            changed = {
                line.strip()
                for line in _git(kit_repo, "diff", "--name-only").stdout.splitlines()
                if line.strip()
            }
            self.assertEqual(_git(kit_repo, "ls-files", "--others", "--exclude-standard").stdout.strip(), "")
            self.assertEqual(
                changed,
                {
                    ".claude-plugin/marketplace.json",
                    "plugins/vagaa-media/.claude-plugin/plugin.json",
                    "plugins/vagaa-media/README.md",
                    "plugins/vagaa-media/skills/EXPORTED-FROM",
                    f"plugins/vagaa-media/skills/{target_rel}",
                },
            )
            for meta in (
                ".claude-plugin/marketplace.json",
                "plugins/vagaa-media/.claude-plugin/plugin.json",
                "plugins/vagaa-media/README.md",
            ):
                numstat = _git(kit_repo, "diff", "--numstat", "--", meta).stdout.strip()
                self.assertTrue(numstat.startswith("1\t1\t"), f"{meta}: {numstat}")

    def test_c_idempotent_on_rerun_and_second_edit_without_commit(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit_repo, media_repo, tmpdir = _build_workspace(Path(tmp))
            old_ver, _, _ = _read_three_versions(kit_repo)
            expected_new = _bump_patch(old_ver)

            f1 = media_repo / "skills_fixture/video-prompting/SKILL.md"
            f1.write_text(f1.read_text(encoding="utf-8") + "\n<!-- edit 1 -->\n", encoding="utf-8")
            res1 = _run_sync(kit_repo, [str(media_repo)], tmpdir=tmpdir)
            self.assertEqual(res1.returncode, 0, res1.stderr)
            self.assertIn(f"VERSION_BUMP {old_ver} -> {expected_new}", res1.stdout)

            # Re-run without committing when content already matches -> unchanged
            res2 = _run_sync(kit_repo, [str(media_repo)], tmpdir=tmpdir)
            self.assertEqual(res2.returncode, 0, res2.stderr)
            self.assertIn("SKILLS_CONTENT unchanged", res2.stdout)
            self.assertIn("VERSION_BUMP none", res2.stdout)
            self.assertEqual(_read_three_versions(kit_repo), (expected_new, expected_new, expected_new))

            # Modify source again without committing -> syncs copy, does NOT bump a second time
            f2 = media_repo / "skills_fixture/music-and-sfx/SKILL.md"
            f2.write_text(f2.read_text(encoding="utf-8") + "\n<!-- edit 2 -->\n", encoding="utf-8")
            res3 = _run_sync(kit_repo, [str(media_repo)], tmpdir=tmpdir)
            self.assertEqual(res3.returncode, 0, res3.stderr)
            self.assertIn("SKILLS_CONTENT changed 1 files", res3.stdout)
            self.assertIn(f"VERSION_BUMP already {expected_new}", res3.stdout)
            self.assertEqual(_read_three_versions(kit_repo), (expected_new, expected_new, expected_new))
            self.assertEqual(
                (kit_repo / "plugins/vagaa-media/skills/music-and-sfx/SKILL.md").read_text(encoding="utf-8"),
                f2.read_text(encoding="utf-8"),
            )

    def test_d_check_mode_reports_changes_exits_1_and_leaves_repo_clean(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit_repo, media_repo, tmpdir = _build_workspace(Path(tmp))
            rel = "storyboard-longform/SKILL.md"
            f = media_repo / "skills_fixture" / rel
            f.write_text(f.read_text(encoding="utf-8") + "\n<!-- drift -->\n", encoding="utf-8")

            res = _run_sync(kit_repo, [str(media_repo), "--check"], tmpdir=tmpdir)
            self.assertEqual(res.returncode, 1, res.stderr)
            self.assertIn("SKILLS_CONTENT changed 1 files", res.stdout)
            self.assertIn(f"M {rel}", res.stdout)
            self.assertEqual(_git(kit_repo, "status", "--porcelain").stdout.strip(), "")

    def test_e_deleted_source_file_is_reported_and_deleted_from_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit_repo, media_repo, tmpdir = _build_workspace(Path(tmp))
            rel = "_shared/provenance.md"
            (media_repo / "skills_fixture" / rel).unlink()

            chk = _run_sync(kit_repo, [str(media_repo), "--check"], tmpdir=tmpdir)
            self.assertEqual(chk.returncode, 1, chk.stderr)
            self.assertIn(f"D {rel}", chk.stdout)

            res = _run_sync(kit_repo, [str(media_repo)], tmpdir=tmpdir)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertFalse((kit_repo / "plugins/vagaa-media/skills" / rel).exists())

    def test_f_same_length_and_same_mtime_content_change_is_detected(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit_repo, media_repo, tmpdir = _build_workspace(Path(tmp))
            rel = "_shared/media-inputs.md"
            src = media_repo / "skills_fixture" / rel
            dst = kit_repo / "plugins/vagaa-media/skills" / rel

            raw = src.read_bytes()
            flipped = bytes([raw[0] ^ 0x01]) + raw[1:]
            self.assertEqual(len(flipped), len(raw))
            src.write_bytes(flipped)

            st = dst.stat()
            os.utime(src, ns=(st.st_atime_ns, st.st_mtime_ns))
            self.assertEqual(src.stat().st_size, dst.stat().st_size)
            self.assertEqual(src.stat().st_mtime_ns, dst.stat().st_mtime_ns)

            res = _run_sync(kit_repo, [str(media_repo), "--check"], tmpdir=tmpdir)
            self.assertEqual(res.returncode, 1, res.stderr)
            self.assertIn(f"M {rel}", res.stdout)

    def test_g_preexisting_three_way_version_mismatch_exits_2_without_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit_repo, media_repo, tmpdir = _build_workspace(Path(tmp))
            src = media_repo / "skills_fixture/media-production/SKILL.md"
            src.write_text(src.read_text(encoding="utf-8") + "\n<!-- change -->\n", encoding="utf-8")

            rm_path = kit_repo / "plugins/vagaa-media/README.md"
            # the mismatch is made from whatever version the repository is on today, never from a literal:
            # a literal here goes stale on the very next bump and the case silently stops testing anything
            rm_text = rm_path.read_text(encoding="utf-8")
            rm_bad, n = re.subn(r"(\|\s*Plugin version\s*\|\s*\*\*)[0-9]+\.[0-9]+\.[0-9]+(\*\*)", r"\g<1>0.0.1\g<2>", rm_text)
            self.assertEqual(n, 1, "the README has no Plugin version row to break")
            self.assertNotEqual(rm_bad, rm_text)
            rm_path.write_text(rm_bad, encoding="utf-8")
            before_diff = _git(kit_repo, "diff").stdout

            res = _run_sync(kit_repo, [str(media_repo)], tmpdir=tmpdir)
            self.assertEqual(res.returncode, 2, res.stdout + res.stderr)
            self.assertEqual(_git(kit_repo, "diff").stdout, before_diff)
            self.assertEqual(_git(kit_repo, "ls-files", "--others", "--exclude-standard").stdout.strip(), "")

    def test_h_export_failure_propagates_error_exits_2_and_cleans_tmpdir(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit_repo, media_repo, tmpdir = _build_workspace(Path(tmp))
            res = _run_sync(
                kit_repo,
                [str(media_repo)],
                tmpdir=tmpdir,
                extra_env={"STUB_FAIL_CODE": "3", "STUB_FAIL_MSG": "!! stub exploded at export"},
            )
            self.assertEqual(res.returncode, 2)
            self.assertIn("!! stub exploded at export", res.stderr)
            self.assertEqual(_git(kit_repo, "status", "--porcelain").stdout.strip(), "")
            self.assertEqual(list(tmpdir.iterdir()), [])

    def test_check_truncates_output_at_40_lines(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit_repo, media_repo, tmpdir = _build_workspace(Path(tmp))
            extra_dir = media_repo / "skills_fixture/extra"
            extra_dir.mkdir()
            for i in range(43):
                (extra_dir / f"file_{i:02d}.md").write_text(f"item {i}\n", encoding="utf-8")

            res = _run_sync(kit_repo, [str(media_repo), "--check"], tmpdir=tmpdir)
            self.assertEqual(res.returncode, 1)
            lines = res.stdout.strip().splitlines()
            self.assertEqual(lines[0], "SKILLS_CONTENT changed 43 files")
            self.assertEqual(len(lines), 42)  # header + 40 entries + "... +3 more"
            self.assertEqual(lines[-1], "… +3 more")

    def test_version_flag_forwarded_and_bad_args_exit_2(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit_repo, media_repo, tmpdir = _build_workspace(Path(tmp))
            rec = Path(tmp) / "recorded_args.txt"
            res = _run_sync(
                kit_repo,
                [str(media_repo), "--version", "0.9.59", "--check"],
                tmpdir=tmpdir,
                extra_env={"STUB_RECORD_ARGS": str(rec)},
            )
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(rec.read_text(encoding="utf-8").splitlines(), ["--version", "0.9.59"])

            bad = _run_sync(kit_repo, [str(media_repo), "--bogus"], tmpdir=tmpdir)
            self.assertEqual(bad.returncode, 2)
            self.assertIn("usage:", bad.stderr)


if __name__ == "__main__":
    unittest.main()
