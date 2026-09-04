# vagaa-media

Claude Code plugin for a self-hosted **media gateway**: generate video, images, music, speech and
translations, keep every result in an asset library, gate them on a vision review, and assemble long
video through a storyboard pipeline.

The plugin ships no address and no credential. The endpoint and the token are `userConfig` values you
fill in at install time; the token is `sensitive`, so Claude Code stores it in your OS keychain (or
`~/.claude/.credentials.json`) rather than in a settings file you might commit.

## Compatibility matrix

| | |
|---|---|
| Requires Claude Code | **≥ 2.1.259** (anchored hook matchers, `hookSpecificOutput.additionalContext`, `userConfig` env injection, hyphen-preserving MCP tool names) |
| Verified against | **media-mcp 0.3.5** |
| Platforms | **macOS, Linux.** Windows only through WSL or Git Bash — the hooks are bash scripts |
| Runtime dependencies | `bash`, `curl`, `python3` (no packages) |
| Tool surface | media-mcp 0.3.5 serves the **standard** surface only (`/mcp`, 28 tools). The compact surface (`/mcp-compact`) arrives in media-mcp 0.5; until then set `surface=standard` |

## What you get

| Component | What it does |
|---|---|
| MCP server `media` | `video_*`, `image_*`, `music_*`, `workflow_*`, `tts`, `translate`, `image_review`, `video_review`, `reverse_prompt`, `assets_search` / `asset_get` / `asset_tag`, `storyboard_*`, `presets_list`, `jobs_list` — 28 tools on the standard surface |
| Skill `media-production` | Search the library first, draft cheaply, review with the vision model, render the final on the same seed; the five-step storyboard pipeline for anything longer than one clip |
| Command `/vagaa-media:media-status` | Recent jobs, what is in flight, what is completed but not fetched. User-invoked only |
| Hook `SessionStart` | Health probe plus one authenticated `server/discover`, so a bad token, a bad URL and a down service are told apart before you waste a turn |
| Hook `PostToolUse` | After a media fetch, relays the stable `/assets/<id>` URL into the conversation |

## Install

```
/plugin marketplace add clayboby/claude-kit
/plugin install vagaa-media@claude-kit
```

`/plugin install vagaa-dgx@claude-kit` installs this plugin together with `vagaa-web-evidence`.

## Configuration

| Key | Type | Example | Notes |
|---|---|---|---|
| `media_mcp_url` | string, required | `https://media.example.com/mcp` | Streamable-HTTP MCP endpoint. Also the only origin the asset-link hook will relay a URL from |
| `media_mcp_token` | string, required, **sensitive** | — | Bearer token. Prefer a short-lived token scoped to the capabilities you actually use |
| `surface` | string, default `compact` | `standard` | Which surface the URL points at. Documentation and a session-start note only — it never rewrites the URL. With media-mcp 0.3.5, set `standard` |

The URL becomes the MCP server's `url` and the token its `Authorization: Bearer …` header. Nothing
else is sent. Tools appear as `mcp__plugin_vagaa-media_media__<tool>`.

## Hook behaviour

**`SessionStart` → `scripts/preflight.sh`.** Derives the health path from the configured MCP URL
(`…/mcp` or `…/mcp-compact` → `…/healthz`, falling back to `…/health`), probes it with a 3-second
timeout, then makes one authenticated MCP `server/discover` call — a metadata request that lists
nothing and runs no job. Four outcomes are reported separately, one line each: unreachable, token
rejected (401/403), no MCP endpoint (404), and answered but not with JSON-RPC. A JSON-RPC *error*
counts as reachable and authenticated, so a server that has not implemented `server/discover` is not
misreported as broken. When everything passes it prints nothing. It never prints the URL, the token
or any part of the response, writes no file, and always exits 0 — a down gateway never blocks a
session. The token reaches curl through a config file on stdin, so it is not visible in `ps`.

**`PostToolUse` → `scripts/asset-notify.sh`,** matcher anchored to
`^mcp__plugin_vagaa-media_media__(video_fetch|image_fetch|music_fetch|storyboard_fetch)$`. A tool
response is remote data, so a URL is relayed only when it is `http`/`https`, has no userinfo, query
or fragment, shares the **exact** origin (scheme, host and port) of the configured gateway, and has
a path matching `^/assets/[A-Za-z0-9_-]{6,64}(/.*)?$` with no `.` or `..` segments. Any control
character rejects the URL. At most 5 URLs and 1 KB reach the conversation, as one strict JSON
document:

```json
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"作品已入库:https://…/assets/<id>"}}
```

That field is the only PostToolUse output a model actually reads — a hook's plain stdout does not
reach it. The point is that the transcript keeps the **stable** library URL, not the 24-hour
presigned one.

Both hooks unset every `CLAUDE_PLUGIN_OPTION_*` variable whose name looks like a credential before
starting `python3`, so only the gateway URL crosses into the child process.

## Update

```
/plugin marketplace update claude-kit
/plugin update vagaa-media
```

Then `/reload-plugins`, or restart Claude Code. A plugin updated mid-session keeps serving the old
hooks and MCP connection until it is reloaded. Your configured URL and token survive an update.

## Develop

```bash
claude --plugin-dir ./plugins/vagaa-media
claude plugin validate ./plugins/vagaa-media --strict
bash tests/run-offline-tests.sh          # from the repository root; contacts nothing but 127.0.0.1
```

## License

MIT.
