---
name: media-production
description: Use to search or review media assets, create standalone images or video clips, or generate speech and translations through media-mcp; coordinate the draft, review, and final workflow and load specialist skills when needed.
verified_against: media-mcp 0.6.1 (2026-09-07)
shared_facts: ../_shared/cluster-facts.md
shared_facts_sha256: 7d364005ed4a335557afc36ef0b39191a9b81b3ecfc5b8b23c2d348fc91485d2
---

# Media production on the cluster (core loop)

All media work goes through the `media-mcp` MCP server. Node timings, preset tables, voices, limits and error codes live in
`../_shared/cluster-facts.md` — read it once per task, do not restate numbers from memory. Specialist skills: `video-prompting`
(writing / rewriting / A/B-testing a video prompt), `storyboard-longform` (multi-shot films, continuity, resume, assembly),
`image-edit-and-reference` (references, identity, edits), `music-and-sfx` (BGM, SFX, levels). This skill owns the loop
itself plus speech, translation, the asset library and job recovery.

## 1. Search the library before generating
- `assets_search(query="teapot steam", since="30d")`, `assets_search(query="seed:101 preset:draft")`, `assets_search(tags=["hero"], starred=true)`,
  `assets_search(min_score=4)`. Each hit has a STABLE `url` and a `thumb_url`; nothing expires the way presigned links do.
- `asset_get(asset_id)` returns the record + the job (prompt, seed, params, and since 0.6.0 `params.prompt_id` when the prompt came from
  `prompt_rewrite`) — enough to re-submit the same seed on a final preset without guessing. `presign=true` adds a 24 h URL.
- `asset_tag(asset_id, add=["hero","ep1"], starred=true, collection="game-art")` marks keepers; untagged drafts expire after 7 days.
- `asset_feedback_get(asset_id)` (0.5.1, needs `jobs.read`) returns the HUMAN verdict the operator gave in the console (`rating` good / ok / bad, reason tags, note, every rater, the history with a job-side snapshot); `assets_search(rating="bad")` lists the failure-case set, `rating="none"` what nobody rated yet. Prefer works rated `good` as references.
- A good hit ends the task: do not regenerate what the library already holds unless the user asks for a new take.

## 2. The loop: draft → review → final
1. **Draft cheaply.** `video_submit(prompt, preset="draft", seconds=5, seed=<fixed>)` or a lottery `seeds=[11, 12, 13, 14]` (≤ 8, one job per
   seed, spread over both nodes). Poll `video_status(job_id)` every 20–30 s; `progress` stays null on the ComfyUI lane — that is not "stuck".
   **Never end your turn while a job you submitted is still queued/running** — in a non-interactive run (`claude -p`, a hook, a script) there is
   no next turn: keep calling `video_status` (sleep 20–30 s between calls) until it is `completed` / `failed` / `lost`, then fetch and review.
   Prompt text: write it yourself (see `video-prompting`) or pass `prompt_id` from `prompt_rewrite`; `rewrite="auto"` on `draft` runs the
   deterministic check + rewrite for you and FAILS the call (nothing generated) when no valid prompt comes out. Leave `rewrite` unset to send
   your words untouched (the pre-0.6.0 behaviour). Optional `idempotency_key` makes a retried call replay the first answer instead of paying twice.
2. **Review, don't eyeball.** `video_review(job_id)` / `image_review(job_id)` → five 1–5 scores + `overall` + one suggestion from the Qwen vision
   lane; iterate until the bar you set (3.5 is the storyboard gate) is met. `reverse_prompt(source, style="h3"|"sd"|"plain")` describes an image.
3. **Final with the same seed.** Re-submit the approved text with the SAME seed on `fast` (everyday) or `quality` (one candidate, never iterate);
   a `prompt_id` written for `draft` is accepted unchanged on `fast`/`daily`/`quality` (same 5 s); anything else is refused, never re-rewritten.
4. **Fetch once.** `video_fetch(job_id)` → presigned URL + `asset_id` + stable `asset_url`; hand the stable URL on.
Images: `image_submit(prompt, preset="krea-default", seed, width, height)`; `krea-169` for a 16:9 first frame; poll `image_status(job_id)`, then `image_fetch(job_id)`.
Raw ComfyUI graphs: `workflow_submit(graph_json, overrides)` → `workflow_status` / `workflow_fetch` — ask the operator for a template first.

## 3. Speech and translation (synchronous, this skill's job)
- `tts(text, voice, lang)` → WAV asset. Voices are presets (`presets_list` → `tts_voices`): `default`, `calm`, `news`, `story-female`,
  `story-male`, `energetic`; ask for a new preset rather than inventing parameters. ≤ 4000 chars per call, one call per scene.
- `translate(text, dst="en", src=None)` via Hy-MT2; `dst` is the target language (default zh).
- Voice cloning (`voice_enroll`) and lip-sync (`lipsync`) are cloud-only tools that appear only when their entry is keyed — today none is.

## 4. Jobs, recovery, presets
- `jobs_list(limit, service, status)` for an overview; `presets_list` for the live presets / voices / models / cloud entries (`available` flag).
- `job_recover(job_id, action=attach|resubmit|abandon, backend_id)` (admin) resolves `submission_unknown`, `cancel_pending`,
  `cancel_unconfirmed`. **Never just re-submit such a job** — the node may be generating it; check the node, then attach / resubmit / abandon.
- Cloud presets (`presets_list` shows `cloud: true`): money. No lottery without being asked; a missing key is not retried.
- `compliance_review(source)` / `compliance_status(job_id)` = the licensed publish gate (cloud, only when keyed).

## 5. Etiquette
Always pass and record a `seed`. On `backend_unreachable` / `queue_full` wait and retry, never spam. `quality` is for one approved candidate.
When a tool this skill names is missing from the session, ask the user to run `/mcp` and reconnect `media-mcp` before working around it.
