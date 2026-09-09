# claude-kit

Claude Code plugins and skills maintained by clayboby, published as a plugin marketplace.

## 一键安装 / One-click install

Inside Claude Code (any project):

```
/plugin marketplace add clayboby/claude-kit
/plugin install vagaa-media@claude-kit
```

Or from a terminal, non-interactive (fills the options in one go — the token goes to the OS keychain, never a file):

```bash
claude plugin marketplace add clayboby/claude-kit
claude plugin install vagaa-media@claude-kit \
  --config media_mcp_url=https://<your-gateway>/mcp \
  --config media_mcp_token=<bearer token from the gateway console: Tokens → New> \
  --config surface=standard
claude plugin list          # shows version + enabled
```

Then start Claude Code and check: `/mcp` lists `media` as connected, and asking "list the media tools you have" returns
video / image / music / tts / storyboard / director tools. The session-start hook prints the gateway version it verified.

### Update

```bash
claude plugin marketplace update claude-kit      # refresh the catalog
claude plugin update vagaa-media@claude-kit      # e.g. 0.3.7 -> 0.3.8; restart Claude Code to apply
```

Skills carry a `verified_against: media-mcp <version>` stamp; the session-start hook warns when the gateway is newer than the skills.

Nothing in this repository contains an address, a token or a hostname of a private deployment: every
plugin reads its endpoints and credentials from `userConfig` at install time. Credentials are
declared `sensitive`, so Claude Code keeps them in the OS keychain (or `~/.claude/.credentials.json`)
rather than in any settings file you might commit.

| Plugin | Install | What it gives Claude Code |
|---|---|---|
| [`vagaa-media`](plugins/vagaa-media) | `/plugin install vagaa-media@claude-kit` | An MCP server for a media gateway (video, images, music, speech, translation, asset library), the skill that teaches the production workflow, a session-start reachability and credential check, and a hook that puts the stable asset link back into the conversation |
| [`vagaa-web-evidence`](plugins/vagaa-web-evidence) | `/plugin install vagaa-web-evidence@claude-kit` | An MCP server for a free-first web-evidence router, the skill that rations it to one call per turn, and the same session-start check |
| [`vagaa-dgx`](plugins/vagaa-dgx) | `/plugin install vagaa-dgx@claude-kit` | A bundle: no components of its own, just `dependencies` on the two above |

## Compatibility matrix

| | |
|---|---|
| Requires Claude Code | **≥ 2.1.259** |
| Verified against | **media-mcp 0.7.7** (`vagaa-media` 0.3.14: director console `director_run`, characters table, `refine=latent_upscale`), **Nólë v1.10.2+dgx.20260828.24** (`vagaa-web-evidence`) |
| Platforms | **macOS, Linux.** Windows only through WSL or Git Bash — the hooks are bash scripts |
| Runtime dependencies | `bash`, `curl`, `python3`; no packages, no network access beyond your own gateways |

## Configuration

Claude Code prompts for these when the plugin is enabled; `/plugin` → the plugin → **Options** edits
them later. Every value stays on your machine.

### vagaa-media

| Key | Required | Example | What it is |
|---|---|---|---|
| `media_mcp_url` | yes | `https://media.example.com/mcp` | Streamable-HTTP MCP endpoint of your media gateway. Also the only origin the asset-link hook will relay a URL from |
| `media_mcp_token` | yes, sensitive | — | Bearer token for the gateway |
| `surface` | no, default `standard` | `compact` | Which tool surface the URL points at. Documentation and a session-start note only. media-mcp 0.3.x serves only the standard surface; set `compact` once 0.5 ships `/mcp-compact` |

### vagaa-web-evidence

| Key | Required | Example | What it is |
|---|---|---|---|
| `nole_mcp_url` | yes | `https://search.example.com/mcp-compact` | Streamable-HTTP MCP endpoint. `/mcp-compact` gives one tool; `/mcp` gives six |
| `nole_credential` | yes, sensitive | — | 直连填服务令牌,公网填网关密钥,不可互换 — with `profile=lan` the router's own service token, with `profile=public` the gateway's API key. Different secrets; neither works at the other address |
| `profile` | yes | `public` | `lan` or `public`. Picks the wording of the session-start check and nothing else |

Each URL becomes its MCP server's `url`, and each credential becomes that server's
`Authorization: Bearer …` header. Nothing else is sent anywhere.

## Local development

```bash
claude --plugin-dir ./plugins/vagaa-media          # load a plugin without installing it
claude plugin validate ./plugins/vagaa-media --strict
claude plugin validate . --strict                  # the marketplace manifest
bash tests/run-offline-tests.sh                    # hook behaviour; contacts nothing but 127.0.0.1
```

`tests/run-offline-tests.sh` starts a stub gateway on `127.0.0.1:8792` and exercises the asset-link
allowlist, the anchored hook matcher and every branch of the session-start check. No real endpoint
is ever contacted.

## Skills that live elsewhere on purpose

- Midscene automation skills (browser / android / ios / desktop, vitest-midscene-e2e): install from Midscene's own marketplace.
- `find-skills`: install from skills.sh.
- Company-internal skills (agent fleet, config-center, council review): private repositories.

## License

MIT.
