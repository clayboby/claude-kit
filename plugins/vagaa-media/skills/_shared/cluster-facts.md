# Cluster facts (single source for the five media skills)

Referenced by every `SKILL.md` under `.claude/skills/*` as `../_shared/cluster-facts.md`; its sha256 is stamped in each
skill's front matter (`shared_facts_sha256`) and checked by `media-mcp/tools/skill_check.py` — edit HERE, then run
`media-mcp/tools/skills_build.py --write`. Timings are measurements with a date; when they drift by more than 25 %,
update the measurement with evidence. API/preset contracts aligned with media-mcp 0.8.2 (2026-09-23; image section); deployment verification is recorded in the release ledger. Earlier timings below are historical samples, not latency guarantees.

## Tools (media-mcp MCP server; `presets_list` is the live truth for presets, voices, models, cloud entries)
`video_submit`/`video_status`/`video_fetch`, `image_submit`/`image_status`/`image_fetch`, `music_submit`/`music_status`/`music_fetch`,
`workflow_submit`/`workflow_status`/`workflow_fetch`, `director_run`/`director_status`/`director_fetch`/`director_accept`/`director_pack_export`/`director_pack_import`/`director_pack_run`, `tts`, `translate`, `image_review`, `video_review`, `reverse_prompt`,
`prompt_rewrite`/`prompt_get` (0.6.0; image targets 0.8.2), `image_edit` (Qwen-Image 2.1 since 0.8.2), `assets_search`/`asset_get`/`asset_tag`, `storyboard_plan`/`storyboard_plan_get`/
`storyboard_plan_update`/`storyboard_run`/`storyboard_direct`/`storyboard_status`/`storyboard_fetch`, `presets_list`, `jobs_list`, `job_cancel`, `capabilities`, `job_recover` (admin).
Cloud-only, present only when the matching cloud entry is enabled (none is, 2026-09-06): `voice_enroll`, `compliance_review`/
`compliance_status`, `lipsync`. Missing tools may reflect cloud configuration, scope, surface or a planning-only restriction; verify the cause before asking for reconnection.
**Since 0.8.0 `tools/list` only shows what YOUR token may call, so a tool you cannot see is usually "not granted", not "not built"** —
call `capabilities` (any token, no arguments) before telling anyone a feature does not exist: it returns your principal, `available`,
and `hidden[{tool, code, why, needs_scope, how_to_get_it}]`, plus a note when this instance is the read-only maintenance reader.
0.8.1 also sends `notifications/tools/list_changed` when an admin changes your token, so a refused tool may become available mid-session.

## Nodes and lanes (2026-09-24, media-mcp 0.8.6)
- **comfy-pro = RTX PRO 6000** (the fastest image node; its GPU is shared with its own Qwen3.8-27B, and a job that lands there has its
  official-PE prompt rewrite done by that 27B, not by the cluster's flash lane). IMAGE ONLY
  (Qwen-Image 2.1 + Krea2 kept loaded): first choice for every `image_submit` preset and `image_edit`; never gets video, music or raw
  graphs. Measured 2026-09-23 (IMG21-PRO6000, IMG-BAKEOFF): Krea 1024² ≈ 4–5 s, 2 MP (1448²) ≈ 9 s; Qwen 2.1 T2I 2K/40 steps/cfg 1 ≈ 55 s (cfg 3.5 ≈ 107 s, no longer used); edit one picture at
  the 2K budget ≈ 85–95 s, three ≈ 190 s, five ≈ 285 s, ten at 1440 ≈ 220 s. Under a busy 27B lane a job can take 2–3× longer.
- **comfy2 = spark-03**: the preferred H3 node since 0.8.2 (`draft`, `fast`/`daily`/`quality`, director, storyboard): `draft` 5 s ≈ 2 min;
  music models (ACE-Step, Stable Audio 3) live ONLY here. Image fallback: Krea ≈ 20–30 s, Qwen 2.1 1 MP/25 steps ≈ 18 s warm, edit ≈ 42–54 s.
- **comfy = spark-04**: Krea images only — no video since 2026-09-23 (its memory is shared with the home voice stack) and no Qwen 2.1
  since 0.8.6 (a resident Qwen3.6-35B lives there; a cold 2.1 load ran it below the watchdog line). Same Krea fallback timing as spark-03;
  every `qi21-*` preset and `image_edit` fall back to spark-03 only.
- ComfyUI runs one queue serially per node: an image queued behind a running H3 job waits for the whole job (+250 s measured).
- Text/vision lane: `qwen38-flash-next-nvfp4` (spark-01/02, 512K context, multimodal); planner, reviewer, the H3 rewriter, reverse prompts
  and the image rewrite of GB10 jobs use it. `Qwen3.8-27B` (PRO 6000, 262K context, multimodal) is a second text model behind the same
  gateway `/v1` and rewrites the prompts of PRO 6000 jobs. `presets_list.models` is the live list.
- TTS: Qwen3-TTS-12Hz-1.7B on spark-04 `ha-tts-stream2` (vLLM-Omni, shared with the home agent; ≈0.4× real time, long text read in ≤150-character chunks two at a time and joined; `lang` sets the reading language: zh/en/ja/ko/de/fr/ru/pt/es/it); translation: Hy-MT2 on spark-04.

- **Bulk embeddings are gated (0.7.55).** WeMM (spark-03) shares its GPU with `comfy2`; `embed_batch_*` jobs run only while `comfy2` has been idle 30 s and pause within one chunk when film work arrives (an H3 draft ran 2× slower under a WeMM burst, 2026-09-19). One query-time embedding still goes straight through the gateway `/v1/embeddings`.

## Video presets (H3 on the ComfyUI lane, 24 fps)
`video_submit` accepts integer `seconds` from 1 through `presets_list.defaults.max_seconds` (15 in production, 2026-09-13); token limits may be stricter. The [official H3 output range](https://github.com/MiniMax-AI/MiniMax-H3#readme), 4–15 s, is model guidance, not the gateway's minimum accepted duration. Frames snap to 17n+5: 4 s → 107, 5 s → 124, 15 s → 362; inspect the returned duration.
| preset | size / steps | ≈ time | use |
|---|---|---|---|
| `draft` | 832×480, Turbo 8 | 5 s ≈ 2 min (comfy2) | iterate; the only preset `prompt_rewrite` covers (T2V, 5 s, zh/en dialogue) |
| `fast` | 1344×768, Turbo 8 | ≈5 min per 4 s, ≈40 min per 15 s | everyday final; same seed as the approved draft |
| `daily` | 1344×768, Base 8, no LoRA | ≈5 min per 4 s, ≈36 min per 15 s | when the Turbo look is not wanted |
| `quality` | 1344×768, Base 20 | ≈11 min per 4 s | final only, one candidate at a time, never iterate |
Cloud video presets (all `available: false` until keyed): `bailian-wan27`, `ark-seedance`, `kling-std`, `vidu-turbo`, `hailuo-23`, `veo-fast`, `flux3-draft`.
Output is video WITH generated audio (speech, ambience). `video_status.progress` stays null on the ComfyUI lane: poll every 20–30 s.
The five local video presets (`draft`, `preset="director_t2v"`, `fast`, `daily`, `quality`) have no `image_url` channel. Check `presets_list.video[preset].image_url_supported` for Comfy presets; use Director `fl2v` with `first_frame` for image-to-video. A reference stored in a request is not proof it conditioned the model.
`video_submit` lottery: `seeds=[...]` (≤ 8) or `n=k` → one job per seed; reply `{batch, job_ids, jobs, nodes}`. `storyboard_run` and `director_run` take one `seed`, not `seeds` or `n`.

## Image presets and edit presets (0.8.6; `presets_list(brief=true).image_guide` is the live selection guide)
**Two overrides come before the routes, for a NEW picture** (an edit of an existing one is always `image_edit`): the person NAMES the model
("use Qwen" / 千问 → `qi21-*`, `qi21-text` when there are words; "use Krea" → `krea-*`), or asks for fast / a draft (→ `krea-fast`, unless
the picture must carry exact words).
**Route first, first match wins:** a real-looking PHOTO that must carry exact words (shop front, product poster, menu board, ad) → `krea-default`
with `aspect_ratio="2:3"` for the photo WITHOUT text, then `image_edit` (`qi21-edit`) adds the quoted words; typography IS the picture
(graphic poster, flyer, infographic, UI, menu design, an illustration whose words must be right) → `qi21-text`; combining / keeping / changing
existing pictures → `image_edit`; many named elements with exact counts / left-right positions → `qi21-t2i` (it rewrites by default);
everything else without exact text (photo, portrait, phone snapshot, product, food, anime, concept art, landscape, night, crowds / cities / big
scenes) → `krea-*` — Krea is the QUALITY default there, not a draft (the 09-23 blind bake-off: Krea won those categories, Qwen won words /
layouts / many-element prompts, big scenes were 1 : 1 : 1); Krea's words go as written (its own prompt expansion is not a default).
**Posters and covers are portrait 2:3** (Krea: `aspect_ratio="2:3"` = 1184×1760 on the PRO 6000, 832×1248 on a GB10).
| preset | model | PRO 6000 default (GB10 fallback) | use |
|---|---|---|---|
| `krea-default` / `krea-169` | Krea2 Turbo 8 steps | 1448² (2 MP) / 1928×1088 (16:9, 2 MP), ≈9 s (1024² / 1344×768 7:4, 20–30 s) | the quality default without exact text: photoreal, portraits, products, food, anime, concept art, crowds; the photo step of a photo poster; cannot spell |
| `krea-fast` | Krea2 Turbo 8 steps | 1024² on every node, ≈4 s (20–30 s) | only when the person asks for fast / a draft |
| `qi21-text` | Qwen-Image 2.1 | 1696×2528 (2:3), 40 steps ≈ 1 min (832×1248, 25 steps) | typography-first designs with exact Chinese / English words: graphic posters, flyers, infographics, UI, menus |
| `qi21-t2i` | Qwen-Image 2.1 | 2048² ≈ 55 s (1024², 25 steps ≈ 18 s) | many named elements with counts / positions; long structured prompts; "use Qwen" |
| `qi21-scene` | Qwen-Image 2.1 | 2528×1696 (3:2) ≈ 1 min (1248×832) | a wide frame with many named elements and exact counts / positions; keeps 3:2 whatever ratio the rewrite picks |
| `qi21-rgba` | Qwen-Image 2.1 | 2048², RGBA sentence added, no rewrite | transparent PNG: sticker, logo, cut-out product |
| `qi21-quality` | Qwen-Image 2.1, 40 steps | 2048² on every node (≈ 55 s; ≈ 190 s on GB10) | one hard final on Qwen |
Every qi21 `image_submit` preset runs **cfg 1** (0.8.6): the official path; a `negative_prompt` has no effect at cfg 1 (cfg 3.5 + negative
doubled the time and was not steadily better, IMG-BAKEOFF §2.3).
`aspect_ratio="3:2"` sizes the picture to each node's pixel budget; `width`/`height` pin one size on every node (so `width=1024, height=1536`
is now SMALLER than the PRO 6000's 2 MP default). `krea-169` is 16:9 on the PRO 6000 and 7:4 on a GB10; `aspect_ratio="16:9"` gives ≈16:9 at
each node's budget (1920×1088 / 1376×768); an EXACT 16:9 everywhere = `width=1024, height=576` (checked 2026-09-13). qi21 output is always a PNG with an alpha channel.
**Every qi21 `image_submit` preset but `qi21-rgba` rewrites by default** (0.8.6, owner 2026-09-24: 「这个几乎不用不行」) with the official Qwen-Image 2.1
prompt enhancer (the authors' PE-T2I system prompt, run by the rewriter of the node the job lands on; +15–45 s, median ≈38 s, BEFORE the job
id comes back): a long English observer paragraph plus an aspect ratio; quoted words are checked verbatim. `rewrite="off"` per call sends your
words as written; an English prompt of 120+ words is kept as written; a defaulted rewrite that fails falls back to your words with a warning.
`qi21-rgba` has NO rewrite (the profile does not cover it; `rewrite="auto"` answers unsupported_target): in the 2026-09-23 A/B the enhancer
painted a background and a transparent sticker lost its transparency. Another known cost from that A/B: a night scene came out too dark. The reply carries `prompt` (the text sent), `prompt_id` and `per_node` sizes; `image_status` /
`job_wait` / `image_fetch` carry `sent_prompt` (what the model got), `caller_prompt` (your words), `rewrite_status` and `was_rewritten`.
**`image_edit` presets:** `qi21-edit` (default; Qwen-Image 2.1; 1–10 pictures; PRO 6000 40 steps at a 2K budget, GB10 25 steps at 1 MP),
`qi21-edit-quality` (cfg 3.5 + negative, twice the time), `qwen-edit-2511` (the old model, 1–3 pictures, fallback only). Reference
pixels are capped per node — PRO 6000 21 MP (1–5 pictures at 2048, 6 at 1856, 7–8 at 1600, 9–10 at 1440; ten at 2048 ran out of
memory), GB10 10.5 MP — and the reply warns when it lowered `resolution`. The instruction is sent as written; `rewrite="auto"` runs the
official PE-I2I rewriter on the pictures first (+15–60 s; no gain on four clear instructions in the A/B — use it for a vague one).
Six or more people in one picture: identities may mix (2026-09-23, IMG21-GB10). Cloud image presets (unkeyed): `qwen-image-pro`,
`seedream-pro`, `flux2-pro`. Raw graphs: `workflow_submit` (ask for a template first; they run on the GB10 nodes only).

## Music / SFX presets (comfy2 only)
`bgm-draft` (ACE-Step 1.5 turbo, 30 s, MP3, lottery here), `bgm-final` (60–300 s FLAC, same prompt+seed+bpm+key, never lottery),
`sfx` (Stable Audio 3 small-sfx, accepts 1–60 s FLAC; 2–8 s is a typical short cue, no lyrics/bpm/key). BGM accepts 1–600 s. Check the live preset and schema for the requested length. Cloud: `fun-music` (unkeyed).
H3 clips come out quiet (≈ −34 dB measured by a reference setup); level normalisation is not exposed as a tool yet.

## TTS voices (`presets_list` → `tts_voices`)
`default` (Vivian), `calm` (audiobook), `news` (Ryan), `story-female` (Serena), `story-male` (Aiden), `energetic`; cloud voices
`cloud-cherry`, `cloud-minimax-calm` (unkeyed). Production cap is 2000 characters per call; six local voices plus two unavailable cloud entries is not eight callable voices.

## Storyboard
Shots 4–8 s (default 5, cap `max_shot_seconds` 6 in production), `target_seconds` ≤ 180, review gate `review_threshold` 3.5 (0 disables),
continuity `fl2v` (default) | `guide` (experimental) | `cut`; ≈ 5 min per 5 s shot on `fast`, ≈ 13 min on `quality`; ≈ 1 h GPU per minute of film.
- Director console (0.7.0, `director_run`): AIMixer MiniMaxH3 Director on both ComfyUI nodes; segment joins carry motion + audio (22-frame guide); draft 832×480 ≈ 2 min per 5 s segment, r2v/v2v (ref2va + 4-step LoRA) ≈ 75–180 s; media uploads go to every node; ≤ 24 segments, v2v = 1 segment; diffusion model int8_convrot on all H3 presets since 0.7.0. 0.7.1: `characters` table + dialogue shortcuts; `refine=latent_upscale` (LBH 3D latent upscaler on both nodes) → 1344×768 in the same job.
0.6.0 does NOT route storyboard prompts through `prompt_rewrite`; the planner keeps its own renderer (`Style:`/`Location:` prefixes).
`presets_list.storyboard.ref2v_enabled: false` applies to the older `storyboard_run` renderer, not all H3 references. `director_run` r2v and `storyboard_direct` character references use ref2va. `prompt_rewrite` coverage is a third, separate capability table. `director_run` has no `ref_videos` argument; raw graphs and imported packs require separate validation.

## Asset library and job states
Every completed job is copied to MinIO and indexed (prompt, seed, preset, node, review score, tags). Stable URL
`https://media-mcp.zhenbs.com:10000/assets/<asset_id>`; presigned links last 24 h. Drafts expire after 7 days unless starred / in a collection.
Historical scores, tags and accepted runs identify candidates, not proof that a new brief's hard constraints are met. Claim a constraint is demonstrated only when the cited original media is inspectable and has been checked against that same requirement; record what remains unverified. Sampled frames cannot certify complete action timing or audio. Choose sound from the current brief: a closed list of allowed sounds excludes added room tone, while no dialogue, no music and complete silence are different requests.
Waiting: `job_wait(job_id, timeout_s=55)` — always the full 55 s; every call re-sends the whole conversation (a three-picture edit waited on 8 times
cost 1.2 M input tokens on 2026-09-23).
Job states: `queued_local` → `queued` → `running` → `completed` | `failed` | `lost`; `submission_unknown`, `cancel_pending`,
`cancel_unconfirmed` need a PERSON (`job_recover`, admin) and keep their node slot meanwhile.
**Stopping work (0.8.1).** `job_cancel(job_id)` stops a job YOUR token submitted — use it the moment the user says "stop"/"取消"
about something still running, instead of letting a 15-minute `quality` render finish and bill the token's GPU budget. Someone
else's job answers `forbidden`; `jobs_list` marks every row with `can_cancel` / `cancel_hint` and repeats the stoppable ids in
`cancellable`. A node that confirms the stop leaves the job `failed`; a node that does not leaves it `cancel_pending` (still holding
its slot, re-asked automatically). Cancelling something already finished is not an error — the reply says `cancelled: false`.
Storyboard SHOT jobs are refused (one stopped shot just makes the run retry it): a run has to be stopped from the console.

## Etiquette
Record every seed for comparisons; reproducibility also depends on model/workflow/runtime and is not a bitwise guarantee. `backend_unreachable` / `queue_full`: wait and retry, never spam.
A cloud preset is money: never lottery on it unless asked; a missing key answers `backend_rejected: ... 已停用`, do not retry.
Errors are `<code>: <detail>` with code ∈ backend_unreachable, backend_timeout, backend_rejected, backend_error, storage_error,
invalid_preset, invalid_argument, queue_full, job_not_found, forbidden, limit_exceeded, and (0.6.0) unsupported_target,
unsupported_references, unsupported_language, rewrite_failed, prompt_not_found, prompt_not_usable, prompt_binding_mismatch,
idempotency_in_progress, idempotency_failed, profile_not_found.
- Fetch `url` is the temporary browser link; `asset_url` is the stable authenticated record. Keep signed URLs unchanged and renew via fetch when expired. Pass `job_id` to review and `asset_id` to director references; accepted media arguments differ by tool. See `media-inputs.md` for the per-tool table. Cloud availability is on each preset/voice entry (`cloud`, `available`), not a top-level `cloud` section.
