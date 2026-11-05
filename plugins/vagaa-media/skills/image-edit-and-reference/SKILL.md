---
name: image-edit-and-reference
description: Load when the user wants to CHANGE an existing image or video rather than make a new one, or keep something consistent: edit/retouch an image, change clothes or background, swap a person, transfer motion from a video, animate a still, use a reference image, keep a character or product identical across shots. 中文触发：改图、修图、换装、换背景、换人、换脸、动作迁移、让这张图动起来、参考图、保持一致、同一个人。Tells which routes exist today (Director fl2v/ref2v/v2v, reverse_prompt, raw workflow) and which have NO tool yet, so you can say so honestly.
verified_against: media-mcp 0.9.22 (2026-11-05)
shared_facts: ../_shared/cluster-facts.md
shared_facts_sha256: d282274761849abcb52758a63eb81bde5dc93d22aa9a2d0581f2e4ec636ffcf0
when_to_use: 用户拿着已有的图/视频要改、要保持一致、要参考时加载；只是从零画一张新图用 media-production。
---

# Images, references and identity — current gateway contracts

Read this section first: it is the honest capability table. Facts (presets, nodes, timings): `../_shared/cluster-facts.md`.

| need | available now | how |
|---|---|---|
| describe an existing image to re-create or vary it | yes | `reverse_prompt(source, style="sd")` → `image_submit`; `style="h3"` → `video_submit`; `style="plain"` → prose |
| a new image in a chosen composition / size | yes | `image_submit(prompt, preset="krea-default"|"krea-169", seed, aspect_ratio)` for photoreal / aesthetic / portraits / crowds (posters and covers: `aspect_ratio="2:3"`); `preset="qi21-text"` (typography IS the picture), `"qi21-t2i"` (many elements with counts / positions; rewrites by default), `"qi21-rgba"` (transparent PNG) — `media-production` owns the choice; → `image_review` |
| animate an existing image (image-to-video) | yes, director | `director_run(segments=[{mode:"fl2v", first_frame:<image asset/job/allowlisted URL>, prompt:..., seconds:...}], seed=...)`. Current local `video_submit` T2V presets cannot use an image. `prompt_rewrite` does not cover i2v |
| keep a character stable across shots of one film | planning support; verify outputs | `storyboard-longform`: the same `characters` sheet in every shot guides identity but does not certify it |
| instruction-based image editing / multi-reference composition | **yes — `image_edit`** (0.8.2: Qwen-Image 2.1, up to 10 pictures) | `image_edit(images=[<edited>, <ref2>, …], instruction, preset="qi21-edit", seed)`: images[0] is the canvas being changed; §5 below is how to write the instruction. Returns a workflow job → `job_wait` / `workflow_status` → `workflow_fetch`. `preset="qwen-edit-2511"` is the old model (1–3 pictures, `megapixels`, `lightning=true` 4 steps; a node without the Lightning LoRA file cannot run it, so the edit then falls back to the plain 40 steps and the receipt's `lightning` field says `used: false` and why — tell the user it was not 4-step) — only when 2.1 cannot do it. No mask input: say WHERE in words, or circle it on the picture in a colour and name the colour. |
| remove a background / make a transparent cut-out | **yes — `image_edit`** | instruction "Remove the background, and output a PNG image" (the official wording); the PNG carries a real alpha channel. A NEW transparent picture from text: `image_submit(prompt, preset="qi21-rgba")` |
| make an existing picture bigger / sharper (upscale) | **yes — `image_upscale`** (0.9.3) | `image_upscale(source=<as-… / image job / allowlisted URL>, mode="hd", scale=2)` → an image job → `job_wait` → the NEW work (`asset_id`, rarely `asset_pending: true`: call `job_wait` again; the source is not touched). `mode="hd"` (default, SeedVR2 7B sharp) is the faithful one for portraits and photos (≈25 s for 1024×1280 → 2×); `"detail"` (3B) adds skin / texture detail and can age a face — only when asked; `"fast"` with `fast_model="anime"` (illustrations, line art, screenshots) or `"photo"`, seconds, and the ONLY tier for a transparent PNG. `scale` 2 or 4, lowered automatically to fit the 16 MP output cap (the reply says the scale used). Pass `idempotency_key` when retrying; `in_library=false` keeps a background enlargement out of the library lists. |
| a real-looking PHOTO that must carry exact words (shop front, product poster, menu board, ad) | yes — **the default route, two steps** | `image_submit(prompt, preset="krea-default", aspect_ratio="2:3")` for the photo with no text in it → `image_edit(images=[<that job or asset>], instruction='add the title "…" and the date "…" in the empty sky; keep the photo unchanged')`. Measured 2026-09-23: the photo stays exactly as Krea made it and every character is right; Krea2 alone misspelled 「啡」, `qi21-text` alone looked less like a photo. `qi21-text` is for typography-first designs (graphic posters, infographics, UI) |
| reference-driven video (character / voice references) | yes, director | `director_run` segment `ref_images` / `ref_audios` or its character table; see `storyboard-longform`. This does not extend `prompt_rewrite` to reference modes |
| video-to-video using an existing clip | yes, director | A single `director_run` v2v segment with `source_video`; this is not a dedicated motion-transfer / subject-swap API |
| replace the person in a video with a reference character, scene kept | **yes — `character_swap`** (0.7.28, SCAIL-2) | `character_swap(driver_video, reference_image, prompt, mode="replace", driver_object="person", ref_object="person")`: SAM 3.1 text picks the person on both sides; the prompt describes the OUTPUT (appearance, held objects, scene); long videos are chained in 81-frame segments. Returns chain_id → `job_wait` (pass the chain id as `job_id`) or `character_status(chain_id)` → final job_id + asset. `mode="animate"` = reference character performs the motion, scene from the prompt. Only the node holding SCAIL-2 runs it (~4 min per 65–81-frame segment). |
| reference character performs a driving video's motion, prompt-controlled background/camera | **yes — `motion_animate`** (0.7.28, Wan-Animate-2) | `motion_animate(driver_video, reference_image, prompt, pose_prompt)`: no mask; framing of reference and driver must match (full body ↔ full body, the #1 failure cause); long videos chained with continue_motion (experimental). ~6 min per 81 frames. |
| use the person's OWN photo (a file they hand over) | **yes — `asset_upload`** (0.8.11) | `asset_upload(data_base64=<the file>, filename=..)` — png / jpeg / webp ≤ 20 MiB, ≤ 50 MP; stored re-encoded (phone rotation applied, GPS / camera metadata dropped, long edge ≤ 4096), private to your token, expires in 7 days unless starred or a director run uses it → `as-…` for `image_edit(images=[…])` (one upload per picture, up to 10) or `director_run` `first_frame`. A filesystem path or data URI is not an input: upload the bytes |

`krea-169` is 1928×1088 (16:9, 2 MP) on the PRO 6000 but 1344×768 (7:4) on a GB10 fallback. `aspect_ratio="16:9"` gives ≈16:9 at each node's budget (1920×1088 / 1376×768); for an EXACT 16:9 on every node pass `width=1024, height=576` to `image_submit` and verify the original file's dimensions; wording the ratio in a prompt is not a size control.

When a row says "no dedicated tool": tell the user plainly, offer the nearest available route (often `reverse_prompt` + a new generation, or a hand-built
ComfyUI graph via `workflow_submit` with the operator's template), and record the gap; never fake the result with a different tool.

## 1. Reference images that ARE supported
- Accepted sources differ by tool: read `../_shared/media-inputs.md` when moving media between tools. Director accepts asset IDs; `image_review` / `video_review` / `reverse_prompt` take an asset ID (`as-…`), a job ID or an allowlisted URL. `video_submit.image_url` requires both a supporting preset and an allowlisted URL; URL validation alone does not establish an image channel. An unsigned stable asset URL is not a universal media input.
- `reverse_prompt(source=<job_id or URL>, style="sd", lang="en"|"zh")` returns a tag prompt + `negative_prompt` for Krea; keep the seed discipline
  (`seed` fixed, iterate on the prompt) so a re-generation is comparable to the reference.
- Image-to-video: use a single Director segment with `first_frame`. Since 0.9.1 a first frame alone runs as the node's i2v task: the subject itself moves and the clip does not return to the frame (I-1, 2026-10-05; before, it ran as fl2v, held the frame and drifted back to it, or an invented second person did the motion). Give `last_frame` only when the clip must END in a specific different state (a mug knocked over, keys handed over, a lamp switched on): `image_edit` of the same image with only the result changed — a separately generated end image was cut or dissolved to in 5/6 L2 runs (2026-09-17); inspect the schema and load `storyboard-longform` for Director options. Keep the requested duration and describe the intended motion, with appearance constraints consistent with the frame. Poll `director_status`, then `director_fetch`. Review the completed job with `video_review(source=run_id, prompt=<original brief>)`; the reviewer sees sampled frames only and does not receive the original reference as a second video. Do not discard a required image to make a T2V call succeed.

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
differ between `comfy` and `comfy102`); never invent node ids. Outputs are indexed like any other job.

## 5. Writing an `image_edit` instruction (Qwen-Image 2.1)
- **Name the pictures `<image1>`, `<image2>` … `<imageN>`** in the order of `images` (e.g. "put the coat from <image2> on the woman in <image1>, keep her face, hair and pose"); a single picture needs no tag. Never "the first image" / "图1".
- Lead with the change, then say what stays: "change the background to a snowy mountain; keep the boy, the sandcastle and the bucket exactly as they are". Point at a reference for identity instead of describing a face in words.
- Words that must appear on the picture go in quotes, character for character, in the language wanted.
- The output follows images[0]'s shape. For a new scene built from several pictures (group photo, poster), pass `aspect_ratio="3:2"` / `"2:3"`, or let the rewriter choose.
- **Your instruction is sent as written** (every edit preset defaults to `rewrite="off"`). For a vague request, `rewrite="auto"` first lets the official PE-I2I rewriter (the authors' prompt; the cluster's Qwen looks at the pictures, +15–60 s before the job id) turn it into a precise `<imageN>` directive, and the reply shows what it sent (`prompt`, `prompt_id`). A clear instruction gains nothing from it (four A/B edits, 2026-09-23). `prompt_rewrite(text, target={"tool": "image_edit"}, references=[…the same pictures…])` previews the directive first; `image_edit(images=[…], prompt_id=…)` then runs it on exactly those pictures.
- Waiting: `job_wait(job_id, timeout_s=55)` — one picture ≈ 1.5 min, ten ≈ 4 min; each call re-sends the conversation, so use the full 55 s.
- Budget: `resolution` is the per-picture pixel side (default PRO 6000 2048, GB10 1024); the node's total is capped (21 MP / 10.5 MP) and lowered automatically — the reply says so. More pictures = longer: one ≈ 1.5 min, ten ≈ 4 min on the PRO 6000.
- Six or more people composed into one scene: identities may mix (measured 2026-09-23); do not promise a one-to-one likeness. Up to five references (one person + four garments, ten furniture pieces) were reliable.
- Check an edit side by side with the original (§3): "only change X" is not proven by one score.
