---
name: music-and-sfx
description: Load for background music, BGM, soundtrack, jingle, beat/rhythm track, sound effects or ambience for a video. 中文触发：配乐、背景音乐、BGM、音效、环境音、卡点音乐、来段音乐、vlog 开头那种。Plans music and SFX separately (music_submit presets bgm-draft/bgm-final/sfx), explains mixing limits. NOT for narration or spoken lines — that is tts in media-production.
verified_against: media-mcp 0.7.33 (2026-09-15)
shared_facts: ../_shared/cluster-facts.md
shared_facts_sha256: 14352cbee7d70dd8a43326b3f017f499182c01134736f077b3b54236a217d9e6
when_to_use: 用户要音乐、音效、氛围声时加载；要人声旁白/台词时不加载本 skill。
---

# Music and sound effects (ACE-Step + Stable Audio 3 on comfy2)

Facts (limits, node, timings): `../_shared/cluster-facts.md`. Spoken narration (`tts`) and translation belong to `media-production`;
assembling a whole film (per-shot clips, seams) belongs to `storyboard-longform`.
Publisher skills and their API differences: `../_shared/provenance.md`; read the ACE-Step guidance when changing the music workflow.
Use the current brief's sound requirements: a closed list of permitted sounds excludes added ambience or room tone. No dialogue, no music and complete silence are different constraints; do not add a score or impose silence by default. Verify requested audio in the original media, not from an image-based review score.

## 1. BGM
`music_submit(prompt=<style / instrument / mood tags>, preset="bgm-draft", seconds=30, seed=<fixed>, bpm=<int>, key="A minor")` → poll
`music_status(job_id)` → `music_fetch(job_id)` (MP3). Draft is 30 s and cheap (ACE-Step 1.5 turbo, 8 steps): run a lottery (`seeds=[...]`, ≤ 8), pick
by ear / rubric, then re-submit the **same prompt + seed + bpm + key** on `preset="bgm-final"` with the real length (60–300 s, FLAC). Never lottery on
`bgm-final`. Lyrics: omit `lyrics` (or `instrumental=true`) for instrumental cues; otherwise pass `[Verse]` / `[Chorus]`-tagged lyrics.

## 2. SFX
`music_submit(prompt=<describe the sound, not music>, preset="sfx", seconds=4, seed=<fixed>)` → FLAC (Stable Audio 3 small-sfx; no lyrics / bpm /
key). Current SFX accepts 1–60 seconds; verify the live schema/preset before choosing the required length. Two to eight seconds is only a typical short cue. A multi-seed lottery is normal for SFX. Loops: ask for "seamless loop" and cross-fade in the editor; sample-exact loops are not guaranteed.

## 3. Levels and mixing — what exists today
- H3 clips carry their own generated audio and come out quiet (≈ −34 dB in a reference measurement). Loudness normalisation, mixing a BGM under a
  clip and burning subtitles are **not exposed as MCP tools** in the verified deployment. Hand the clip and the music
  asset URLs to the user's editor with the target level; do not claim a mix was made.
- When a mix must happen on the cluster anyway, `workflow_submit` with an operator-provided ffmpeg / ComfyUI audio graph is the only route; say so.

## 4. Queueing reality
Music models live only on `comfy2` (spark-03), so a music job queues behind any H3 draft or final running there: submit BGM / SFX first or accept the
wait; `music_status` shows `queue_position`. Record seeds, preset and runtime for comparisons; do not promise bitwise reproducibility. Cloud music preset `fun-music` is unkeyed (money, no
lottery, not retried on `backend_rejected`).\n\n## Beat-synced cuts (0.7.32)\n`beat_grid(audio=<music asset id / job id / URL>, bpm_hint?, fps=24, beats_per_shot=[1,2,4,8])` returns bpm, beat times, downbeats, `cut_frames` and a shot-length table with the nearest H3 17n+5 frame count and its error. Plan 2–5 s shots that END on beats (official MV skill: cut on snare / drop / phrase, hard cuts only), render each at `h3_frames`, then trim to `cut_frames` in post. Music first, video second.\n