"""Execute the shipped manifests using Claude Code's command/args hook contract."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


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
        marketplace = json.loads((ROOT / ".claude-plugin/marketplace.json").read_text())
        market_versions = {p["name"]: p["version"] for p in marketplace["plugins"]}
        plugin_dirs = sorted(p.name for p in (ROOT / "plugins").iterdir() if p.is_dir())
        self.assertEqual(set(market_versions), set(plugin_dirs))

        semver_re = re.compile(r"^\d+\.\d+\.\d+$")
        readme_ver_re = re.compile(r"^\|\s*Plugin version\s*\|\s*\*\*([0-9]+\.[0-9]+\.[0-9]+)\*\*\s*\|$", re.MULTILINE)
        for name in plugin_dirs:
            with self.subTest(plugin=name):
                plugin_json = json.loads((ROOT / "plugins" / name / ".claude-plugin/plugin.json").read_text())
                p_ver = plugin_json["version"]
                m_ver = market_versions[name]
                readme = (ROOT / "plugins" / name / "README.md").read_text()
                matches = readme_ver_re.findall(readme)
                self.assertRegex(p_ver, semver_re)
                self.assertEqual(len(matches), 1, f"{name}/README.md must declare Plugin version once")
                r_ver = matches[0]
                self.assertEqual(p_ver, m_ver, f"{name}: plugin.json ({p_ver}) != marketplace.json ({m_ver})")
                self.assertEqual(p_ver, r_ver, f"{name}: plugin.json ({p_ver}) != README.md ({r_ver})")

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
