---
name: video-prompting
description: Load BEFORE writing, rewriting or diagnosing a MiniMax-H3 video prompt: spoken dialogue, on-screen text, camera moves, style words, reference-aware wording, seed A/B, why a clip came out wrong. 中文触发：提示词、怎么写、画面文字、店名要出现在画面里、台词、对白、运镜、换个 seed、为什么不像、优化一下描述。Uses prompt_rewrite for T2V drafts and explains what the local grammar accepts.
verified_against: media-mcp 0.8.3 (2026-09-23)
shared_facts: ../_shared/cluster-facts.md
shared_facts_sha256: 852c74d3d4cd7dff25dd7e44e616e64e1d425bf1f2c831e9370f946163829431
when_to_use: 要写或改视频提示词、要画面里出现文字、要台词、要解释为什么生成得不对时加载。
---

Vendor guidance and the scope of historical evidence: `../_shared/provenance.md` (read when changing workflows).

# Writing video prompts for MiniMax-H3 (single clip)

This skill produces PROMPT TEXT (or a `prompt_id`). It never generates by itself: when the task is "write / fix / compare the prompt", stop
after handing over the text or id; `media-production` owns submitting, reviewing and finals. Facts (presets, timings, error codes):
`../_shared/cluster-facts.md`. Multi-shot planning, cross-shot continuity and resume: `storyboard-longform`.

## 1. The grammar H3 reads (what a finished prompt looks like)
```
integrated_multimodal_description: <one English paragraph: shot size + camera move, subject (age, clothes, expression), the action beat by beat,
setting, light and colour; a cut is "the camera cuts to ..." inside the same paragraph>
overall_soundscape: <1-4 sentences of diegetic sound, or N/A>
non_diegetic_music: <1-3 sentences: instruments, tempo, dynamics; or N/A>
```
- Preserve the brief's audio requirements: a closed list of allowed sounds excludes added room tone or ambience. No dialogue, no music and complete silence are different requests; do not impose silence on a brief that asks for sound. Use `N/A` for a silent soundscape or absent non-diegetic music as appropriate; source music heard within the scene belongs in the integrated description.
- **Score for a multi-segment film goes in post, not per segment**: H3 writes a different piece for every segment it renders (held-out skate film 2026-09-17: 0–10 s and 10–20 s were two unrelated tracks, user: "极其突兀"). In a `director_run` plan write `non_diegetic_music: N/A` in every segment and add ONE track afterwards with `video_audio_level(music=<music_submit asset>)` (0.7.51). A single-clip `video_submit` may still ask for music in its own text.
- **Spoken words** go inside the dialogue tag with a language label; who speaks and how stays outside it:
  `(S1) The vendor says warmly: <d>[Chinese] 来,刚烤好的,趁热吃</d>`, `(S2) She whispers: <d>[English] Don't look back.</d>`.
  Copy the line character for character (same punctuation, same spaces, no translation). Stable ids `S1`, `S2`, … for speakers only.
- **Visible text** (sign, label, title card) goes in English double quotes: `a neon sign reads "OPEN 24H"`. Nothing else goes in quotes:
  quoted dialogue was burned in as subtitles in a 2026-09-05 sample. Avoiding quotes is a risk reduction, not a guarantee that no text appears; inspect the output.
- Off-screen voice: `<name> says in an off-screen voiceover: <d>[...] ...</d>` and note that the visible lips stay closed.
- Base-mode control tags are `<d>`, `<scenetrans>`, `<cutoff>`; reference mode also uses `<Picture N>`, `<Audio N>`, `<Video N>` bindings. Read the official reference guide for r2v and check the gateway accepts that media kind. Description in English; dialogue keeps its language.
- The gateway `prompt_rewrite` profile covers Chinese/English dialogue and rejects other scripts with `unsupported_language`; this is not a statement that direct H3 generation supports only those languages.

## 2. Rewrite instead of guessing: `prompt_rewrite`
```
prompt_rewrite(text=<brief or prompt>, target={"tool": "video_submit", "preset": "draft"}, mode="t2v", seconds=5,
               language_policy={"description_language": "en"}, protected_content={"dialogue": [...], "screen_text": [...]},
               profile_version=None, on_failure="error", force=false)
# profile_version="1.0.1" (0.6.1, experimental): the same H3 rules plus locked brief elements (place, people, time, mood, action) and a
# text-level faithfulness judge — one extra LLM call; an unfaithful rewrite is retried once with the judge's issues, then fails. Use it
# when the brief names a specific place or mood the model tends to dramatise. Default stays 1.0.0 until 1.0.1 passes its own T3.
```
- Covered in 0.6.0: H3 `draft`, `t2v`, 5 s, dialogue zh/en. Other presets, `seconds`, modes (i2v / fl2v / ref2v) or any `references` are refused
  (`unsupported_target` / `unsupported_references`) — write those prompts by hand with §1 and say so; do not pretend the tool covered them.
- Deterministic first: a prompt that already IS the grammar comes back `status: unchanged` verbatim with zero LLM calls; a partially structured one is
  kept verbatim with `warnings[].code == partial_structure` (pass `force=true` to rewrite it); a plain brief is rewritten (≤ 2 attempts).
- Protected content is checked VERBATIM after the rewrite: every quoted span in the brief is a spoken line (a signage cue — "sign says", "招牌上写着" —
  makes it on-screen text); `protected_content` settles ambiguous cases. A failure raises `rewrite_failed` and keeps the attempts under the returned
  `prompt_id`; `on_failure="raw"` returns your own words as `status: fallback_raw` instead.
- Reply fields worth reading: `prompt`, `prompt_id`, `profile{id,version,sha256}`, `validation.errors/warnings`, `attempts`, `usage`, `timings`.
  `prompt_get(prompt_id)` returns the same plus the execution snapshot (messages, model revision, sampling) and the jobs that used it.
- A hand-written prompt submitted with `rewrite="off"` creates no rewrite artifact. Preserve that prompt and the original brief with the job; do not invent a `prompt_id` or schedule `prompt_get`/profile validation for that path.
- Hand over `prompt_id` to `video_submit(prompt_id=..., preset="draft", seed=...)`; it is bound to `draft` (reusable unchanged on `fast`/`daily`/
  `quality`, same 5 s) and is never rewritten again. `presets_list` → `prompt_rewrite.supported` is the live coverage table.

## 3. Diagnosing a bad clip (with `video_review`)
| symptom | usual cause | fix in the prompt |
|---|---|---|
| dialogue burned in as subtitles / garbled text | line written in quotes, or the word "subtitle" | move the line into `<d>[Language] ...</d>`, drop quotes |
| wrong language spoken | wrong `[Language]` tag or a translated line | tag = the line's language, copy the line verbatim |
| character drifts (clothes, age) | vague subject line | one explicit subject sentence: age, build, clothing, colour |
| action not performed | two actions in one clause | one beat per sentence, in playback order |
| the one action written happens only in the last second, nothing follows | only the first beat of a chain was written ("She picks up the cup." → pick-up at t≈4–4.5 s, 2/2 seeds; P line 2026-09-17) | write EVERY beat that must happen, in order — "picks up the cup, then takes a sip, then puts it down": 3/3 on both seeds whether written with "then", as three sentences, with time codes (kept to ±0.5 s) or as a three-segment chain; the writing style made no difference, completeness did |
| closing beat blows up (grabs or lifts the prop, yanks the lamp, loud thump, toothy grin) | any hand action written into the last continued segment; wording like "gentle", "quiet", "closed-mouth" did not restrain it across three seeds-identical retries (C03 v1–v3, 2026-09-15) | make the closing beat hand-free: posture, breath, eyes, a faint closed-mouth smile; keep props untouched (C03 v4/v5 passed) |
| black bars left and right (a product / still-life shot rendered as a narrow frame inside the 16:9 canvas) | seed-bound: the same prompt on another seed fills the frame; adding "no black borders / no letterboxing / no pillarboxing" to the prompt changed nothing (C02 purple-jar, seed 9132006 vs 9132016, `reference/c02-styles-20260915`) | keep the prompt, change the seed; do not spend a run on negative wording |
| audio clips at 0 dB / later shots far louder than the first (level wording did not help in two same-seed re-renders — C04 v3 "no louder than the other shots", S9 v2 "exactly the same constant level" came back unchanged; n=2, provisional — finish with `video_audio_level`) | every shot's soundscape stacks several sources (street traffic + tools + voices) and nothing says "quiet"; H3 mixes them at full scale (C04 2026-09-16: shots 4–6 at −0…−6 dB peak, user: "后续配音有问题") | one or two quiet diegetic sources per shot, the loudest named once ("only a soft brush of cloth on leather; distant street, faint"); check `max_volume` with ffmpeg before delivery |
| sound does not match the brief | soundscape repeats dialogue or adds unrequested layers | requested diegetic sounds in `overall_soundscape`; requested background score in `non_diegetic_music`; keep source music inside the scene description |
| a causal event never happens across cut-style segments (the bag is knocked in one shot, the next shot pours flour by itself) | each `continuity=false` segment samples its own action; wording did not fix it in two versions (held-out Flour Crown 2026-09-17, director and storyboard) | keep the event inside ONE segment, and when it must connect to other shots stage it as a keyframe chain: first frame = state before, last frame = `image_edit` of the SAME image changing only the result, the event in one `fl2v` segment. L2 line 2026-09-17 (knock a mug / hand over keys / switch a light on, 2 seeds each): same-source end frame 6/6 on every criterion; an end frame generated separately 5/6 turned into a hard cut, a dissolve or a costume change; **first frame alone (i2v) 0/6 — the clip returns to its first frame by the end**; plain t2v 6/6 for a single-subject fixed-shot micro-event. Sound events (a hum that stops) are cut in post, not prompted |

## 4. A/B two prompts honestly
Same preset, same `seconds`, same `seed`, submitted back to back so both land on the same node when possible (check `backend` in each job); review both
with `video_review(source=job_id, prompt=<the original brief>)` so the reviewer sees the same brief, not the candidate text. One seed is a lead, not a
statistic — `media-mcp/tools/prompt_ab.py` runs the paired protocol (random order, blinded review, hard generation cap); report deltas per brief.

## 6. Multi-segment or media-driven clips: hand the plan to `director_run` (0.7.0)
Prompt text from this skill goes into `director_run(segments=[{prompt, seconds, …}])` when the piece has more than one beat, needs a first/last frame,
a reference face/voice, or a source video; see `storyboard-longform` §6 for the call shape. One rule of thumb for the prompt of a continued
segment: describe the new beat only ("He turns to the camera and grins."), the previous segment's motion is carried over by the node.
Put the look (medium, palette, lens) in `style` once — it is prefixed to every segment — and keep segment prompts to action, sound and dialogue.
Poll `director_status(run_id)`, then `director_fetch(run_id)`.
With a `characters` table you can write `@别名` for a reference face and `别名: 台词` / `旁白: 台词` for spoken lines — the server expands them
into `<Picture N>` / `<d>[Language] …</d>` (storyboard-longform §6 has the call shape); keep writing full H3 grammar when you need control.
