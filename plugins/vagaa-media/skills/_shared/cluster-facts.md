# Cluster facts (single source for the five media skills)

Referenced by every `SKILL.md` under `.claude/skills/*` as `../_shared/cluster-facts.md`; its sha256 is stamped in each
skill's front matter (`shared_facts_sha256`) and checked by `media-mcp/tools/skill_check.py` — edit HERE, then run
`media-mcp/tools/skills_build.py --write`. Timings are measurements with a date; when they drift by more than 25 %,
update the number and the date, never the prose around it. Verified against media-mcp 0.6.0 (2026-09-06).

## Tools (media-mcp MCP server; `presets_list` is the live truth for presets, voices, models, cloud entries)
`video_submit`/`video_status`/`video_fetch`, `image_submit`/`image_status`/`image_fetch`, `music_submit`/`music_status`/`music_fetch`,
`workflow_submit`/`workflow_status`/`workflow_fetch`, `director_run`/`director_status`/`director_fetch`/`director_pack_export`/`director_pack_import`/`director_pack_run`, `tts`, `translate`, `image_review`, `video_review`, `reverse_prompt`,
`prompt_rewrite`/`prompt_get` (0.6.0), `assets_search`/`asset_get`/`asset_tag`, `storyboard_plan`/`storyboard_plan_get`/
`storyboard_plan_update`/`storyboard_run`/`storyboard_status`/`storyboard_fetch`, `presets_list`, `jobs_list`, `job_recover` (admin).
Cloud-only, present only when the matching cloud entry is enabled (none is, 2026-09-06): `voice_enroll`, `compliance_review`/
`compliance_status`, `lipsync`. If a tool is missing from the session, ask the user to run `/mcp` and reconnect `media-mcp`.

## Nodes and lanes (2026-09-06)
- **comfy2 = spark-03** (lottery node): `draft` 5 s ≈ 2 min (4 s draft 115–126 s), Krea images ≈ 30 s (models reload every job);
  never blocked behind a 15 s render. Music models (ACE-Step, Stable Audio 3) live ONLY here — music queues behind any H3 job on it.
- **comfy = spark-04** (final node): `fast`/`daily`/`quality`; 15 s clip ≈ 36–40 min GPU hold; faster when warm (4 s draft ~80 s),
  3–4× slower after a Krea job or cache eviction. Both nodes serve `fast`/`daily`/`quality` since 2026-09-06 (comfy2 verified on a 15 s fast, 2098 s).
- ComfyUI runs one queue serially per node: an image queued behind a running H3 job waits for the whole job (+250 s measured).
- Text/vision lane: one model, `qwen38-flash-next-nvfp4` (spark-01/02, 512K context, multimodal); planner, reviewer, rewriter and
  reverse prompts all use it. `presets_list.models` is the live list.
- TTS: Qwen3-TTS-12Hz-1.7B on spark-04 `tts-lane` (≈0.75× real time per sentence, batch-decoded); translation: Hy-MT2 on spark-04.

## Video presets (H3 on the ComfyUI lane, 24 fps, `seconds` 4–15, frames snap to 17n+5: 4 s → 107, 5 s → 124, 15 s → 362)
| preset | size / steps | ≈ time | use |
|---|---|---|---|
| `draft` | 832×480, Turbo 8 | 5 s ≈ 2 min (comfy2) | iterate; the only preset `prompt_rewrite` covers (T2V, 5 s, zh/en dialogue) |
| `fast` | 1344×768, Turbo 8 | ≈5 min per 4 s, ≈40 min per 15 s | everyday final; same seed as the approved draft |
| `daily` | 1344×768, Base 8, no LoRA | ≈5 min per 4 s, ≈36 min per 15 s | when the Turbo look is not wanted |
| `quality` | 1344×768, Base 20 | ≈11 min per 4 s | final only, one candidate at a time, never iterate |
Cloud video presets (all `available: false` until keyed): `bailian-wan27`, `ark-seedance`, `kling-std`, `vidu-turbo`, `hailuo-23`, `veo-fast`, `flux3-draft`.
Output is video WITH generated audio (speech, ambience). `video_status.progress` stays null on the ComfyUI lane: poll every 20–30 s.
Lottery: `seeds=[...]` (≤ 8) or `n=k` → one job per seed spread over both nodes; reply `{batch, job_ids, jobs, nodes}`.

## Image presets (Krea 2 via ComfyUI)
`krea-default` 1024×1024, 8 steps, CFG 1, ≈15 s warm; `krea-169` 1344×768 for a 16:9 first frame (`nodes: [comfy2, comfy]`).
Cloud image presets (unkeyed): `qwen-image-pro`, `seedream-pro`, `flux2-pro`. Raw graphs: `workflow_submit` (ask for a template first).

## Music / SFX presets (comfy2 only)
`bgm-draft` (ACE-Step 1.5 turbo, 30 s, MP3, lottery here), `bgm-final` (60–300 s FLAC, same prompt+seed+bpm+key, never lottery),
`sfx` (Stable Audio 3 small-sfx, 2–8 s FLAC, no lyrics/bpm/key). Limits: bgm 1–600 s, sfx 1–60 s. Cloud: `fun-music` (unkeyed).
H3 clips come out quiet (≈ −34 dB measured by a reference setup); level normalisation is not exposed as a tool yet.

## TTS voices (`presets_list` → `tts_voices`)
`default` (Vivian), `calm` (audiobook), `news` (Ryan), `story-female` (Serena), `story-male` (Aiden), `energetic`; cloud voices
`cloud-cherry`, `cloud-minimax-calm` (unkeyed). One call ≤ 4000 chars; one call per scene so seams fall on scene cuts.

## Storyboard
Shots 4–8 s (default 5, cap `max_shot_seconds` 6 in production), `target_seconds` ≤ 180, review gate `review_threshold` 3.5 (0 disables),
continuity `fl2v` (default) | `guide` (experimental) | `cut`; ≈ 5 min per 5 s shot on `fast`, ≈ 13 min on `quality`; ≈ 1 h GPU per minute of film.
- Director console (0.7.0, `director_run`): AIMixer MiniMaxH3 Director on both ComfyUI nodes; segment joins carry motion + audio (22-frame guide); draft 832×480 ≈ 2 min per 5 s segment, r2v/v2v (ref2va + 4-step LoRA) ≈ 75–180 s; media uploads go to every node; ≤ 24 segments, v2v = 1 segment; diffusion model int8_convrot on all H3 presets since 0.7.0. 0.7.1: `characters` table + dialogue shortcuts; `refine=latent_upscale` (LBH 3D latent upscaler on both nodes) → 1344×768 in the same job.
0.6.0 does NOT route storyboard prompts through `prompt_rewrite`; the planner keeps its own renderer (`Style:`/`Location:` prefixes).

## Asset library and job states
Every completed job is copied to MinIO and indexed (prompt, seed, preset, node, review score, tags). Stable URL
`https://media-mcp.zhenbs.com:10000/assets/<asset_id>`; presigned links last 24 h. Drafts expire after 7 days unless starred / in a collection.
Job states: `queued_local` → `queued` → `running` → `completed` | `failed` | `lost`; `submission_unknown`, `cancel_pending`,
`cancel_unconfirmed` need a PERSON (`job_recover`, admin) and keep their node slot meanwhile.

## Etiquette
Record every seed (same preset + seed is deterministic). `backend_unreachable` / `queue_full`: wait and retry, never spam.
A cloud preset is money: never lottery on it unless asked; a missing key answers `backend_rejected: ... 已停用`, do not retry.
Errors are `<code>: <detail>` with code ∈ backend_unreachable, backend_timeout, backend_rejected, backend_error, storage_error,
invalid_preset, invalid_argument, queue_full, job_not_found, forbidden, limit_exceeded, and (0.6.0) unsupported_target,
unsupported_references, unsupported_language, rewrite_failed, prompt_not_found, prompt_not_usable, prompt_binding_mismatch,
idempotency_in_progress, idempotency_failed, profile_not_found.
- Links a fetch returns (verified from the public internet 2026-09-09): `url` = presigned S3 link on `https://s3.zhenbs.com:10000`, opens ANYWHERE (phone, no login) for 24 h, supports seeking; `asset_url` = permanent `https://media-mcp.zhenbs.com:10000/assets/<id>`, needs the bearer (or the LAN default principal) — give the user `url` for "open it now", keep `asset_url` for records and for passing back to tools. Presigned URLs may be passed back as `image_url` / `first_frame` (the host is allowlisted).
