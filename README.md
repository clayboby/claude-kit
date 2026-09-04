# claude-kit

Claude Code plugins and skills maintained by clayboby, published as a plugin marketplace.

```
/plugin marketplace add clayboby/claude-kit
/plugin install vagaa-dgx@claude-kit
```

Nothing in this repository contains an address, a token or a hostname of a private deployment: every
plugin reads its endpoints and credentials from `userConfig` at install time. Tokens are declared
`sensitive`, so Claude Code keeps them in the OS keychain (or `~/.claude/.credentials.json`) rather
than in any settings file you might commit.

| Plugin | What it gives Claude Code |
|---|---|
| [`vagaa-dgx`](plugins/vagaa-dgx) | MCP servers for a media cluster (video/image/music/speech/translation/asset library) and a web-evidence router, the skills that teach the workflows, a session-start reachability check, and status commands |

## Configuring vagaa-dgx

Claude Code prompts for these at install time; `/plugin` → **vagaa-dgx** edits them later.

| Key | Required | Example | What it is |
|---|---|---|---|
| `media_mcp_url` | yes | `https://media.example.com/mcp` | Streamable-HTTP MCP endpoint of your media gateway |
| `media_mcp_token` | yes, sensitive | — | Bearer token for the media gateway |
| `nole_mcp_url` | yes | `https://search.example.com/mcp-compact` | Web-evidence router. `/mcp-compact` gives one tool; `/mcp` gives six |
| `nole_token` | yes, sensitive | — | Bearer token for the router — a different secret from the media one |

The URLs become each MCP server's `url`, and the tokens become its `Authorization: Bearer …` header.
See [the plugin README](plugins/vagaa-dgx/README.md) for the tool surface, the hooks and the update
procedure.

## Local development

```bash
claude --plugin-dir ./plugins/vagaa-dgx        # load a plugin without installing it
claude plugin validate ./plugins/vagaa-dgx --strict
claude plugin validate . --strict              # the marketplace manifest
```

## Skills that live elsewhere on purpose

- Midscene automation skills (browser / android / ios / desktop, vitest-midscene-e2e): install from Midscene's own marketplace.
- `find-skills`: install from skills.sh.
- Company-internal skills (agent fleet, config-center, council review): private repositories.

## License

MIT.
