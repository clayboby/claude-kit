---
name: image-edit-and-reference
description: Use to edit existing images, combine visual references, preserve character identity, transfer motion, or replace a subject in a video using the editing and reference capabilities available in the selected preset.
verified_against: media-mcp 0.7.7 (2026-09-10)
shared_facts: ../_shared/cluster-facts.md
shared_facts_sha256: 7529e32af9e2c41b037ca963beb32bd976e4d92c7e51cf52d95150d515a0cc17
---

# Images, references and identity — what 0.6.0 can and cannot do

Read this section first: it is the honest capability table. Facts (presets, nodes, timings): `../_shared/cluster-facts.md`.

| need | available now (0.6.0) | how |
|---|---|---|
| describe an existing image to re-create or vary it | yes | `reverse_prompt(source, style="sd")` → `image_submit`; `style="h3"` → `video_submit`; `style="plain"` → prose |
| a new image in a chosen composition / size | yes | `image_submit(prompt, preset="krea-default"|"krea-169", seed, width, height)` → `image_review` |
| animate an existing image (image-to-video) | yes | `video_submit(prompt, image_url=<allow-listed URL or asset url>, preset="draft", seed)`; `prompt_rewrite` does NOT cover i2v — write the prompt by hand (`video-prompting` §1) |
| keep a character stable across shots of one film | yes (planner) | `storyboard-longform`: the same `characters` sheet in every shot |
| instruction-based image editing, multi-reference composition, outfit swap | **not exposed** | Qwen-Image-Edit weights are on the cluster but the image-edit tool ships in 0.6.1; `workflow_submit` with an operator-provided graph is the only route today |
| reference-driven video (character / voice lock, ref2v) | **not exposed** | H3 ref2v weights exist, the preset is off (`ref2v_enabled: false`); any `references` to `prompt_rewrite` is refused (`unsupported_references`) |
| motion transfer / subject replacement in a video | **not exposed** | Wan Animate 2 / SCAIL-2 are 0.6.1 candidates (a video-animate tool); do not promise them |
| upload a user file as a reference | **not exposed** | an upload tool is 0.6.1; today a reference must already be an asset (`assets_search`) or on an allow-listed host |

When a row says "not exposed": tell the user plainly, offer the nearest available route (often `reverse_prompt` + a new generation, or a hand-built
ComfyUI graph via `workflow_submit` with the operator's template), and record the gap; never fake the result with a different tool.

## 1. Reference images that ARE supported
- Sources: an `asset_id` / stable asset URL from the library, or a URL on the allow-list (`MEDIA_MCP_FETCH_ALLOWED_HOSTS`); other hosts are refused
  with `invalid_argument`. Presigned MinIO links expire after 24 h — hand stable URLs around, not presigned ones.
- `reverse_prompt(source=<job_id or URL>, style="sd", lang="en"|"zh")` returns a tag prompt + `negative_prompt` for Krea; keep the seed discipline
  (`seed` fixed, iterate on the prompt) so a re-generation is comparable to the reference.
- Image-to-video: `video_submit(image_url=...)` uses the H3 i2v path; keep `seconds` at 5 for drafts and describe the MOTION, not the picture
  (the frame already carries the look). Review with `video_review(job_id)`; the reviewer sees frames only, so mention the reference in `prompt=`.

## 2. Identity across a film (delegated)
Cross-shot identity is a planning problem: pass one `characters={name: {"appearance": ...}}` sheet to `storyboard_plan` and keep names identical in every
shot; continuity `fl2v` carries the last frame into the next shot. That whole flow is `storyboard-longform`; do not chain `video_submit` by hand.

## 3. Reviewing an edit or a reference-based result
`image_review(source, rubric=..., prompt=...)` scores prompt consistency, composition, artifacts, style, usability. For "only change X" requests the
reviewer must SEE the original: pass the original prompt / a description of what had to stay unchanged in `prompt=`, and compare the two images yourself;
a high score on the edited image alone does not prove the unrequested regions were preserved.

## 4. Raw graphs (`workflow_submit`) as the escape hatch
`workflow_submit(graph_json, overrides)` runs a ComfyUI API-format graph as-is (scope `workflow.raw`); `workflow_status` / `workflow_fetch` return every
SaveImage / video output. Use only with a graph the operator supplied for that model (node ids, model files and the node that has the weights
differ between `comfy` and `comfy2`); never invent node ids. Outputs are indexed like any other job.
