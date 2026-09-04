---
name: web-budget
description: Report the web-evidence router's provider quota and budget, or explain why the compact surface cannot
---

# Web-evidence budget

Report how much free provider quota is left on the web-evidence router.

1. If a `budget_status` tool is present in this session (the router's standard six-tool surface),
   call it with no arguments and report, per provider: quota used and remaining for the window,
   whether the provider is currently open or tripped, and the total spend — which should be `$0.00`,
   because the router is free-first with a hard cap and never selects a paid provider on its own.
   If `provider_status` is also present and the budget output leaves a provider's state unclear,
   you may call it once.
2. If the only web tool in this session is `web_evidence`, the plugin is pointed at the **compact**
   surface (`/mcp-compact`), which exposes exactly one tool by design so chat models stop calling
   three near-synonyms per turn. `budget_status` is not reachable from there. Say that plainly, and
   give the two ways out:
   - run `/plugin`, open vagaa-web-evidence, and change `nole_mcp_url` from `.../mcp-compact` to `.../mcp` to
     get the six-tool surface (this also re-exposes `search`, `extract`, `search_and_extract`,
     `research` and `provider_status`, which is exactly the confusion the compact surface avoids —
     so switch back afterwards if the one-tool discipline is what you want); or
   - ask the operator, who can read the same numbers from the router's own budget endpoint.
   Do **not** call `web_evidence` to work around this. It would spend the very quota being asked
   about, and it cannot answer the question.
3. Never print a token, and never invent numbers. If neither tool is available, say the
   `web-evidence` server is not connected and stop.
