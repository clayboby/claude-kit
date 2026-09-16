---
name: image-edit-and-reference
description: Load when the user wants to CHANGE an existing image or video rather than make a new one, or keep something consistent: edit/retouch an image, change clothes or background, swap a person, transfer motion from a video, animate a still, use a reference image, keep a character or product identical across shots. 中文触发：改图、修图、换装、换背景、换人、换脸、动作迁移、让这张图动起来、参考图、保持一致、同一个人。Tells which routes exist today (Director fl2v/ref2v/v2v, reverse_prompt, raw workflow) and which have NO tool yet, so you can say so honestly.
verified_against: media-mcp 0.7.47 (2026-09-16)
shared_facts: ../_shared/cluster-facts.md
shared_facts_sha256: 14352cbee7d70dd8a43326b3f017f499182c01134736f077b3b54236a217d9e6
when_to_use: 用户拿着已有的图/视频要改、要保持一致、要参考时加载；只是从零画一张新图用 media-production。
---

# Images, references and identity — current gateway contracts

Read this section first: it is the honest capability table. Facts (presets, nodes, timings): `../_shared/cluster-facts.md`.

| need | available now | how |
|---|---|---|
| describe an existing image to re-create or vary it | yes | `reverse_prompt(source, style="sd")` → `image_submit`; `style="h3"` → `video_submit`; `style="plain"` → prose |
| a new image in a chosen composition / size | yes | `image_submit(prompt, preset="krea-default"|"krea-169", seed, width, height)` → `image_review` |
| animate an existing image (image-to-video) | yes, director | `director_run(segments=[{mode:"fl2v", first_frame:<image asset/job/allowlisted URL>, prompt:..., seconds:...}], seed=...)`. Current local `video_submit` T2V presets cannot use an image. `prompt_rewrite` does not cover i2v |
| keep a character stable across shots of one film | planning support; verify outputs | `storyboard-longform`: the same `characters` sheet in every shot guides identity but does not certify it |
| instruction-based image editing / multi-reference composition | **yes — `image_edit`** (0.7.28, Qwen-Image-Edit 2511) | `image_edit(images=[<edited>, <ref2>, <ref3>], instruction, negative, seed, steps=40, cfg=4, lightning=false)`: images[0] is the picture being edited and sets the output size; images[1..2] are references named as "image 2" / "image 3" in the instruction; no mask/inpaint input exists. Returns a workflow job → `job_wait` / `workflow_status` → `workflow_fetch`. `lightning=true` = official 4-step LoRA (fast, slightly less faithful). |
| reference-driven video (character / voice references) | yes, director | `director_run` segment `ref_images` / `ref_audios` or its character table; see `storyboard-longform`. This does not extend `prompt_rewrite` to reference modes |
| video-to-video using an existing clip | yes, director | A single `director_run` v2v segment with `source_video`; this is not a dedicated motion-transfer / subject-swap API |
| replace the person in a video with a reference character, scene kept | **yes — `character_swap`** (0.7.28, SCAIL-2) | `character_swap(driver_video, reference_image, prompt, mode="replace", driver_object="person", ref_object="person")`: SAM 3.1 text picks the person on both sides; the prompt describes the OUTPUT (appearance, held objects, scene); long videos are chained in 81-frame segments. Returns chain_id → `job_wait` (pass the chain id as `job_id`) or `character_status(chain_id)` → final job_id + asset. `mode="animate"` = reference character performs the motion, scene from the prompt. Only the node holding SCAIL-2 runs it (~4 min per 65–81-frame segment). |
| reference character performs a driving video's motion, prompt-controlled background/camera | **yes — `motion_animate`** (0.7.28, Wan-Animate-2) | `motion_animate(driver_video, reference_image, prompt, pose_prompt)`: no mask; framing of reference and driver must match (full body ↔ full body, the #1 failure cause); long videos chained with continue_motion (experimental). ~6 min per 81 frames. |
| upload a local user file | **no dedicated tool** | A gateway asset or allowlisted URL is required. Report this input gap; do not claim a filesystem path or data URI was accepted |

`krea-169` defaults to 1344×768 (7:4), not exact 16:9. For an exact 16:9 image, explicitly pass `width=1024, height=576` to `image_submit` and verify the original file's dimensions; wording the ratio in a prompt is not a size control.

When a row says "no dedicated tool": tell the user plainly, offer the nearest available route (often `reverse_prompt` + a new generation, or a hand-built
ComfyUI graph via `workflow_submit` with the operator's template), and record the gap; never fake the result with a different tool.

## 1. Reference images that ARE supported
- Accepted sources differ by tool: read `../_shared/media-inputs.md` when moving media between tools. Director accepts asset IDs; review takes job IDs or allowlisted URLs. `video_submit.image_url` requires both a supporting preset and an allowlisted URL; URL validation alone does not establish an image channel. An unsigned stable asset URL is not a universal media input.
- `reverse_prompt(source=<job_id or URL>, style="sd", lang="en"|"zh")` returns a tag prompt + `negative_prompt` for Krea; keep the seed discipline
  (`seed` fixed, iterate on the prompt) so a re-generation is comparable to the reference.
- Image-to-video: use a single Director `fl2v` segment with `first_frame`; inspect the schema and load `storyboard-longform` for Director options. Keep the requested duration and describe the intended motion, with appearance constraints consistent with the frame. Poll `director_status`, then `director_fetch`. Review the completed job with `video_review(source=run_id, prompt=<original brief>)`; the reviewer sees sampled frames only and does not receive the original reference as a second video. Do not discard a required image to make a T2V call succeed.

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
