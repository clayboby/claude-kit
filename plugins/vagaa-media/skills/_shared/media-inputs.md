# Media inputs and delivery links

Contracts aligned with media-mcp 0.7.21 on 2026-09-13; deployment verification is recorded in the release ledger. Read this reference when reusing an asset or delivering a browser link; the live tool schema remains authoritative.

| Tool / purpose | Argument and supported value |
|---|---|
| `image_review`, `video_review`, `reverse_prompt` | `source`: an asset id (`as-…`), a `job_id` (no need to fetch it first) or an allowlisted HTTP(S) URL; the parameter is `source`, not `job_id=`; not the authenticated stable asset URL as a link |
| `video_submit` optional image input | Only a preset that actually supports `image_url` may use an allowlisted URL; Comfy presets expose `presets_list.video[preset].image_url_supported`. Current local `draft`, `preset="director_t2v"`, `fast`, `daily`, `quality` are T2V and reject it. For local image-to-video pass `first_frame` (asset id / picture job id / allowlisted URL; presets `draft` / `fast`, a plain `prompt` of the motion) or use Director fl2v |
| `director_run` | Segment `first_frame`, `last_frame`, `ref_images`, `ref_audios`, `source_video`: appropriate-kind asset IDs, completed job IDs or allowlisted URLs |
| Director mode compatibility | First/last frames require fl2v; reference images/audio require r2v; source video requires v2v. `ref_videos` is unsupported and is rejected. Unknown fields are rejected before media I/O |
| `storyboard_plan_update` → `storyboard_direct` | Store a character image reference in `ref_image_url`; asset IDs are supported and avoid URL expiry. Voice references belong to `director_run`'s character/segment inputs; do not invent `ref_audio_url` on a storyboard character |
| `director_pack_import` | `pack_asset` for a stored pack asset, or `pack_url` on an allowlisted host |
| The person's own file (`asset_upload`, scope `assets.upload`) | `data_base64` (or an allowlisted `url`) → an `as-…` id private to the uploading token, 7-day draft (kept once a cover or a director run reads it). 0.8.11: a picture (png / jpeg / webp ≤ 20 MiB, re-encoded without metadata) feeds `image_edit.images` and Director frames; audio (mp3 / wav / m4a / flac ≤ 30 MiB, 240 s) feeds a `music_submit` cover. `presets_list().asset_upload.kinds` says which kinds this server takes |
| Browser delivery | A fetch's `url`, or `asset_get(asset_id, presign=true)` → `presigned_url`. Temporary, opens without a Bearer; preserve the complete query and percent encoding |
| Stable records | `asset_id`, `job_id`, `asset_url`. The stable URL needs Bearer/LAN authorization; an anonymous 404 does not prove the asset is gone |

The admin console uses its own same-origin signed asset links. This does not make the unsigned `asset_url` public. Re-fetch to renew a temporary link; do not reconstruct or decode an S3 signature.
`asset_tag` edits tags with `add`/`remove`, not `tags`. `assets_search(tags=[...])` is a search filter, not the tagging contract. Hiding is not a tag: `asset_set_in_library(asset_id, in_library=false)` makes a work «hidden» (= not in the library, left out of every search and list; `asset_get` still reads it).

`idempotency_key` is scoped to the caller/token, and replays its first accepted request when the arguments are the same (`idempotent_replay: true`); the same key with DIFFERENT arguments is refused (`idempotency_conflict`), never answered with the first result. Keep the key for a transport retry; use a new key for a new take or corrected parameters.

Stable URLs do not override retention. Preserve an approved draft with a star or a collection before calling it a kept deliverable. Report manual-recovery states explicitly and resolve the original job before resubmitting.

These are project integration skills, not vendor-official skills. Model-specific guidance and experiments belong in the specialist skill; protocol details do not establish artistic quality.
