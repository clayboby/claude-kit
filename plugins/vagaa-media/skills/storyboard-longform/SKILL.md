---
name: storyboard-longform
description: Use to turn briefs, scripts, or prose into multi-shot videos, manage characters and transitions across shots, resume interrupted storyboard runs, and assemble the resulting sequence.
verified_against: media-mcp 0.6.4 (2026-09-07)
shared_facts: ../_shared/cluster-facts.md
shared_facts_sha256: 7d364005ed4a335557afc36ef0b39191a9b81b3ecfc5b8b23c2d348fc91485d2
---

# Long videos: the storyboard pipeline (`storyboard_*`)

Anything longer than one 15 s clip goes through the storyboard tools (plan → run → status → fetch), not through hand-chained `video_submit`.
Facts (shot limits, timings, review gate, continuity modes): `../_shared/cluster-facts.md`. Single-clip prompt wording: `video-prompting`.
Reference images / identity across shots is split: cross-shot continuity is this skill; reference-driven generation is `image-edit-and-reference`.

## 1. Plan
`storyboard_plan(text, style?, characters?, target_seconds?, shot_seconds=5, language?)` → `plan_id` + `plan` + `shot_prompts`.
- Feed a **novel chapter** as-is (up to ~60k chars; split longer chapters by scene), a **shot script** as free text (one paragraph per shot) or
  as a ready JSON storyboard (`{"shots":[{"seconds","prompt","camera","characters","dialogue","transition"}], "characters":{...}}` — JSON skips the LLM),
  or a **one-line brief** with `target_seconds`.
- Pass `characters={name: {"appearance": ...}}` when the cast is known: the planner repeats the sheet in every shot, which is what keeps faces and
  clothes stable across shots. Give every recurring character the same name in every shot.
- Read `plan.shots[*]` and `shot_prompts` (the exact H3 prompts the runner will send; they carry the planner's own `Style:` / `Location:` prefixes —
  0.6.0 does not route storyboard prompts through `prompt_rewrite`). Fix wrong beats, split shots whose dialogue does not fit (~3 words/s, 1 s
  silence at both ends), set `transition: "continue"` only when the next shot really continues in the same place; then
  `storyboard_plan_update(plan_id, plan)`. `warnings` lists what the validator changed. `storyboard_plan_get(plan_id)` re-reads a stored plan.

## 2. Run
`storyboard_run(plan_id, preset="fast", seed=<fixed>, continuity="fl2v"|"guide"|"cut", review_threshold=3.5, max_retries=2)` → `run_id` at once.
- Budget ≈ 5 min per 5 s shot on `fast`, ≈ 13 min on `quality`, times attempts; ≈ 1 h of GPU per minute of film. Poll `storyboard_status(run_id)`
  every 60–120 s: `stage` names the shot being rendered, `progress.eta_s` extrapolates from finished shots.
- `continuity`: `fl2v` (default) hands the previous last frame to the next shot; `cut` for montage / multi-location pieces (no seams to protect);
  `guide` (experimental) anchors the last 22 frames + audio and falls back to `fl2v` if ComfyUI rejects it. `review_threshold=0` disables the gate.
- `quality` is for the final render of an approved plan whose `fast` run scored well; it sharpens, it does not fix planning.

## 3. Read the score table, then resume or redo
- Each shot in `storyboard_status` / `storyboard_fetch` has `review_overall` (Qwen vision 1–5), `attempts`, `seam_ssim` / `seam_ok`, `drop_frames`,
  `below_threshold`, `notes`. A `below_threshold: true` shot was kept as the best of its attempts: read `review_summary`, fix that shot's prompt in the
  plan, and rerun only it with `storyboard_run(plan_id, resume_run_id=<run>)` (finished shots are reused; to force a redo of a done shot, change its
  `seconds` or edit it into a new plan). `seams_cut` lists continuations downgraded to hard cuts because the seam did not match.
- **Interrupted runs**: `storyboard_run(resume_run_id=<run>)` ALONE continues after a restart / timeout — done shots reused, an in-flight backend job
  adopted; a run is continued at most once. `blocked` is not terminal: the reply names the shot job and the actions; `submission_unknown` /
  `cancel_pending` / `cancel_unconfirmed` need `job_recover` by a person (see `media-production`) before a resume is accepted.
- Every shot is also a normal job: `jobs_list(service="shot")`, `video_review(job_id)` for a second opinion, `asset_get(asset_id)` per shot.

## 4. Assemble and deliver
`storyboard_fetch(run_id)` → final mp4 URL (presigned) + per-shot clip / last-frame URLs + `asset_id` / `asset_url` per shot + `report{duration_s,
frames, retries}`. Hand the stable asset URLs on. Trimming, re-ordering, overlaying music or burning subtitles after assembly is not exposed as a
tool in 0.6.0 (a compose / loudnorm chain is a 0.6.1 candidate): say so and hand the per-shot clips to the user's editor instead of improvising.

## 5. Wuxia-style workflow (first frame → drafts → continue → final)
`image_submit(preset="krea-169")` (Krea 1344×768) → pick the frame → `video_submit(image_url=<frame>, preset="draft", seeds=[...])` 4–5 s drafts →
`video_review` → plan the continuation shots from the chosen last frame with `transition: "continue"` → one `quality` run of the approved plan.
