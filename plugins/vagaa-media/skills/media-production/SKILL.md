---
name: media-production
description: MUST load FIRST for any request to make, find, review or deliver media through the media gateway: images, video clips, speech/narration, translation, finding earlier work, reviewing a clip, draft→final. 中文触发：帮我做个视频、画张图、整张图、念出来、配音、翻译、找之前做的、审一下、哪里不行、出正式版、再来一张、换个风格、用 sora/可灵/runway 生成。Covers image_submit, video_submit (draft → video_review → same-seed final), tts, translate, assets_search, video_review, job polling and delivery, and the behaviour rules for unsupported models, vague briefs and long jobs.
verified_against: media-mcp 0.7.36 (2026-09-15)
shared_facts: ../_shared/cluster-facts.md
shared_facts_sha256: 14352cbee7d70dd8a43326b3f017f499182c01134736f077b3b54236a217d9e6
when_to_use: 用户一提到出图、出片、配音、翻译、找作品、审片，先加载本 skill 再调任何 media 工具；用户点名不存在的模型（sora、runway、可灵、veo）时也先加载。
---
## 0. Behaviour rules (2026-09-14, from the pty trial)
1. **Unsupported capability first.** If the user names a model or feature this gateway does not have (sora, runway, kling, veo, seedance, cloud presets that are disabled), say so in ONE sentence before anything else, then offer the local route (presets_list). Never silently substitute and generate.
2. **Vague brief → one question.** "生成一段东西" / "做个视频" with no subject or duration: ask one short question (subject + length) before spending GPU. A clear brief needs no question.
3. **Long jobs are tickets, not loops.** fast/quality clips, 15 s renders and storyboard/director runs take 5–40 min. Wait with `job_wait(job_id)` / `storyboard_wait(run_id)` (server-side long-poll, ≤55 s per call, returns early on change; reply carries `eta_s`, `done`, `next`) — never `sleep`. At most 3 waits per turn; then END the turn with the job_id / run_id, `eta_s`, and "说一声我再查". NEVER say you are monitoring, polling or watching in the background: you are not; only a person's next message resumes you.
4. **Exact tool names.** Media tools are `mcp__plugin_vagaa-media_media__<tool>` (e.g. `…media__presets_list`, `…media__video_status`); never shorten or hyphenate the prefix.
5. **Results carry the ticket.** Every reply that produced media ends with: asset page URL, job_id, preset + seed, and what to say to iterate.
6. **Editing / swapping / motion transfer have their own tools now**: `image_edit` (change an existing picture), `character_swap` (put a reference character into a video, SCAIL-2), `motion_animate` (Wan-Animate-2) — load `image-edit-and-reference` for their contracts; `character_status` / `job_wait` (pass the chain id as `job_id`) follow a chain.
7. **Read the brief forms first.** call `presets_list(brief=true)` first (one screen, ~3K chars); plain `presets_list()` is the 26K-char full contract, only for a missing parameter; `assets_search` rows are brief (`full=true` or `asset_get` for everything). `video_review` frames: 8 is enough for a draft; 16 costs ~4 GiB on the language node.


# Media production on the cluster (core loop)

All media work goes through the `media-mcp` MCP server. Node timings, preset tables, voices, limits and error codes live in
`../_shared/cluster-facts.md` — read it once per task, do not restate numbers from memory. Specialist skills: `video-prompting`
(writing / rewriting / A/B-testing a video prompt), `storyboard-longform` (multi-shot films, continuity, resume, assembly),
`image-edit-and-reference` (references, identity, edits), `music-and-sfx` (BGM, SFX, levels). This skill owns the loop
itself plus speech, translation, the asset library and job recovery. Invoke specialists by the name in the harness skill listing (plugin installs use `vagaa-media:<name>`); loading this core skill does not load their bodies.
Use the exact qualified tool names and input schemas exposed in this session; never invent a namespace or borrow parameters from another tool. A tool intentionally hidden by a planning-only test is not evidence of a production outage.

## 1. Search the library before generating
- `assets_search(query="teapot steam", since="30d")`, `assets_search(query="seed:101 preset:draft")`, `assets_search(tags=["hero"], starred=true)`,
  `assets_search(min_score=4)`. Each hit has a stable authenticated `url` and `thumb_url`; URL stability does not prevent asset expiry.
- `asset_get(asset_id)` returns the record + the job (prompt, seed, params, and since 0.6.0 `params.prompt_id` when the prompt came from
  `prompt_rewrite`) — enough to re-submit the same seed on a final preset without guessing. `presign=true` adds a 24 h URL.
- `asset_tag(asset_id, add=["hero","ep1"], starred=true, collection="game-art")` marks keepers; untagged drafts expire after 7 days.
- `asset_feedback_get(asset_id)` (needs `jobs.read`) returns HUMAN ratings entered in the console; `assets_search(rating="bad")` lists rated failures, `rating="none"` unrated work. Empty ratings mean no human feedback, not poor quality. Machine review uses separate scores.
- Reuse a matching asset when it satisfies the current request. Scores and metadata identify candidates; claim a hard constraint is met only after inspecting the original media against that same requirement. State any unverified action, sound or visual constraint instead of treating a historical score as delivery approval.

## 2. The loop: draft → review → final
1. **Draft cheaply.** `video_submit(prompt, preset="draft", seconds=5, seed=<fixed>)` or a lottery `seeds=[11, 12, 13, 14]` (≤ 8, one job per
   seed, spread over both nodes). Poll `video_status(job_id)` every 20–30 s; `progress` stays null on the ComfyUI lane — that is not "stuck".
   **Never end your turn while a job you submitted is still queued/running** — in a non-interactive run (`claude -p`, a hook, a script) there is
   no next turn: keep calling `video_status` (sleep 20–30 s between calls) until it is `completed` / `failed` / `lost`, then fetch and review.
   Prompt text: write it yourself (see `video-prompting`) or pass `prompt_id` from `prompt_rewrite`; `rewrite="auto"` on `draft` runs the
   deterministic check + rewrite for you and FAILS the call (nothing generated) when no valid prompt comes out. Leave `rewrite` unset to send
   your words untouched (the pre-0.6.0 behaviour). Optional `idempotency_key` makes a retried call replay the first answer instead of paying twice.
2. **Review.** `video_review(source=job_id)` / `image_review(source=job_id)` → five 1–5 scores + `overall` + one suggestion from the Qwen vision
   lane. Check the original brief as well as the score: sampled JPEGs cannot certify sound, a full action, or human taste. `reverse_prompt(source, style="h3"|"sd"|"plain")` describes an image.
3. **Final with the same seed.** Re-submit the approved text with the SAME seed on `fast` (everyday) or `quality` (one candidate, never iterate);
   a `prompt_id` written for `draft` is accepted unchanged on `fast`/`daily`/`quality` (same 5 s); anything else is refused, never re-rewritten.
   Fix missing actions, wrong references or style drift before final rendering; a larger preset is not a repair operation. Recheck the final itself.
4. **Deliver.** `video_fetch(job_id)` → `url` (temporary browser link), `asset_id`, authenticated stable `asset_url`. Give the user `url` unchanged; keep `asset_id`/`job_id` for reuse. Save an approved deliverable with `asset_tag(asset_id, starred=true)` or a collection; an unstarred draft may expire after 7 days. Media input and link contracts: `../_shared/media-inputs.md`.
Images: `image_submit(prompt, preset="krea-default", seed, width, height)`; `krea-169` defaults to 1344×768 (7:4). For exact 16:9, explicitly pass `width=1024, height=576` and check the output dimensions; poll `image_status(job_id)`, then `image_fetch(job_id)`.
Raw ComfyUI graphs: `workflow_submit(graph_json, overrides)` → `workflow_status` / `workflow_fetch` — ask the operator for a template first.

## 3. Speech and translation (synchronous, this skill's job)
- `tts(text, voice, lang)` → WAV asset. Voices are presets (`presets_list` → `tts_voices`): `default`, `calm`, `news`, `story-female`,
  `story-male`, `energetic`; two additional cloud voices are listed but unavailable. Current production cap: 2000 characters per call; split longer speech by scene/sentence.
  Speed and warm-up options are not MCP parameters; inspect the TTS schema and live presets.
- `translate(text, dst="en", src=None)` via Hy-MT2; `dst` is the target language (default zh).
- Voice cloning (`voice_enroll`) and lip-sync (`lipsync`) are cloud-only tools that appear only when their entry is keyed — today none is.

## 4. Jobs, recovery, presets
- `jobs_list(limit, service, status)` for an overview; `presets_list` for the live presets / voices / models / cloud entries (`available` flag).
- `job_recover(job_id, action=attach|resubmit|abandon, backend_id)` (admin) resolves `submission_unknown`, `cancel_pending`,
  `cancel_unconfirmed`. **Never just re-submit such a job** — the node may be generating it; check the node, then attach / resubmit / abandon.
- Cloud presets have `cloud: true` and `available` on each video/image/music/voice entry; there is no required top-level `cloud` section. A disabled entry is not callable. Follow the user's budget for paid generations.
- `compliance_review(source)` / `compliance_status(job_id)` = the licensed publish gate (cloud, only when keyed).

## 5. Etiquette
Always pass and record a `seed`. On `backend_unreachable` / `queue_full` wait and retry, never spam. `quality` is for one approved candidate.
For a missing tool, check the current surface, permissions, disabled cloud entries and any planning-only restriction first. Ask for `/mcp` reconnection only when an expected connected tool is actually unavailable; never call a hidden tool by guessing its name.
