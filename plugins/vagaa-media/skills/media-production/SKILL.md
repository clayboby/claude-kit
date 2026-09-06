---
name: media-production
description: How to produce video, image, speech and translation assets on the ZhenBS DGX cluster through the media-mcp tools (H3 video, Krea images, Qwen3-TTS speech, Hy-MT2 translation, Qwen3.8 visual review, asset library). Use whenever a task needs generated media.
verified_against: media-mcp 0.5.1 (2026-09-06)
---

# Media production on the cluster (media-mcp)

All media generation goes through the `media-mcp` MCP server (tools: `video_submit`/`video_status`/`video_fetch`, `image_submit`/`image_status`/`image_fetch`, `workflow_submit`/`workflow_status`/`workflow_fetch`, `tts`, `translate`, `image_review`, `video_review`, `reverse_prompt`, `assets_search`/`asset_get`/`asset_tag`/`asset_feedback_get`, `storyboard_plan`/`storyboard_plan_get`/`storyboard_plan_update`/`storyboard_run`/`storyboard_status`/`storyboard_fetch`, `presets_list`, `jobs_list`, `job_recover`; cloud-only since 0.5.0, present only when the matching cloud entry is enabled: `voice_enroll`, `compliance_review`/`compliance_status`, `lipsync`). Text/code chat does not go through it. If a tool listed here is missing from the session (new tools since the last connect), ask the user to run `/mcp` and reconnect `media-mcp` before working around it.

## Search the library before generating (media-mcp ≥ 0.2.0)

Every completed job is copied to MinIO and indexed automatically (prompt, seed, preset, node, size/seconds, review score, tags) — nobody has to call `*_fetch` for that any more. So:

- **First look, then generate.** `assets_search(query="teapot steam", since="30d")` or `assets_search(query="seed:101 preset:draft")`, `assets_search(tags=["hero"], starred=true)`, `assets_search(min_score=4)`. Each hit has a **stable** `url` (`https://media-mcp.zhenbs.com:10000/assets/<asset_id>`, works with your token or from inside the LAN) and a `thumb_url`; nothing expires the way presigned links do.
- `asset_get(asset_id)` returns the full record + the job (prompt, seed, params) — enough to re-submit the same seed on `fast`/`quality` without guessing. `presign=true` adds a 24 h presigned URL for tools that cannot send a bearer.
- `job_recover(job_id, action=attach|resubmit|abandon, backend_id=...)` (admin) resolves a job whose status is
  `submission_unknown`: its request was sent, never confirmed, and its backend cannot be asked whether it holds the
  work. **Never just re-submit such a job** — the backend may be generating it right now and you would pay twice.
  Look at the backend first: attach the id if it is there, `resubmit` only once you have confirmed it is not, or
  `abandon` to write it off. A job in this state carries `manual_action_required: true` and will not move on its own.
  A job whose cancel the node never confirmed within the window shows `cancel_unconfirmed` (0.3.13): it keeps its
  slot, nothing releases it on a timer, and only `job_recover(job_id, action="abandon")` — after you checked the
  node — does; a job that finished while it was being cancelled comes back `completed` with its result.
- `asset_feedback_get(asset_id)` (0.5.1, needs `jobs.read`) returns the HUMAN verdict the operator gave in the console (`rating` good / ok / bad, reason tags, note, every rater, the history with a job-side snapshot); `assets_search(rating="bad")` lists the failure-case set, `rating="none"` what nobody rated yet. Prefer works rated `good` as references.
- `asset_tag(asset_id, add=["hero","ep1"], starred=true, collection="game-art")` marks keepers. **Drafts expire after 7 days** unless starred or in a collection; other presets are kept. Tag what you would want to find again.
- `*_fetch` and `storyboard_fetch` now also return `asset_id` / `asset_url` (per shot too), so pass those on instead of presigned links.
- Operators see the same library in the console (`/admin` → Assets: search, grid, tags, star, collections, same-seed resubmit, reverse prompt).

## The loop: draft → review → final

1. **Draft cheaply.** `video_submit(prompt, preset="draft", seconds=5, seed=<fixed>)` (5 s is the default since 2026-09-06 and matches a storyboard shot; 4–15 s accepted, time is roughly linear: 5 s ≈ 2 min, 15 s ≈ 9 min on the lottery node). Draft is 832×480 + Turbo 8 steps; it lands on spark-03 `comfy2` first, overflow to spark-04 `comfy`. `video_status.progress` stays null on the ComfyUI lane — poll every 20–30 s and expect ~2 min for 5 s, do not read null as "stuck". Submit several drafts (different seeds or prompt variants) back to back; they queue.
2. **Review, don't eyeball.** `video_review(job_id)` / `image_review(job_id)` returns a 5-axis score (prompt match, composition, artifacts, style, usability) plus one improvement hint from the cluster's Qwen3.8 vision model (`qwen38-flash-next-nvfp4`, the `vision` backend; `overall` is 1.0–5.0 with one decimal). `reverse_prompt` uses the same vision lane. Iterate on the prompt until the review passes the bar you set.
3. **Final with the same seed.** Re-submit the approved prompt with the **same seed** using `preset="fast"` (1344×768 Turbo 8 steps, ~5 min per 4 s, ~40 min per 15 s; everyday deliverable) or `preset="quality"` (1344×768 Base 20 steps, ~11 min per 4 s). `daily` = Base 8 steps without the Turbo look (~5 min per 4 s, ~36 min per 15 s).
4. **Fetch.** `video_fetch(job_id)` returns the presigned URL (24 h) plus `asset_id` and the stable `asset_url`; the copy to MinIO already happened on completion. Hand the stable URL on; do not re-fetch in a loop.

Never iterate prompts on `quality`. Never submit `quality` for more than one candidate at a time.

## H3 video facts (MiniMax-H3 on the ComfyUI lane, spark-04)
- 24 fps fixed; `seconds` 4–15; the server rounds frames up to 17n+5 (4 s → 107 frames, 15 s → 362).
- Output is video **with generated audio** (speech, ambience). Spoken lines go in the official H3 dialogue tag, not in quotes: `(S1) <name> says: <d>[Chinese] 台词原文</d>` — quotes are reserved for text that should appear ON SCREEN. In the 2026-09-05 A/B sample, raw Chinese dialogue in quotes was burned in as subtitles (3.0 vs 4.3); treat quotes as on-screen text.
- 16:9 at short edge 768 is the tuned resolution. `draft` uses short edge 480.
- One job at a time on the GPU (shared with Krea image jobs); a 15 s clip is ~36–40 min on either `daily` or `fast` (Turbo's speed-up fades on long clips). Plan batches accordingly and poll with `video_status` every 20–30 s (5 s draft ≈ 2 min) or use `jobs_list`.
- Prompts: subject + action + camera + lighting + audio cue. English and Chinese both work.

## Images (Krea 2 via ComfyUI)
- `image_submit(prompt, preset="krea-default", seed, width, height)`; 1024×1024, 8 steps, CFG 1. About 15 s warm. For a 16:9 video first frame use `preset="krea-169"` (1344×768, same Turbo 8 steps, `nodes: [comfy2, comfy]`) so the frame already matches `fast`/`quality`.
- For anything the presets do not cover, `workflow_submit(graph_json, overrides)` runs a raw ComfyUI API graph; ask the operator for a template before inventing node ids.

## Speech and translation (synchronous)

- `tts(text, voice, lang)` → WAV in MinIO (asset). Backend since 2026-09-04: **Qwen3-TTS-12Hz-1.7B** on spark-04 (`tts-lane`), Breeze retired. Voices are presets (`presets_list` → `tts.voices`): `default` (Vivian, plain), `calm` (audiobook), `news` (Ryan, anchor), `story-female` (Serena) / `story-male` (Aiden) for drama and fight scenes, `energetic` (short-video hook). Each preset = built-in speaker + a free-text style instruction; ask for a new preset rather than inventing parameters.
- Speed: ≈0.75× real time per sentence; long text is split into sentences and batch-decoded, so a 60 s narration returns in ≈10–20 s. Keep one call ≤4000 chars; for a whole episode send one call per scene so seams fall on scene cuts.
- Voice cloning exists on the service (`ref_audio` 3–10 s + its transcript) but is not exposed as an MCP tool yet; ask before relying on it.
- `translate(text, dst="en", src=None)` via Hy-MT2 (spark-04); `dst` is the target language (default zh), `src` optional. Both calls are synchronous.

## Seed lottery across two nodes (media-mcp ≥ 0.1.7)

- `video_submit(prompt, preset="draft", seconds=5, seeds=[11, 12, 13, 14])` (or `n=4` with a base `seed`) creates **one job per seed** and spreads them over the ComfyUI nodes (spark-04 `comfy` + spark-03 `comfy2`) by current queue depth. The result is `{"batch": true, "job_ids": [...], "count", "requested"}`; if some seeds could not be queued it carries `partial: true` + `failed`. Poll each `job_id` with `video_status`, review the winners with `video_review`, then re-submit **only the chosen seed** on `fast`/`quality`.
- Max 8 seeds per call. A lottery on `quality` is never worth it: draft first, final once.
- Each job records the node it ran on (`backend`); `video_fetch` and the console's cancel follow the job automatically. Different presets may pin a node (`nodes:` in presets) for vendor/quant experiments.

## Two text models behind the same gateway

- `/v1/chat/completions` routes by model id. Since 2026-09-06 there is one text lane: `qwen38-flash-next-nvfp4` (spark-01/02, TP2, 512K, multimodal — accepts `image_url` parts; primary for coding, review and reverse prompts). The Qwen3.6 lane on spark-03 was retired to give that node to ComfyUI; `presets_list.models` is the live list — use only ids it shows.
- A token may be restricted to a model allowlist; `/v1/models` lists what your token can use.

## Reverse-prompting an image (media-mcp ≥ 0.1.9)

- `reverse_prompt(source=<job_id or URL>, style="sd")` returns a Krea-ready tag prompt + `negative_prompt`; `style="h3"` returns a MiniMax-H3 paragraph plus an `audio` line for `video_submit`; `style="plain"` a prose description (`lang="zh"` for Chinese notes/description). Feed `prompt` straight into `image_submit` / `video_submit`; keep the same seed discipline.
- Inside ComfyUI you can call the same model without media-mcp tools: an OpenAI-compatible VLM node with `base_url http://192.168.1.100:8150/v1`, `model qwen38-flash-next-nvfp4`, an `mm_` token with `llm.chat`, the image as a data: URL. The gateway floors `max_tokens` to 8192 for thinking models (header `X-MM-Max-Tokens-Adjusted` tells you when it did), so do not fight it with small budgets.
- From inside the LAN (192.168.1.0/24) requests without a bearer act as the `lan-default` token (limited scopes); pass your own `mm_` token whenever you need more than it allows.

## Music and sound effects (media-mcp ≥ 0.2.0, comfy2 on spark-03)

- **BGM**: `music_submit(prompt=<style/instrument/mood tags>, preset="bgm-draft", seconds=30, seed=<fixed>, bpm=<int>, key="A minor")` → poll `music_status` → `music_fetch` (MP3). Draft is 30 s and cheap (ACE-Step 1.5 turbo, 8 steps): run a lottery (`seeds=[...]`, ≤8) and pick by ear/rubric, then re-submit the **same prompt + seed + bpm + key** on `preset="bgm-final"` with the real length (60–300 s, FLAC, lossless). Never lottery on `bgm-final`.
- **Lyrics**: omit `lyrics` (or pass `instrumental=true`) for instrumental game music; otherwise pass `[Verse]/[Chorus]`-tagged lyrics and set `language` implicitly through the text (default en; Chinese lyrics work with `zh`-style content).
- **SFX**: `music_submit(prompt=<describe the sound, not music>, preset="sfx", seconds=2..8, seed=<fixed>)` → FLAC. Stable Audio 3 small-sfx; no lyrics/bpm/key. Multi-seed lottery is normal for SFX (`seeds=[1,2,3,4]`). Loops: ask for "seamless loop" in the prompt and cross-fade in your editor; the model does not guarantee sample-exact loops.
- Limits: bgm 1–600 s, sfx 1–60 s; models live only on `comfy2` (spark-03), so music jobs queue behind any H3 job on that node — submit BGM/SFX first or accept the wait. Record seeds; same preset + seed is deterministic.

## Which node does what (media-mcp ≥ 0.2.0, measured 2026-09-04)

- **Lottery node = `comfy2` (spark-03)**: Krea first frames, 5 s `draft` lotteries. Since 2026-09-06 the node is ComfyUI-only (Qwen3.6 retired, ~104 GiB free). Presets `krea-default` and `draft` prefer it. Timing is predictable (models reload every job: Krea ~30 s, 4 s draft 115–126 s) and it is never blocked behind a 15 s render. spark-04 is faster when its models are warm (4 s draft ~80 s) but 3–4x slower after a Krea job or cache eviction (270–340 s), so it is reserved for long clips.
- **Quality node = `comfy` (spark-04)**: `fast` / `daily` / `quality` (up to 15 s) are pinned there. A 15 s clip is a 36 min GPU hold, so never put a Krea image or a draft behind it: lottery first on comfy2, then one final on comfy.
- ComfyUI executes one queue serially: a Krea image queued behind a running H3 job waits for the whole job (measured: +250 s wait). If you need an image while a long clip renders, it goes to comfy2 automatically.
- Storyboard shots are capped at 6 s (`max_shot_seconds`); they may run on comfy2. Finals of an approved plan: `preset="quality"`.
- Wuxia workflow: `image_submit(preset="krea-169")` (Krea 1344×768, comfy2) → pick frame → `video_submit(... seeds=[...])` 4 s drafts (spread over both, comfy2 first) → `video_review` → storyboard `continue` shots from the chosen last frame → one `quality` final on comfy.

## Cloud providers (media-mcp ≥ 0.5.0, opt-in per entry, none enabled yet)

- Cloud preset names as shipped (all `available: false` until their entry is enabled and keyed): video `bailian-wan27`, `ark-seedance`, `kling-std`, `vidu-turbo`, `hailuo-23`, `veo-fast`; image `qwen-image-pro`, `seedream-pro`, `flux2-pro`, `flux3-draft`; music `fun-music`; TTS voices `cloud-cherry` (阿里百炼 qwen3-tts-flash) and `cloud-minimax-calm` (MiniMax speech-2.8-hd). Check the `available` flag in `presets_list` before choosing one; a local preset is always the default.
- The same tools reach paid cloud models when a preset's backend is a `type: cloud-media` entry of services.yaml (阿里百炼 wan / qwen-image / Qwen3-TTS / fun-music, 火山方舟 Seedance / Seedream, 可灵, 生数 Vidu, MiniMax 海螺 / Speech 2.8, Google Veo, BFL FLUX, 腾讯天御). Nothing new to learn on the client side: pick the cloud preset name shown by `presets_list` (its entry carries `cloud: true`, `model`, and `presets_list` → `backends.cloud` shows the billing unit and a cost estimate). Today every cloud entry is `enabled: false` and no key is configured, so such a preset answers `backend_rejected: cloud backend '<name>' is not available: 已停用` — do not retry, tell the user which entry/key is missing.
- Cloud-only tools appear only when their entry is enabled: `voice_enroll(name, sample_url)` clones a voice on 阿里百炼 (¥0.01/voice, 10–20 s clean speech, never singing) and returns a `voice_id` for a cloud tts voice preset; `compliance_review(source)` sends a finished video (asset_id or allow-listed URL) to 腾讯天御 as the licensed publish gate and returns a job_id, `compliance_status(job_id)` returns the `verdict` (Suggestion Block|Review|Pass, Labels); `lipsync(video_asset_id, audio_asset_id)` (or `text=` instead of audio) lip-syncs an existing clip on 生数 Vidu and returns an ordinary video job (poll `video_status`, then `video_fetch`).
- Cloud errors keep the same shape with a reason word first: `backend_rejected: <entry>: insufficient_balance|content_blocked|content_moderated|rate_limited|auth_failed|task_expired|cancelled|invalid_request: <detail>`. Cloud jobs record `params.cloud` = {provider, service, model, flow, cost_estimate, region, payment}; a cloud job is money, so never lottery (`seeds`/`n`) on a cloud preset without being asked.

## Etiquette
- Always pass a `seed` you record; determinism is guaranteed for the same preset+seed.
- Use `presets_list` if unsure what exists; presets are hot-reloaded and may grow (e.g. new models arrive as new presets, tools stay the same).
- On `backend_unreachable` or `queue_full`, wait and retry; do not spam submits.

## Long videos: storyboard pipeline (`storyboard_*`)

For anything longer than one 15 s clip, do not chain `video_submit` by hand: use the storyboard tools (ComfyUI H3 lane on spark-04, one clip per shot, auto-continuation, review gates, ffmpeg assembly).

1. **Plan.** `storyboard_plan(text, style?, characters?, target_seconds?, shot_seconds=5, language?)`.
   - Feed a **novel chapter** as-is (up to ~60k chars; split longer chapters by scene). Feed a **shot script** as free text (one paragraph per shot works well) or as a ready JSON storyboard (`{"shots":[{"seconds","prompt","camera","characters","dialogue","transition"}], "characters":{...}}`; JSON skips the LLM). A **one-line brief** also works but give `target_seconds`.
   - Pass `characters={name: {appearance}}` when you already know the cast; the planner keeps the names and repeats the sheet in every shot (that is what keeps faces/clothes stable).
   - Read `plan.shots[*]` and `shot_prompts` (the exact H3 prompts). Fix wrong beats, split shots whose dialogue does not fit (~3 words/s, 1 s silence at both ends), set `transition: continue` only when the next shot really continues in the same place; then `storyboard_plan_update(plan_id, plan)`. `warnings` lists what the validator changed.
2. **Run.** `storyboard_run(plan_id, preset="fast", seed=<fixed>)` returns `run_id` immediately. Budget ≈ 5 min per 5 s shot on `fast`, ≈ 13 min on `quality`, times attempts. Poll `storyboard_status(run_id)` every 60–120 s; `stage` tells you which shot is rendering, `progress.eta_s` extrapolates from finished shots.
3. **Read the score table.** In `storyboard_status`/`storyboard_fetch` each shot has `review_overall` (Qwen vision 1–5), `attempts`, `seam_ssim`/`seam_ok`, `drop_frames`, `below_threshold` and `notes`. A shot with `below_threshold: true` was kept as the best of its attempts: read its `review_summary`, fix the prompt in the plan and rerun that shot (`storyboard_run(plan_id, resume_run_id=<run>)` regenerates only shots that are not `done`; to force a redo of a done shot, change its `seconds` or edit it into a new plan). `seams_cut` in the report lists continuations that were downgraded to hard cuts because the seam did not match.
4. **Fetch.** `storyboard_fetch(run_id)` gives the final mp4 URL, each shot's clip and last-frame URL, and `report{duration_s, frames, retries}`. Every shot is also a normal job (`jobs_list(service="shot")`, `video_review(job_id)`).

When to use `quality`: only for the final render of an approved plan whose `fast` run scored well; it does not fix planning problems, it only sharpens. Use `continuity="cut"` for montage/multi-location pieces (no seams to protect), `fl2v` (default) for continuous action, `guide` only as an experiment on continuous action with camera motion (falls back to fl2v if ComfyUI rejects it). `review_threshold=0` disables the vision gate when the Qwen endpoint is busy. Keep `target_seconds` ≤ 180 (server cap) and expect ~1 h of GPU time per minute of film on `fast`.
