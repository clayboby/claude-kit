---
name: music-and-sfx
description: Load for background music, BGM, soundtrack, jingle, beat/rhythm track, sound effects or ambience for a video, and for a SONG with vocals or a COVER of an existing song (YuE2). 中文触发：配乐、背景音乐、BGM、音效、环境音、卡点音乐、来段音乐、vlog 开头那种、写首歌、唱出来、翻唱、换个风格唱、用这首歌的旋律。Plans music and SFX separately (music_submit presets bgm-draft/bgm-final/sfx; mode song/cover + asset_upload for songs), explains mixing limits. NOT for narration or spoken lines — that is tts in media-production.
verified_against: media-mcp 0.8.7 (2026-09-26)
shared_facts: ../_shared/cluster-facts.md
shared_facts_sha256: 6a7f507ceb7ff0ce13700c64aead5cb82f10ad6383b6190d6cdae3c5ac2b4a32
when_to_use: 用户要音乐、音效、氛围声时加载；要人声旁白/台词时不加载本 skill。
---

# Music, songs and sound effects (YuE2 + ACE-Step + Stable Audio 3 on comfy2)

## 0. Which engine (decide first)
- A **song someone sings** (lyrics, a vocal, a whole track) → YuE2: `music_submit(mode="song")` (§5). Re-singing an **existing song** in a new style → `mode="cover"` (§5).
- **BGM / cue / loop / jingle under a video** (no vocal needed) → ACE-Step `bgm-draft` → `bgm-final` (§1). A **sound / ambience** → Stable Audio 3 `sfx` (§2).
- Never point YuE2 at BGM (3–5× slower, no bpm/key/loop control) and never ask ACE for a vocal song or a cover (MUSIC1 eval: YuE2 6.73 vs ACE 6.01 on WildSongBench; cover mAP 0.647 vs 0.024).

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

## 3. Levels and mixing — `video_audio_level` (0.7.49–0.7.51)
- H3 clips carry their own generated audio, uneven between shots and often quiet. `video_audio_level(source)` levels each shot to `target_lufs` (−20) with true-peak headroom and fades the cuts (no bed by default, 0.7.53); `music=<asset>` mixes ONE track under the whole film (trimmed, 0.3 s in / 1.5 s out, never looped, `music_db` −14 by default), `ambience=<asset ≥ film length>` replaces the self-bed with a generated room tone (`sfx` preset, 30–60 s, "constant and even, no events") at `bed_db`. Music, bed and shots are budgeted together so the mix never passes −2 dBTP; the result's `mix_true_peak_dbtp` says what came out.
- Ask for the music with `music_submit` first (`bgm-draft` → `bgm-final`, same seed), then level; do not write a score into each director segment (each segment gets its own piece). A bed is a taste decision, not a default: `bed_from_shot` (the film's own audio looped) is not recommended — it carried a wrong shot-1 texture over all of C04 (2026-09-17); if a bed is wanted, generate a neutral room tone and pass `ambience=` at `bed_db` −6 or lower, and listen before delivering.
- Burning subtitles and a delivery-loudness master pass (−14 LUFS / −1.5 dBTP for YouTube-style platforms; 0.7.52 candidate) are **not exposed as MCP tools** in the verified deployment; hand the clip and text to the editor and say so rather than claiming a mix was mastered.

## 4. Queueing reality
Music models live only on `comfy2` (spark-03), so a music job queues behind any H3 draft or final running there: submit BGM / SFX first or accept the
wait; `music_status` shows `queue_position`. Record seeds, preset and runtime for comparisons; do not promise bitwise reproducibility. Cloud music preset `fun-music` is unkeyed (money, no
lottery, not retried on `backend_rejected`).\n\n## Beat-synced cuts (0.7.32)\n`beat_grid(audio=<music asset id / job id / URL>, bpm_hint?, fps=24, beats_per_shot=[1,2,4,8])` returns bpm, beat times, downbeats, `cut_frames` and a shot-length table with the nearest H3 17n+5 frame count and its error. Plan 2–5 s shots that END on beats (official MV skill: cut on snare / drop / phrase, hard cuts only), render each at `h3_frames`, then trim to `cut_frames` in post. Music first, video second.\n\n`beat_cut(clips=[...], audio, beats_per_shot=[4], plan_only=true)` first returns the shot plan and `seconds` vs `music_seconds` without rendering — tune `beats_per_shot` / clip count / `max_seconds` there (the cut can never be longer than the music); then call it ONCE with `plan_only=false`: it assembles the clips on those beats (hard cuts, music from t=0) into one workflow job + asset and reports each cut's error. Do not re-render the same request to "check" it: an identical call within an hour returns the film already made. Render clips a little longer than their beats.\n

## 5. Songs and covers — YuE2-3B (MUSIC2, comfy2 only)
When: the person wants a song that is SUNG (lyrics, a vocal, a whole track), or an existing song re-sung in another style. Not for BGM / cues (§1) or sounds (§2). No voice cloning, no vocal separation, no "in X's voice": a cover is a new performance on the source's melody.

| call | when | parameters |
|---|---|---|
| `music_submit(mode="song", prompt=<style line>, lyrics=<sectioned lyrics>, seed=<fixed>)` | a new song from words | `prompt` ONE line: language, genre, vocal, tempo, instruments ("Chinese, city pop, warm female vocal, 96 BPM, Rhodes"); `lyrics` REQUIRED in `[Verse]` / `[Chorus]` / `[Bridge]` / `[Outro]` blocks (`instrumental`, `bpm`, `key` are refused — put tempo / key in the line); `quant` int8 (default, ≈1.7× realtime) \| bf16 (reference, ≈1×); `cot` full (default) \| melody \| off (no plan, faster); `seconds` = cap (default 240, the plan may end earlier); `seeds` lottery as §1 |
| `asset_upload(data_base64=<file>, filename=..)` | the person hands over a song / recording to cover | mp3 / wav / m4a / flac, ≤ 30 MiB, ≤ 240 s; or `url` on an allow-listed host; returns `asset_id`. DRM tracks (Apple Music, QQ 音乐, 网易云) cannot be uploaded — ask for a real file or a recording |
| `music_submit(mode="cover", source=<asset_id>, prompt=<target style line>, lyrics=<sectioned lyrics>)` | re-sing that source in a new style | `source` = the upload, a finished `music_submit` job or an `assets_search` hit; `cot` melody (default) \| full; `denoise=true` for a hummed / phone recording; keep phrasing and syllable count close to the original (translate to syllables first) |

Then `music_status` / `job_wait` → `music_fetch` (FLAC 48 kHz, 3–4 min for a 3-minute song: poll, never resubmit). Delivery is normalised to −14 LUFS / −1 dBTP; `asset_get` → `params.loudness` (measured → delivered), `params.abc` (plan / transcription), `params.source_asset_id`. Whether the words are sung right and the melody kept is for the person's ear: hand over the URL, do not claim it.
