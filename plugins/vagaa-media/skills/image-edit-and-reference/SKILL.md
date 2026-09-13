---
name: image-edit-and-reference
description: Use to plan image changes, animate images, preserve character references, and select supported reference or video-to-video routes; check the current capability table before promising edits, motion transfer or subject replacement.
verified_against: media-mcp 0.7.20 (2026-09-13)
shared_facts: ../_shared/cluster-facts.md
shared_facts_sha256: 0a403c42e84651f84eed8528b2248d8698a3d0fb6f22c35f505689b531ce12f5
---

# Images, references and identity — current gateway contracts

Read this section first: it is the honest capability table. Facts (presets, nodes, timings): `../_shared/cluster-facts.md`.

| need | available now | how |
|---|---|---|
| describe an existing image to re-create or vary it | yes | `reverse_prompt(source, style="sd")` → `image_submit`; `style="h3"` → `video_submit`; `style="plain"` → prose |
| a new image in a chosen composition / size | yes | `image_submit(prompt, preset="krea-default"|"krea-169", seed, width, height)` → `image_review` |
| animate an existing image (image-to-video) | yes | `video_submit(prompt, image_url=<allowlisted HTTP(S) URL>, preset="draft", seed)`; for an asset ID use `director_run` with segment `first_frame`. `prompt_rewrite` does not cover i2v |
| keep a character stable across shots of one film | yes (planner) | `storyboard-longform`: the same `characters` sheet in every shot |
| instruction-based image editing / multi-reference image composition | **no dedicated tool** | `workflow_submit` can run an existing verified graph; model weights alone do not provide an image-edit API. No release date is promised |
| reference-driven video (character / voice references) | yes, director | `director_run` segment `ref_images` / `ref_audios` or its character table; see `storyboard-longform`. This does not extend `prompt_rewrite` to reference modes |
| video-to-video using an existing clip | yes, director | A single `director_run` v2v segment with `source_video`; this is not a dedicated motion-transfer / subject-swap API |
| upload a local user file | **no dedicated tool** | A gateway asset or allowlisted URL is required. Report this input gap; do not claim a filesystem path or data URI was accepted |

When a row says "no dedicated tool": tell the user plainly, offer the nearest available route (often `reverse_prompt` + a new generation, or a hand-built
ComfyUI graph via `workflow_submit` with the operator's template), and record the gap; never fake the result with a different tool.

## 1. Reference images that ARE supported
- Accepted sources differ by tool: read `../_shared/media-inputs.md` when moving media between tools. Director accepts asset IDs; review takes job IDs or allowlisted URLs; `video_submit.image_url` requires a URL. An unsigned stable asset URL is not a universal media input.
- `reverse_prompt(source=<job_id or URL>, style="sd", lang="en"|"zh")` returns a tag prompt + `negative_prompt` for Krea; keep the seed discipline
  (`seed` fixed, iterate on the prompt) so a re-generation is comparable to the reference.
- Image-to-video: `video_submit(image_url=...)` uses the H3 i2v path; keep `seconds` at 5 for drafts and describe the MOTION, not the picture
  (the frame already carries the look). Review with `video_review(source=job_id)`; the reviewer sees frames only, so mention the reference in `prompt=`.

## 2. Identity across a film (delegated)
Cross-shot identity is a planning problem: pass one `characters={name: {"appearance": ...}}` sheet to `storyboard_plan` and keep names identical in every
shot; continuity `fl2v` carries the last frame into the next shot. That whole flow is `storyboard-longform`; do not chain `video_submit` by hand.

## 3. Reviewing an edit or a reference-based result
`image_review(source, rubric=..., prompt=...)` scores prompt consistency, composition, artifacts, style, usability from one result image. `prompt=`
provides text constraints, not a second image. For "only change X", inspect the original and result side by side separately; a single-image score
does not prove the unrequested regions were preserved. Report when the comparison was not possible.

## 4. Raw graphs (`workflow_submit`) as the escape hatch
`workflow_submit(graph_json, overrides)` runs a ComfyUI API-format graph as-is (scope `workflow.raw`); `workflow_status` / `workflow_fetch` return every
SaveImage / video output. Use only with a graph the operator supplied for that model (node ids, model files and the node that has the weights
differ between `comfy` and `comfy2`); never invent node ids. Outputs are indexed like any other job.
