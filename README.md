# claude-kit

Claude Code plugins and skills maintained by clayboby, published as a plugin marketplace.

```
/plugin marketplace add clayboby/claude-kit
/plugin install vagaa-dgx@claude-kit
```

Nothing in this repository contains an address, a token or a hostname of a private deployment: every
plugin reads its endpoints and credentials from `userConfig` at install time.

| Plugin | What it gives Claude Code |
|---|---|
| `vagaa-dgx` | MCP servers for a media cluster (video/image/speech/translation/asset library) and a web-evidence router, the skills that teach the workflows, a session-start reachability check, and status commands |

## Skills that live elsewhere on purpose

- Midscene automation skills (browser / android / ios / desktop, vitest-midscene-e2e): install from Midscene's own marketplace.
- `find-skills`: install from skills.sh.
- Company-internal skills (agent fleet, config-center, council review): private repositories.
