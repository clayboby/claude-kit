---
name: media-status
description: List recent media-gateway jobs and say which ones still need fetching
disable-model-invocation: true
---

# Recent media jobs

Call the media gateway's `jobs_list` tool and report what is in flight.

1. Call `jobs_list`. Arguments, if the user gave any in `$ARGUMENTS`:
   - a bare number becomes `limit` (default 20),
   - a word such as `video`, `image`, `music`, `workflow`, `tts` or `shot` becomes `service`,
   - a word such as `queued_local`, `queued`, `running`, `completed`, `failed` or `lost` becomes
     `status`.
   Anything you cannot map, ignore, and say so in one clause.
2. Render the result as a compact table, newest first: job id (short), service, preset, status,
   age, and whether an artifact is already stored.
3. Below the table, add at most three lines:
   - **completed but not fetched** — name those job ids and offer to call the matching `*_fetch`;
   - **running or queued** — say how many, and what the in-flight counters report;
   - **failed or lost** — name those job ids and their error, if the record carries one.
4. Do not call any generation tool, do not fetch anything, and do not poll in a loop. This command
   reads status once.

If the tool is missing from the session, the plugin's `media` server is not connected: tell the user
to run `/plugin` to check the vagaa-media options, or `/mcp` to reconnect, and stop there.
