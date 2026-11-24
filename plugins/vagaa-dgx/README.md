# vagaa-dgx

A bundle. It ships no skills, no hooks, no commands and no MCP servers of its own — installing it
installs [`vagaa-media`](../vagaa-media) and [`vagaa-web-evidence`](../vagaa-web-evidence) together,
through the `dependencies` field of its manifest.

## Install

### Claude Code (CC)

```
/plugin marketplace add clayboby/claude-kit
/plugin install vagaa-dgx@claude-kit
```

### sema

与 CC 共用同一个 GitHub 插件市场 `clayboby/claude-kit`（插件名 `vagaa-dgx@claude-kit`）；具体 sema 安装命令本仓未记录（**未核**）。

**The bundle install does not prompt for the two plugins' options** (checked with Claude Code
2.1.280): both arrive enabled but unconfigured, and their MCP servers do not start. Configure each
once: `/plugin` → **Installed** → *Vagaa Media* → **Configure options**, then the same for *Vagaa Web
Evidence*, then `/reload-plugins`. Until then `/mcp` reports "No MCP servers configured" and
`/plugin` → **Errors** lists `Plugin option "…" isn't set`; do not press Enter on that Errors row,
because its "resolve" action uninstalls the plugin rather than opening its options.

Installing either plugin on its own (`/plugin install vagaa-media@claude-kit`) does open its options
dialog. Install just one of the two instead if you only want that half; a plugin required by an
enabled dependent stays enabled.

## Compatibility matrix

| | |
|---|---|
| Plugin version | **0.3.6** |
| Requires Claude Code | **≥ 2.1.259** (plugin `dependencies` resolved against the declaring plugin's own marketplace) |
| Verified against | **media-mcp**（以 [`plugins/vagaa-media/skills/EXPORTED-FROM`](../vagaa-media/skills/EXPORTED-FROM) 为准，工具面与个数以 `capabilities` / `presets_list` 实时结果为准）、**Nólë v1.10.2+dgx.20260828.24** |
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

### Claude Code (CC)

```
/plugin marketplace update claude-kit
/plugin update vagaa-dgx
```

Updating the bundle does not update its dependencies; update those by name, or update the
marketplace and let `/plugin` offer both.

### sema

从同一插件市场 `clayboby/claude-kit` 刷新市场并更新 `vagaa-dgx` 及其依赖插件（具体 sema 更新命令本仓未记录，**未核**）。

## License

MIT.
