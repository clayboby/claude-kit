---
name: media-production
description: How to produce video, image, music, speech and translation assets through the media gateway's MCP tools (H3 video with audio, Krea images, ACE-Step music and SFX, Qwen3-TTS speech, machine translation, vision review, asset library). Use whenever a task needs generated media.
---

# Media production through the media gateway

All media generation goes through this plugin's `media` MCP server. Its tools appear in the
session as `mcp__plugin_vagaa-dgx_media__<tool>`; this document calls them by their bare names:

`video_submit` / `video_status` / `video_fetch`, `image_submit` / `image_status` / `image_fetch`,
`music_submit` / `music_status` / `music_fetch`, `workflow_submit` / `workflow_status` /
`workflow_fetch`, `tts`, `translate`, `image_review`, `video_review`, `reverse_prompt`,
`assets_search` / `asset_get` / `asset_tag`, `storyboard_plan` / `storyboard_plan_get` /
`storyboard_plan_update` / `storyboard_run` / `storyboard_status` / `storyboard_fetch`,
`presets_list`, `jobs_list`.

Text and code chat do not go through it. If a tool listed here is missing from the session, ask the
user to run `/mcp` and reconnect the plugin's `media` server before working around it.

Everything asynchronous follows one shape: `*_submit` returns a `job_id` immediately, you poll
`*_status` until `completed | failed | lost`, then `*_fetch` returns the artifact. `tts` and
`translate` are synchronous.

## Search the library before generating

Every completed job is copied to object storage and indexed automatically (prompt, seed, preset,
size/seconds, review score, tags). Nobody has to call `*_fetch` for that to happen. So:

- **First look, then generate.** `assets_search(query="teapot steam", since="30d")`, or
  `assets_search(query="seed:101 preset:draft")`, `assets_search(tags=["hero"], starred=true)`,
  `assets_search(min_score=4)`. Each hit carries a **stable** `url` (`<gateway>/assets/<asset_id>`)
  and a `thumb_url`; those do not expire the way presigned links do.
- `asset_get(asset_id)` returns the full record plus the originating job (prompt, seed, params) —
  enough to re-submit the same seed at a higher preset without guessing. `presign=true` adds a 24 h
  presigned URL for tools that cannot send a bearer token.
- `asset_tag(asset_id, add=["hero","ep1"], starred=true, collection="game-art")` marks keepers.
  **Drafts expire after 7 days** unless starred or in a collection; other presets are kept. Tag what
  you would want to find again.
- `*_fetch` and `storyboard_fetch` also return `asset_id` / `asset_url` (per shot too). Pass those
  on instead of presigned links.

## The loop: draft → review → final

1. **Draft cheaply.** `video_submit(prompt, preset="draft", seconds<=4, seed=<fixed>)`. Draft is
   832x480, Turbo 8 steps, about 2 minutes. Submit several drafts (different seeds or prompt
   variants) back to back; they queue.
2. **Review, don't eyeball.** `video_review(job_id)` / `image_review(job_id)` returns a 5-axis score
   (prompt consistency, composition, artifacts, style, usability, each 1-5) plus one improvement
   hint from the cluster's Qwen3.8 vision model; `overall` is 1.0-5.0 with one decimal. Iterate on
   the prompt until the review clears the bar you set.
3. **Final with the same seed.** Re-submit the approved prompt with the **same seed** at
   `preset="fast"` (1344x768 Turbo 8 steps, ~5 min per 4 s, ~40 min per 15 s; the everyday
   deliverable) or `preset="quality"` (1344x768 base 20 steps, ~11 min per 4 s). `daily` is base 8
   steps without the Turbo look (~5 min per 4 s, ~36 min per 15 s).
4. **Fetch.** `video_fetch(job_id)` returns the presigned URL (24 h) plus `asset_id` and the stable
   `asset_url`. Hand the stable URL on; do not re-fetch in a loop.

Never iterate prompts at `quality`. Never submit more than one `quality` candidate at a time.

## Video facts (H3 video+audio model)

- 24 fps fixed; `seconds` 4-15; the server rounds frames up to the model's 17n+5 grid (4 s -> 107
  frames, 15 s -> 362).
- Output is video **with generated audio** (speech, ambience). Put dialogue in quotes in the prompt
  and name the language.
- 16:9 at short edge 768 is the tuned resolution; `draft` uses short edge 480.
- One job at a time per GPU, shared with image jobs. A 15 s clip is ~36-40 min on either `daily` or
  `fast` (Turbo's speed-up fades on long clips). Plan batches accordingly, poll `video_status` every
  60 s, or watch `jobs_list`.
- Prompt shape: subject + action + camera + lighting + audio cue. English and Chinese both work.

## Images

- `image_submit(prompt, preset="krea-default", seed, width, height)`; 1024x1024, 8 steps, CFG 1,
  about 15 s warm. For a 16:9 video first frame use `preset="krea-169"` (1344x768, same Turbo 8
  steps) so the frame already matches `fast` / `quality`.
- For anything the presets do not cover, `workflow_submit(graph_json, overrides)` runs a raw ComfyUI
  API-format graph. Ask the operator for a template rather than inventing node ids.

## Speech and translation (synchronous)

- `tts(text, voice, lang)` returns a WAV asset. Voices are presets (`presets_list` -> tts voices):
  `default` (plain), `calm` (audiobook), `news` (anchor), `story-female` / `story-male` (drama and
  fight scenes), `energetic` (short-video hook). Each preset is a built-in speaker plus a free-text
  style instruction; ask for a new preset rather than inventing parameters.
- Speed is roughly 0.75x real time per sentence; long text is split into sentences and batch
  decoded, so a 60 s narration returns in 10-20 s. Keep one call under ~4000 characters; for a whole
  episode send one call per scene so seams fall on scene cuts.
- Voice cloning exists on the service but is not exposed as an MCP tool; ask before relying on it.
- `translate(text, dst="en", src=None)` — `dst` is the target language (default zh), `src` is
  optional and auto-detected.

## Seed lottery

- `video_submit(prompt, preset="draft", seconds<=4, seeds=[11, 12, 13, 14])` — or `n=4` with a base
  `seed` — creates **one job per seed** and spreads them across the render lanes by current queue
  depth. The result is `{"batch": true, "job_ids": [...], "count", "requested"}`; if some seeds could
  not be queued it carries `partial: true` plus `failed`. Poll each `job_id` with `video_status`,
  review the winners with `video_review`, then re-submit **only the chosen seed** at `fast` /
  `quality`.
- Max 8 seeds per call. A lottery at `quality` is never worth it: draft first, final once.
- Each job records the lane it ran on (`backend`); `video_fetch` and cancellation follow the job
  automatically. Some presets pin a lane.

## Reverse-prompting an image

- `reverse_prompt(source=<job_id or allowlisted URL>, style="sd")` returns a Krea-ready tag prompt
  plus `negative_prompt`; `style="h3"` returns a cinematic paragraph plus an `audio` line for
  `video_submit`; `style="plain"` returns a prose description (`lang="zh"` for Chinese notes).
  Feed `prompt` straight into `image_submit` / `video_submit` and keep the same seed discipline.
- URL sources are restricted to the gateway's fetch allowlist. If a URL is rejected, submit the
  `job_id` instead.

## Music and sound effects

- **BGM**: `music_submit(prompt=<style/instrument/mood tags>, preset="bgm-draft", seconds=30,
  seed=<fixed>, bpm=<int>, key="A minor")` -> poll `music_status` -> `music_fetch` (MP3). Draft is
  30 s and cheap: run a lottery (`seeds=[...]`, max 8), pick by ear against a rubric, then re-submit
  the **same prompt + seed + bpm + key** at `preset="bgm-final"` with the real length (60-300 s,
  lossless FLAC). Never lottery at `bgm-final`.
- **Lyrics**: omit `lyrics` (or pass `instrumental=true`) for instrumental game music; otherwise
  pass `[Verse]` / `[Chorus]`-tagged lyrics and let the text carry the language.
- **SFX**: `music_submit(prompt=<describe the sound, not music>, preset="sfx", seconds=2..8,
  seed=<fixed>)` -> FLAC. No lyrics, bpm or key. A multi-seed lottery is normal for SFX. For loops,
  ask for "seamless loop" in the prompt and cross-fade in your editor; the model does not guarantee
  sample-exact loops.
- Limits: BGM 1-600 s, SFX 1-60 s. The music models live on one render lane only, so music jobs
  queue behind any long video job there. Submit BGM and SFX first, or accept the wait. Record seeds;
  the same preset plus seed is deterministic.

## Which lane does what

The gateway has two render lanes and picks between them for you. What matters when you plan:

- **The quick lane** takes first-frame images, 4 s `draft` lotteries and reverse prompts. Timing is
  predictable (models reload every job: image ~30 s, 4 s draft ~2 min) and it is never blocked
  behind a 15 s render. Presets `krea-default` and `draft` prefer it.
- **The long-form lane** is pinned for `fast` / `daily` / `quality` up to 15 s. A 15 s clip holds
  that GPU for ~36 min, so never queue an image or a draft behind it.
- Each lane executes its queue serially: an image queued behind a running video job waits for the
  whole job (measured: +250 s). If you need an image while a long clip renders, it goes to the quick
  lane automatically.
- Storyboard shots are capped at 6 s and may run on the quick lane. The final render of an approved
  plan uses `preset="quality"`.
- Worked example: `image_submit(preset="krea-169")` -> pick a frame -> `video_submit(..., seeds=[...])`
  4 s drafts -> `video_review` -> storyboard `continue` shots from the chosen last frame -> one
  `quality` final.

## Etiquette

- Always pass a `seed` and record it; determinism is guaranteed for the same preset plus seed.
- Use `presets_list` when unsure what exists. Presets are hot-reloaded and may grow — new models
  arrive as new presets, the tools stay the same.
- On `backend_unreachable` or `queue_full`, wait and retry; do not spam submits.
- Errors come back as `<code>: <detail>`, where code is one of `backend_unreachable`,
  `backend_timeout`, `backend_rejected`, `backend_error`, `storage_error`, `invalid_preset`,
  `invalid_argument`, `queue_full`, `job_not_found`, `forbidden` (your token lacks that capability
  scope) or `limit_exceeded` (per-token quota). A job's own `failed` / `lost` status is a normal
  return value, not an error.

## Long videos: the storyboard pipeline

For anything longer than one 15 s clip, do not chain `video_submit` by hand. Use the storyboard
tools: one clip per shot, auto-continuation, review gates, assembly.

1. **Plan.** `storyboard_plan(text, style?, characters?, target_seconds?, shot_seconds=5, language?)`.
   - Feed a **novel chapter** as-is (up to ~60k characters; split longer chapters by scene). Feed a
     **shot script** as free text (one paragraph per shot works well) or as ready JSON
     (`{"shots":[{"seconds","prompt","camera","characters","dialogue","transition"}],
     "characters":{...}}`; JSON skips the planner LLM). A **one-line brief** also works, but then
     give `target_seconds`.
   - Pass `characters={name: {appearance}}` when you already know the cast. The planner keeps the
     names and repeats the sheet in every shot; that is what keeps faces and clothes stable.
   - Read `plan.shots[*]` and `shot_prompts` (the exact rendered prompts). Fix wrong beats, split
     shots whose dialogue does not fit (~3 words/s, 1 s of silence at each end), and set
     `transition: continue` only when the next shot really continues in the same place. Then
     `storyboard_plan_update(plan_id, plan)`. `warnings` lists what the validator changed.
2. **Run.** `storyboard_run(plan_id, preset="fast", seed=<fixed>)` returns a `run_id` immediately.
   Budget ~5 min per 5 s shot at `fast`, ~13 min at `quality`, times attempts. Poll
   `storyboard_status(run_id)` every 60-120 s; `stage` says which shot is rendering and
   `progress.eta_s` extrapolates from finished shots.
3. **Read the score table.** Each shot carries `review_overall` (vision score 1-5), `attempts`,
   `seam_ssim` / `seam_ok`, `drop_frames`, `below_threshold` and `notes`. A shot with
   `below_threshold: true` was kept as the best of its attempts: read its `review_summary`, fix the
   prompt in the plan, and rerun that shot. `storyboard_run(plan_id, resume_run_id=<run>)`
   regenerates only shots that are not `done`; to force a redo of a done shot, change its `seconds`
   or edit it into a new plan. `seams_cut` in the report lists continuations that were downgraded to
   hard cuts because the seam did not match.
4. **Fetch.** `storyboard_fetch(run_id)` gives the final mp4 URL, each shot's clip and last-frame
   URL, and `report{duration_s, frames, retries}`. Every shot is also an ordinary job
   (`jobs_list(service="shot")`, `video_review(job_id)`).

When to use `quality`: only for the final render of an approved plan whose `fast` run scored well.
It does not fix planning problems, it only sharpens. Use `continuity="cut"` for montage or
multi-location pieces (no seams to protect), `fl2v` (the default) for continuous action, and `guide`
only as an experiment on continuous action with camera motion (it falls back to `fl2v` if the
backend rejects it). `review_threshold=0` disables the vision gate when the review endpoint is busy.
Keep `target_seconds` at or below 180 (server cap), and expect roughly 1 h of GPU time per minute of
film at `fast`.
