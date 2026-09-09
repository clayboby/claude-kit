---
name: storyboard-longform
description: Use to turn briefs, scripts, or prose into multi-shot videos, manage characters and transitions across shots, resume interrupted storyboard runs, and assemble the resulting sequence.
verified_against: media-mcp 0.7.3 (2026-09-09)
shared_facts: ../_shared/cluster-facts.md
shared_facts_sha256: 243faf8cf6d877ea270703b935ea8d7cf856968a1af54ceaed218c8a865eb9ef
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

## 6. Director console (`director_run`, 0.7.0) — the default for multi-segment work
One job renders a whole plan through the community MiniMaxH3 Director node (installed on both ComfyUI nodes): segments continue motion AND
audio across joins (22-frame guide window), and every input type is accepted in the same call.
```
director_run(segments=[
  {"prompt": "<H3-grammar or plain English>", "seconds": 5},                                   # t2v
  {"prompt": "...", "seconds": 4, "first_frame": "as-…|job-id|https://…", "last_frame": "…"},   # fl2v (first only = i2v)
  {"prompt": "<Picture 1> <Audio 1> …", "seconds": 5, "ref_images": ["as-…"], "ref_audios": ["as-…"]},  # r2v (≤9 images, ≤3 audios)
  {"prompt": "keep the motion of <Video 1>, …", "seconds": 5, "source_video": "as-…"}          # v2v (exactly one segment per plan)
], style="Live-action, cinematic.", width=832, height=480, seed=None, continuity=True, idempotency_key="<your plan id>")
→ {run_id, task, segments[{idx, mode, frames, seconds}], total_frames, seconds, seed, uploads[]}
director_status(run_id) → queued|running|completed|failed|lost ; director_fetch(run_id) → url / asset_id / asset_url
```
- `style` is prefixed to EVERY segment prompt (the node reads segment prompts only): keep it a short look-and-medium line, put beats in the segments.
- `idempotency_key`: reuse your own plan id on a retry and you get the same run back instead of a second render.
- Media references (asset ids, job ids, allowlisted URLs) are uploaded to every node automatically; nothing to place by hand.
- `mode` is inferred from the media given. One plan is one timeline kind: t2v segments may sit beside fl2v OR r2v ones, but fl2v and r2v
  cannot share a plan and v2v is always alone (the call is rejected with `invalid_argument`, nothing is uploaded). An explicit mode
  without its media (r2v with no refs, fl2v with no frame) is rejected too — the node would silently fall back to plain t2v.
- Seconds snap UP to H3's 17k+5 frame grid (5 s → 124 frames, 4 s → 107); 0.2–15 s per segment. Keep a plan ≤ 24 segments.
- v2v takes its length from the source (ffprobe), not from `seconds`; sources over 362 frames (~15 s) are rejected: trim first.
- Draft = 832×480 (default). Final = width 1344, height 768 — same call, ~4× the time. Never iterate prompts on a final.
- fl2v with only a first frame tends to stay still: give it an end frame or write the movement beat by beat.
- r2v references live on the segment (the node ignores plan-level references): always attach `ref_images`/`ref_audios` to the segment that uses them and cite `<Picture N>` / `<Audio N>` in that prompt.
- `video_submit(prompt, preset="director_t2v")` runs the same director graph for ONE text segment — a quick single clip on the
  director models; multi-segment or media-driven work goes through `director_run`.
- 0.7.1 character table — declare once, mention anywhere:
  ```
  director_run(characters={"小明": {"image": "as-…", "voice": "as-…"}, "阿花": "as-…"}, language="Chinese",
               segments=[{"prompt": "@小明 hands @阿花 a lantern.\n小明: 来,刚烤好的!\n旁白: 夜市刚刚醒来。", "seconds": 5}])
  ```
  `@alias` becomes `<Picture N>` and that character's image/voice are attached to THAT segment (it becomes r2v). A line `alias: 台词`
  becomes `<Picture N> says in the voice of <Audio M>: <d>[Chinese] 台词</d>`; `旁白: …` / `Narrator: …` becomes an off-screen voice-over
  with lips closed. Characters cannot be mentioned in a segment that carries a first/last frame or a source video (rejected before upload).
- 0.7.1 final quality: `refine="latent_upscale"` (+ `refine_width=1344, refine_height=768`) enlarges the draft's H3 latent with the 3D
  upscaler in the same job — no second sampling; `director_fetch` reports `refine_applied` (false + a warning means the node fell back
  to the draft). In fl2v plans the given frames pass through the upscaler too. Iterate prompts on drafts, add `refine` only for the
  accepted plan. (Second-sampling modes are not offered yet.) Spoken lines never carry tags: an `@alias` inside a line someone speaks
  becomes the plain name, while the character is still attached.
- Speech budget: H3 speaks Mandarin at ~4 chars/s and never speeds up — a line that does not fit is dropped or cut. Budget ≈ 0.5 s +
  0.28 s per Chinese character (0.37 s per English word) + 0.12 s per punctuation mark; `director_run` refuses a segment over budget.
  One line per 5 s segment; a 20-character line needs 7–8 s. Dialogue goes to a shot with the speaker's FACE large and unobscured
  (medium close-up, facing camera or 3/4, no striking / crossing objects during the line); keep the speaker in frame at the END of a
  segment the next one continues from; a continued segment adds ONE new element.
- Whole-plan ceiling: output `frames × width × height` ≤ 851 × 1344 × 768 (≈35 s at 1344×768 with `refine`, ≈90 s at 832×480). Longer
  stories = several `director_run` calls cut at scene changes; the server refuses an oversize plan before uploading.
- Segment prompt shape (plugin trial 2026-09-09): free prose + shortcut lines — picture (framing, the one new beat, the end state), then
  one `Sound: …` sentence of diegetic ambience, then `旁白:` / `别名:` lines. No `overall_soundscape:` / `non_diegetic_music:` labels
  (that is `video_submit` grammar) and no background music (it fights the picture on this lane). Name every light source and which hand
  holds which prop so the next segment can carry them; `style` is prefixed to EVERY segment, so keep weather and light out of it.
- When to use `storyboard_*` instead: you want the planner LLM to write the shot list from prose, the per-shot review gate, or resume-by-shot. When you already have the shots, `director_run` is one call and joins are cleaner.
