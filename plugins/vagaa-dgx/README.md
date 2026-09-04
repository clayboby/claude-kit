# vagaa-dgx

A bundle. It ships no skills, no hooks, no commands and no MCP servers of its own — installing it
installs [`vagaa-media`](../vagaa-media) and [`vagaa-web-evidence`](../vagaa-web-evidence) together,
through the `dependencies` field of its manifest.

```
/plugin marketplace add clayboby/claude-kit
/plugin install vagaa-dgx@claude-kit
```

Claude Code then prompts for each dependency's own options. Install just one of the two instead if
you only want that half; a plugin required by an enabled dependent stays enabled.

## Compatibility matrix

| | |
|---|---|
| Requires Claude Code | **≥ 2.1.259** (plugin `dependencies` resolved against the declaring plugin's own marketplace) |
| Verified against | **media-mcp 0.3.5**, **Nólë v1.10.2+dgx.20260828.24** |
| Platforms | **macOS, Linux.** Windows only through WSL or Git Bash |
| Runtime dependencies | `bash`, `curl`, `python3` — from the two plugins it pulls in |

## What each half needs

| Plugin | Configuration |
|---|---|
| `vagaa-media` | `media_mcp_url`, `media_mcp_token` (sensitive), `surface` (`standard` \| `compact`) |
| `vagaa-web-evidence` | `nole_mcp_url`, `nole_credential` (sensitive), `profile` (`lan` \| `public`) |

The media token and the web-evidence credential are unrelated secrets, and within
`vagaa-web-evidence` the two profiles take different credentials again: 直连填服务令牌,公网填网关密钥,不可互换.

## Update

```
/plugin marketplace update claude-kit
/plugin update vagaa-dgx
```

Updating the bundle does not update its dependencies; update those by name, or update the
marketplace and let `/plugin` offer both.

## License

MIT.
