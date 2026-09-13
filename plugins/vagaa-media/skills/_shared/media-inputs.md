# Media inputs and delivery links

Contracts checked for media-mcp 0.7.20 on 2026-09-13. Read this reference when reusing an asset or delivering a browser link; the live tool schema remains authoritative.

| Tool / purpose | Argument and supported value |
|---|---|
| `image_review`, `video_review`, `reverse_prompt` | `source`: a completed `job_id` or an allowlisted HTTP(S) URL; not `job_id=` as a parameter, not a bare `asset_id`, not the authenticated stable asset URL |
| `video_submit` image-to-video | `image_url`: an allowlisted HTTP(S) URL. It has no `first_frame` alias. Use the returned presigned URL without changing its encoding |
| `director_run` | Segment `first_frame`, `last_frame`, `ref_images`, `ref_audios`, `source_video`: appropriate-kind asset IDs, completed job IDs or allowlisted URLs |
| Director mode compatibility | First/last frames require fl2v; reference images/audio require r2v; source video requires v2v. `ref_videos` is unsupported and is rejected. Unknown fields are rejected before media I/O |
| `storyboard_plan_update` → `storyboard_direct` | Store a character image reference in `ref_image_url`; asset IDs are supported and avoid URL expiry. Voice references belong to `director_run`'s character/segment inputs; do not invent `ref_audio_url` on a storyboard character |
| `director_pack_import` | `pack_asset` for a stored pack asset, or `pack_url` on an allowlisted host |
| Browser delivery | A fetch's `url`, or `asset_get(asset_id, presign=true)` → `presigned_url`. Temporary, opens without a Bearer; preserve the complete query and percent encoding |
| Stable records | `asset_id`, `job_id`, `asset_url`. The stable URL needs Bearer/LAN authorization; an anonymous 404 does not prove the asset is gone |

The admin console uses its own same-origin signed asset links. This does not make the unsigned `asset_url` public. Re-fetch to renew a temporary link; do not reconstruct or decode an S3 signature.
`asset_tag` edits tags with `add`/`remove`, not `tags`. `assets_search(tags=[...])` is a search filter, not the tagging contract.

`idempotency_key` is scoped to the caller/token, and replays its first accepted request. The current server does not compare changed prompt/options with the original body. Keep the key for a transport retry; use a new key for a new take or corrected parameters.

Stable URLs do not override retention. Preserve an approved draft with a star or a collection before calling it a kept deliverable. Report manual-recovery states explicitly and resolve the original job before resubmitting.

These are project integration skills, not vendor-official skills. Model-specific guidance and experiments belong in the specialist skill; protocol details do not establish artistic quality.
