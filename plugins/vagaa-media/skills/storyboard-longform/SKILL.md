---
name: storyboard-longform
description: Load for anything longer than one clip or with more than one shot: short film, ad, promo, MV, short drama, story adaptation, script to video. 中文触发：分镜、镜头表、短片、宣传片、广告片、MV、短剧、剧本、列分镜、第 N 镜改一下、开拍、继续拍、接着上次。Turns a brief into a shot list (storyboard_plan), edits shots (storyboard_plan_update), keeps characters consistent, runs/resumes/assembles (storyboard_run / director_run), and how to report a long run to the user.
verified_against: media-mcp 0.7.45 (2026-09-16)
shared_facts: ../_shared/cluster-facts.md
shared_facts_sha256: 14352cbee7d70dd8a43326b3f017f499182c01134736f077b3b54236a217d9e6
when_to_use: 用户要多镜头、要分镜、要改某一镜、要开拍/续拍时加载；单镜 10 秒以内的小片用 media-production。
---
Vendor guidance and the scope of historical evidence: `../_shared/provenance.md` (read when changing workflows).

# Long videos: the storyboard pipeline (`storyboard_*`)
For a film beyond `presets_list.defaults.max_seconds` (currently 15 s), choose the storyboard pipeline or Director segments below; do not hand-chain `video_submit`.
Facts (shot limits, timings, review gate, continuity modes): `../_shared/cluster-facts.md`. Single-clip prompt wording: `video-prompting`.
Reference images / identity across shots is split: cross-shot continuity is this skill; reference-driven generation is `image-edit-and-reference`.

> Waiting: use `storyboard_wait(run_id)` (server-side, ≤55 s per call, returns when a shot finishes or the run ends) instead of sleeping between `storyboard_status` calls; end the turn with run_id + eta after at most 3 waits.
## 0. Brief before shots (the producer's part; the 2026-09-09 trial film passed every technical review and was judged wrong on
emotion, tone, scene and plot because it had none — `tools/evals/plugin-trial-20260909/`)
Five lines at the top of the plan notes, judged before any technique: 1) one sentence of what happens; 2) genre and tone (what the cold or the light means); 3) what the viewer feels at start / middle / end; 4) references (a film scene or asset id; note which same-brief constraints its original media actually demonstrates);
5) don'ts (smiles, bright streets, storybook look, music, happy ending…). Each shot then names its emotion and the character's physical state before its action. Templates: LOOK Studios and WKKF briefs, cited in `reference/research/20260909-human-vs-ai-h3-prompts.md` §5.

## 1. Plan
`storyboard_plan(text, style?, characters?, target_seconds?, shot_seconds=5, language?)` → `plan_id` + `plan` + `shot_prompts`.
- Feed a **novel chapter** as-is (up to ~60k chars; split longer chapters by scene), a **shot script** as free text (one paragraph per shot) or
  as a ready JSON storyboard (`{"shots":[{"seconds","prompt","camera","characters","dialogue","transition"}], "characters":{...}}` — JSON skips the LLM),
  or a **one-line brief** with `target_seconds`.
- Pass `characters={name: {"appearance": ...}}` when the cast is known: the planner repeats the sheet in every shot to guide faces and
  clothes; inspect the rendered shots to verify identity. Give every recurring character the same name in every shot.
- **Set sheet, same rule as the cast**: decide location, the surface the subject sits on, light and time of day ONCE and write that sentence into
  EVERY shot that stays in the scene ("on the same warm light-oak tabletop beside the sunny kitchen window, soft morning light"). A shot that leaves
  the surface unspecified or asks for a "clean background" is rendered on a different table (product ad 09-15: shots 1/3 white, 2/4 oak). Change the set only when the script changes scene, and say so in that shot.
- Read `plan.shots[*]` and `shot_prompts` (the exact H3 prompts the runner will send; they carry the planner's own `Style:` / `Location:` prefixes —
  0.6.0 does not route storyboard prompts through `prompt_rewrite`). Fix wrong beats, split shots whose dialogue does not fit (~3 words/s, 1 s
  speech-free margin at both ends), set `transition: "continue"` only when the next shot really continues in the same place; then
  `storyboard_plan_update(plan_id, plan)`. `warnings` lists what the validator changed. `storyboard_plan_get(plan_id)` re-reads a stored plan.

## 2. Run
`storyboard_run(plan_id, preset="fast", seed=<fixed>, continuity="fl2v"|"guide"|"cut", review_threshold=3.5, max_retries=2)` → `run_id` at once.
- Budget ≈ 5 min per 5 s shot on `fast`, ≈ 13 min on `quality`, times attempts; ≈ 1 h of GPU per minute of film. Poll `storyboard_status(run_id)`
  every 60–120 s: `stage` names the shot being rendered, `progress.eta_s` extrapolates from finished shots.
- `continuity`: `fl2v` (default) hands the previous last frame to the next shot; `cut` for montage / multi-location pieces (no seams to protect);
  `guide` (experimental) anchors the last 22 frames + audio and falls back to `fl2v` if ComfyUI rejects it. `review_threshold=0` disables the gate.
- `quality` is for a final render after the plan and its `fast` output meet the current brief's hard constraints; a historical score alone is not approval. Recheck the final itself; a larger preset does not fix planning.

## 3. Read the score table, then resume or redo
- Each shot in `storyboard_status` / `storyboard_fetch` has `review_overall` (Qwen vision 1–5), `attempts`, `seam_ssim` / `seam_ok`, `drop_frames`,
  `below_threshold`, `notes`. A `below_threshold: true` shot was kept as the best of its attempts: read `review_summary`, fix that shot's prompt in the
  plan using `storyboard_plan_update`, then resume the latest run. Changed shot fingerprints render again; unchanged completed shots are reused.
  Continuity may invalidate downstream shots too; a low score alone does not force a redo. `seams_cut` lists continuations downgraded to hard cuts.
- **Interrupted runs**: `storyboard_run(resume_run_id=<run>)` ALONE continues after a restart / timeout — done shots reused, an in-flight backend job adopted; a run is continued at most once. `blocked` is not terminal: the reply names the shot job and the actions; `submission_unknown` /
  `cancel_pending` / `cancel_unconfirmed` need `job_recover` by a person (see `media-production`) before a resume is accepted.
- Every shot is also a normal job: `jobs_list(service="shot")`, `video_review(source=job_id)` for a second opinion, `asset_get(asset_id)` per shot.

## 4. Assemble and deliver
`storyboard_fetch(run_id)` → final mp4 URL (presigned) + per-shot clip / last-frame URLs + `asset_id` / `asset_url` per shot + `report{duration_s,
frames, retries}`. Deliver the unchanged presigned `url`, retain asset/job IDs, and star or collect keepers. Stable `asset_url` needs authentication.
Trimming, re-ordering, mixing or subtitles have no dedicated MCP tool: provide source clips or use an explicitly verified editing workflow.

## 6. Director console (`director_run`, 0.7.0) — the default for multi-segment work
One job renders a whole plan through the community MiniMaxH3 Director node (installed on both ComfyUI nodes): segments continue motion AND
audio across joins (22-frame guide window). Choose one compatible timeline kind; different reference modes are not interchangeable.
```
director_run(segments=[
  {"prompt": "The courier approaches the counter. Sound: quiet footsteps.", "seconds": 5},
  {"prompt": "The courier places one envelope on the counter. Sound: paper rustle.", "seconds": 5}
], style="Live-action, cinematic.", width=832, height=480, seed=None, continuity=True, idempotency_key="<your plan id>")
→ {run_id, task, segments[{idx, mode, frames, seconds}], total_frames, seconds, seed, uploads[]}
director_status(run_id) → queued|running|completed|failed|lost ; director_fetch(run_id) → url / asset_id / asset_url
```
- `style` is prefixed to EVERY segment (the node reads segment prompts only): a short look-and-medium line; `idempotency_key` = your plan id (a retry returns the same run).
- `style` is not a set: the set-sheet sentence goes inside EVERY segment prompt verbatim (segments render independently; anything not repeated is re-imagined per shot).
- `mode` is inferred from the media given. One plan is one timeline kind: t2v segments may sit beside fl2v OR r2v ones, but fl2v and r2v
  cannot share a plan and v2v is always alone (the call is rejected with `invalid_argument`, nothing is uploaded). An explicit mode
  without its media (r2v with no refs, fl2v with no frame) is rejected too — the node would silently fall back to plain t2v.
- fl2v uses `first_frame`/`last_frame`; r2v uses `ref_images` (≤9)/`ref_audios` (≤3); v2v uses `source_video`. Unknown fields and incompatible reference fields are rejected. `ref_videos` is not supported; never silently replace it with a v2v source.
- Seconds snap UP to H3's 17k+5 frame grid (5 s → 124 frames, 4 s → 107); 0.2–15 s per segment. Keep a plan ≤ 24 segments.
- v2v takes its length from the source (ffprobe), not from `seconds`; sources over 362 frames (~15 s) are rejected: trim first.
- Draft = 832×480 (default). Final = width 1344, height 768 (7:4, not exact 16:9) — same call, ~4× the time. Never iterate prompts on a final.
- fl2v with only a first frame tends to stay still (C03 seg 1, 2026-09-15: 4–8 s motion ≈ 0.1 with a first frame alone, 0.7–1.1 once a last frame was added): give it an end frame; the join after a given last frame carries a ~2-frame transition that no wording removes.
- r2v references live on the segment (the node ignores plan-level references): always attach `ref_images`/`ref_audios` to the segment that uses them and cite `<Picture N>` / `<Audio N>` in that prompt.
- `video_submit(prompt, preset="director_t2v")` runs the same director graph for ONE text segment — a quick single clip on the director models; multi-segment or media-driven work goes through `director_run`.
- 0.7.1 character table — declare once, mention anywhere:
  ```
  director_run(characters={"小明": {"image": "as-…", "voice": "as-…"}, "阿花": "as-…"}, language="Chinese",
               segments=[{"prompt": "@小明 hands @阿花 a lantern.\n小明: 来,刚烤好的!\n旁白: 夜市刚刚醒来。", "seconds": 5}])
  ```
  `@alias` becomes `<Picture N>` and that character's image/voice are attached to THAT segment (it becomes r2v). A line `alias: 台词`
  becomes `<Picture N> says in the voice of <Audio M>: <d>[Chinese] 台词</d>`; `旁白: …` / `Narrator: …` becomes an off-screen voice-over
  with lips closed. Characters cannot be mentioned in a segment that carries a first/last frame or a source video (rejected before upload).
- **A plan with `continuity=True` must render its final at native size (`width=1344, height=768`, no `refine`)**: both refine modes run per segment after continuity was established at draft size, so every join becomes a one-frame jump of ~7× the median frame difference and the audio at a join can clip to 0 dB (C03 finals A/B, `reference/c03-short-20260915/README.md`). `refine` is for single-segment or `continuity=False` plans (C02, C08).
- 0.7.1 final quality: `refine="latent_upscale"` (+ `refine_width=1344, refine_height=768`) enlarges the draft's H3 latent with the 3D
  upscaler in the same job — no second sampling; `director_fetch` reports `refine_applied` (false + a warning means the node fell back
  to the draft). In fl2v plans the given frames pass through the upscaler too. Iterate prompts on drafts, add `refine` only for the accepted plan. (Second sampling is exposed as refine=upscale; check its result flag.) Spoken lines never carry tags: an `@alias` inside a line someone speaks
  becomes the plain name, while the character is still attached.
- Measured limits (each number has a file behind it; `tools/evals/hypotheses-20260909/RESULTS.md` = R):
  · Speech: one Mandarin line of up to 26 chars fits a 5 s segment (spoken in ≤4.0 s, 2 seeds; R E1); the server refuses ~0.16 s/char + 0.5 s.
  · Whole plan: `frames × width × height` ≤ 851 × 1344 × 768 — 1128 frames at 1344×768 was killed by the kernel OOM (TODO 09-09 09:2x).
  · Framing for dialogue made no measurable difference to speech or mouth shape (n=3 each, R E2): frame for the story, not the model.
  · Three independent changes in a 4 s segment executed one and jump-cut (n=2, R E4): prefer one visible change per continued segment.
  · Finals (R E3/E6/E7, sharpness : time vs 480p+latent_upscale = 1 : 1): `refine="upscale"` (author's second pass) 1.6× : 1.8–3.5×; native 768p turbo 1.6× : 2.5–3×; official 20-step native 2.6–5× : 6–7×. **Which final to make** (the user just says 出正式版; pick by plan shape): joined segments (`continuity=True`, the default for a multi-segment plan) → native `width=1344, height=768`, no `refine` (the only path whose joins survive; C03 2026-09-16: 77 min for 32 s); one segment or `continuity=False` → `refine="latent_upscale"` (fastest, frame-for-frame the approved draft; C02/C08); the user asks for sharper (更清晰/二采) → `refine="upscale"` (1.6× sharpness, ~2× time); showcase (展示级/官方 20 步) → 20-step native. To force a path the user says 原生尺寸出 / 放大出 / 二采出. Never spend a refine on a joined plan.
- How to write a segment (official guide + published examples, `reference/research/20260909-human-vs-ai-h3-prompts.md` §3–4): `style` is
  prefixed to EVERY segment by the server, so keep weather and light out of it. Write motivated action with a change of feeling, as the official
  reference example does (“Her annoyance softens as she looks toward the Samoyed”, “with a playful tone and an easy conversational pace”);
  then the required sound and dialogue. Choose music, silence and shot direction from the current brief; a previous promo's preference is not universal.
  No dialogue, no music and silence are different constraints. Preserve deliberate hand/object and framing requirements; avoid conflicting instructions.
  The server adds the closed-lips sentence for narration. Review actual action and audio separately from sampled-image scores.
- Plan → director in one call: `storyboard_direct(plan_id, seed=…, refine=…)` compiles a stored `storyboard_plan` (characters with `ref_image_url` = an asset id `as-…` from image_fetch / assets_search (a job id or allowlisted URL also works; presigned `url`s expire, `asset_url` is refused) → `<Picture N>` reference binding (verify rendered identity), dialogue → `<d>` lines, `transition: continue` → joined motion/audio) into ONE director job; poll `director_status`, fetch `director_fetch`; the film is judged whole afterwards: `storyboard_direct(review="gate")` then `director_accept(run_id)` measures every segment boundary (fail = a jump > 3× the median frame difference, E10 `tools/evals/hypotheses-20260909/RESULTS.md`) and hands back `retry.seed`; resubmit with it — seams are a draw, not a setting; no per-shot retry (ruling: reference/research/20260909-director-n4n5-design-gpt6.md). When to use `storyboard_*` instead: you want the planner LLM to write the shot list from prose, the per-shot review gate, or resume-by-shot. When you already have the shots, `director_run` is one call and joins are cleaner.
- Packs: `director_pack_export(run_id)` → the node's own zip for the ComfyUI UI (导入导演包; runs before 0.7.7 cannot); `director_pack_import(pack_url|pack_asset)` → `pack_id` + what it would render; `director_pack_run(pack_id, seed=…, refine=…)` renders it as recorded.
