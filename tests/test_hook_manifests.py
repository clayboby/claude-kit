"""Execute the shipped manifests using Claude Code's command/args hook contract."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
import check_versions  # noqa: E402


def _run_asset_notify(payload, gateway_url="https://media.example.com/mcp"):
    env = {k: v for k, v in os.environ.items() if not k.startswith(("CLAUDE_PLUGIN_OPTION_", "SEMA_PLUGIN_OPTION_"))}
    env["CLAUDE_PLUGIN_OPTION_MEDIA_MCP_URL"] = gateway_url
    return subprocess.run(
        ["bash", str(ROOT / "plugins/vagaa-media/scripts/asset-notify.sh")],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        env=env,
        timeout=5,
    )


class HookManifestTests(unittest.TestCase):
    def test_manifest_hooks_execute_scripts_with_json_stdin(self):
        for plugin in ("vagaa-media", "vagaa-web-evidence"):
            with tempfile.TemporaryDirectory(prefix="plugin path with spaces ") as tmp:
                root = Path(tmp) / plugin
                root.symlink_to(ROOT / "plugins" / plugin, target_is_directory=True)
                hooks = json.loads((root / "hooks/hooks.json").read_text())["hooks"]
                for event, groups in hooks.items():
                    for group in groups:
                        for hook in group["hooks"]:
                            with self.subTest(plugin=plugin, event=event):
                                env = {k: v for k, v in os.environ.items() if not k.startswith(("CLAUDE_PLUGIN_OPTION_", "SEMA_PLUGIN_OPTION_"))}
                                env["CLAUDE_PLUGIN_ROOT"] = str(root)
                                env["CLAUDE_PLUGIN_OPTION_MEDIA_MCP_URL"] = "https://media.example.com/mcp" if event == "PostToolUse" else ""
                                payload = {"hook_event_name": event, "source": "resume", "tool_response": {"asset_url": "https://media.example.com/assets/as-0123456789ab"}}
                                expand = lambda s: s.replace("${CLAUDE_PLUGIN_ROOT}", str(root))
                                if "args" in hook:
                                    command = [expand(hook["command"]), *map(expand, hook["args"])]
                                else:
                                    command = ["bash", "-c", expand(hook["command"])]
                                result = subprocess.run(command, input=json.dumps(payload), text=True, capture_output=True, env=env, timeout=15)
                                self.assertEqual(result.returncode, 0, result.stderr)
                                if event == "SessionStart":
                                    self.assertIn("not configured", result.stdout)
                                else:
                                    self.assertIn("as-0123456789ab", json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"])

    def test_fetch_matcher_covers_both_server_names_and_director_outputs(self):
        hooks = json.loads((ROOT / "plugins/vagaa-media/hooks/hooks.json").read_text())
        pattern = re.compile(hooks["hooks"]["PostToolUse"][0]["matcher"])
        for prefix in ("mcp__media__", "mcp__plugin_vagaa-media_media__"):
            for name in ("video_fetch", "image_fetch", "music_fetch", "storyboard_fetch", "director_fetch", "workflow_fetch", "tts"):
                self.assertIsNotNone(pattern.search(prefix + name), prefix + name)
        for name in (
            "mcp__unrelated__video_fetch",
            "x_mcp__media__video_fetch",
            "mcp__media__video_fetch_extra",
            "mcp__media__video_submit",
            "mcp__media__tts_extra",
            "mcp__media__embed_batch_fetch",
            "mcp__plugin_vagaa-media_media__embed_batch_fetch",
        ):
            self.assertIsNone(pattern.search(name), name)

    def test_plugin_versions_match_across_plugin_json_marketplace_and_readme(self):
        errors = check_versions.check_three_way_consistency(ROOT)
        self.assertEqual(errors, [], "; ".join(errors))

    def test_marketplace_duplicate_plugin_entry_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_root = Path(tmp)
            shutil.copytree(ROOT / ".claude-plugin", fake_root / ".claude-plugin")
            shutil.copytree(ROOT / "plugins", fake_root / "plugins")
            mpath = fake_root / ".claude-plugin/marketplace.json"
            doc = json.loads(mpath.read_text(encoding="utf-8"))
            stale = dict(doc["plugins"][0], version="0.4.5")
            doc["plugins"].insert(0, stale)
            mpath.write_text(json.dumps(doc), encoding="utf-8")

            errors = check_versions.check_three_way_consistency(fake_root)
            self.assertTrue(any("duplicate" in e for e in errors), errors)

    def test_skills_export_bump_check_against_base_ref(self):
        status, detail = check_versions.check_skills_bump_against_base(ROOT)
        if status == "skip":
            print(f"[skills-bump] {detail}", file=sys.stderr)
        self.assertIn(status, ("ok", "skip"), detail)

    def test_skills_export_bump_check_fails_without_bump_and_skips_missing_ref(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            pj = repo / "plugins/vagaa-media/.claude-plugin/plugin.json"
            pj.parent.mkdir(parents=True)
            pj.write_text(json.dumps({"name": "vagaa-media", "version": "0.4.8"}), encoding="utf-8")
            marker = repo / "plugins/vagaa-media/skills/EXPORTED-FROM"
            marker.parent.mkdir(parents=True)
            marker.write_text("media-mcp 0.9.56\n", encoding="utf-8")

            def git(*args):
                r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, timeout=10)
                self.assertEqual(r.returncode, 0, r.stderr)

            git("init", "-b", "main")
            git("config", "user.name", "test")
            git("config", "user.email", "test@example.com")
            git("add", ".")
            git("commit", "-m", "base")

            # Missing ref -> explicit skip
            st_skip, msg_skip = check_versions.check_skills_bump_against_base(repo, base_ref="refs/heads/no-such-ref")
            self.assertEqual(st_skip, "skip", msg_skip)
            self.assertIn("not available", msg_skip)

            # Skills changed without version bump -> fail
            marker.write_text("media-mcp 0.9.57\n", encoding="utf-8")
            st_fail, msg_fail = check_versions.check_skills_bump_against_base(repo, base_ref="main")
            self.assertEqual(st_fail, "fail", msg_fail)

            # Bumping patch version -> ok
            pj.write_text(json.dumps({"name": "vagaa-media", "version": "0.4.9"}), encoding="utf-8")
            st_ok, msg_ok = check_versions.check_skills_bump_against_base(repo, base_ref="main")
            self.assertEqual(st_ok, "ok", msg_ok)

    def test_tts_completed_mcp_text_block_relays_only_stable_asset_url(self):
        body = {
            "job_id": "tts-001",
            "service": "tts",
            "status": "completed",
            "url": "https://media.example.com/presigned/tts-001.wav?X-Amz-Signature=deadbeef",
            "asset_id": "as-tts000001",
            "asset_url": "https://media.example.com/assets/as-tts000001",
        }
        payload = {
            "hook_event_name": "PostToolUse",
            "tool_name": "mcp__plugin_vagaa-media_media__tts",
            "tool_response": {"content": [{"type": "text", "text": json.dumps(body)}]},
        }
        result = _run_asset_notify(payload)
        self.assertEqual(result.returncode, 0, result.stderr)
        ctx = json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"]
        self.assertIn("https://media.example.com/assets/as-tts000001", ctx)
        self.assertNotIn("presigned", ctx)
        self.assertNotIn("X-Amz-Signature", ctx)

    def test_tts_queued_with_asset_url_json_in_params_text_stays_silent(self):
        body = {
            "job_id": "tts-queued-1",
            "service": "tts",
            "status": "queued",
            "url": None,
            "params": {
                "text": json.dumps({"asset_url": "https://media.example.com/assets/as-fakequeued1"}),
                "voice": "cloud-cherry",
            },
            "message": "cloud tts job is queued; the slot was busy",
        }
        payload = {
            "hook_event_name": "PostToolUse",
            "tool_name": "mcp__plugin_vagaa-media_media__tts",
            "tool_response": {"content": [{"type": "text", "text": json.dumps(body)}]},
        }
        result = _run_asset_notify(payload)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "", result.stdout)

    def test_image_fetch_ignores_asset_url_inside_prompt_and_reports_only_real_artifact(self):
        body = {
            "job_id": "image-001",
            "service": "image",
            "status": "completed",
            "prompt": json.dumps({"asset_url": "https://media.example.com/assets/as-promptfake1"}),
            "params": {"prompt": json.dumps({"asset_url": "https://media.example.com/assets/as-paramfake01"})},
            "url": "https://media.example.com/presigned/image-001.png?sig=abc",
            "asset_id": "as-realimg001",
            "asset_url": "https://media.example.com/assets/as-realimg001",
        }
        payload = {
            "hook_event_name": "PostToolUse",
            "tool_name": "mcp__plugin_vagaa-media_media__image_fetch",
            "tool_response": {"content": [{"type": "text", "text": json.dumps(body)}]},
        }
        result = _run_asset_notify(payload)
        self.assertEqual(result.returncode, 0, result.stderr)
        ctx = json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"]
        self.assertEqual(ctx.splitlines(), ["作品记录（需鉴权；浏览器请用 fetch 的 url）:https://media.example.com/assets/as-realimg001"])
        self.assertNotIn("as-promptfake1", ctx)
        self.assertNotIn("as-paramfake01", ctx)

    def test_malformed_port_does_not_hide_later_valid_assets(self):
        env = {**os.environ, "CLAUDE_PLUGIN_OPTION_MEDIA_MCP_URL": "https://media.example.com/mcp"}
        payload = {"tool_response": [{"asset_url": "https://media.example.com:invalid/assets/as-0123456789ab"},
                                     {"asset_url": "https://media.example.com/assets/as-abcdef012345"}]}
        result = subprocess.run(["bash", str(ROOT / "plugins/vagaa-media/scripts/asset-notify.sh")],
                                input=json.dumps(payload), capture_output=True, text=True, env=env, timeout=5)
        self.assertEqual(result.returncode, 0)
        context = json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"]
        self.assertIn("as-abcdef012345", context)
        self.assertNotIn("invalid", context)


if __name__ == "__main__":
    unittest.main()
