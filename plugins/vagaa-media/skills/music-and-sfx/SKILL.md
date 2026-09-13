---
name: music-and-sfx
description: Use to generate background music or sound effects, plan sound and music separately, and identify the current limits of audio mixing and level control; use media-production for spoken narration and translation.
verified_against: media-mcp 0.7.21 (2026-09-13)
shared_facts: ../_shared/cluster-facts.md
shared_facts_sha256: ab2c5b611ed611087a6ee46401c5d3f185d7e49c0ad7f531afd25cb2c820f0c9
---

# Music and sound effects (ACE-Step + Stable Audio 3 on comfy2)

Facts (limits, node, timings): `../_shared/cluster-facts.md`. Spoken narration (`tts`) and translation belong to `media-production`;
assembling a whole film (per-shot clips, seams) belongs to `storyboard-longform`.
Publisher skills and their API differences: `../_shared/provenance.md`; read the ACE-Step guidance when changing the music workflow.

## 1. BGM
`music_submit(prompt=<style / instrument / mood tags>, preset="bgm-draft", seconds=30, seed=<fixed>, bpm=<int>, key="A minor")` → poll
`music_status(job_id)` → `music_fetch(job_id)` (MP3). Draft is 30 s and cheap (ACE-Step 1.5 turbo, 8 steps): run a lottery (`seeds=[...]`, ≤ 8), pick
by ear / rubric, then re-submit the **same prompt + seed + bpm + key** on `preset="bgm-final"` with the real length (60–300 s, FLAC). Never lottery on
`bgm-final`. Lyrics: omit `lyrics` (or `instrumental=true`) for instrumental cues; otherwise pass `[Verse]` / `[Chorus]`-tagged lyrics.

## 2. SFX
`music_submit(prompt=<describe the sound, not music>, preset="sfx", seconds=4, seed=<fixed>)` → FLAC (Stable Audio 3 small-sfx; no lyrics / bpm /
key). Two to eight seconds is a typical short cue, not the accepted duration limit: current SFX accepts 1–60 seconds; verify the live schema/preset before choosing the required length. A multi-seed lottery is normal for SFX. Loops: ask for "seamless loop" and cross-fade in the editor; sample-exact loops are not guaranteed.

## 3. Levels and mixing — what exists today
- H3 clips carry their own generated audio and come out quiet (≈ −34 dB in a reference measurement). Loudness normalisation, mixing a BGM under a
  clip and burning subtitles are **not exposed as MCP tools** in the verified deployment. Hand the clip and the music
  asset URLs to the user's editor with the target level; do not claim a mix was made.
- When a mix must happen on the cluster anyway, `workflow_submit` with an operator-provided ffmpeg / ComfyUI audio graph is the only route; say so.

## 4. Queueing reality
Music models live only on `comfy2` (spark-03), so a music job queues behind any H3 draft or final running there: submit BGM / SFX first or accept the
wait; `music_status` shows `queue_position`. Record seeds, preset and runtime for comparisons; do not promise bitwise reproducibility. Cloud music preset `fun-music` is unkeyed (money, no
lottery, not retried on `backend_rejected`).
