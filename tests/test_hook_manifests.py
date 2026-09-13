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
            for name in ("video_fetch", "image_fetch", "music_fetch", "storyboard_fetch", "director_fetch", "workflow_fetch"):
                self.assertIsNotNone(pattern.search(prefix + name), prefix + name)
        for name in ("mcp__unrelated__video_fetch", "x_mcp__media__video_fetch", "mcp__media__video_fetch_extra", "mcp__media__video_submit"):
            self.assertIsNone(pattern.search(name), name)

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
