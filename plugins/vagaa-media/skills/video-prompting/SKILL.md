---
name: video-prompting
description: Use to write, rewrite, diagnose, or A/B-test video prompts for a selected preset, including spoken dialogue, visible text, and reference-aware descriptions; use storyboard-longform for shot planning and continuity.
verified_against: media-mcp 0.6.3 (2026-09-07)
shared_facts: ../_shared/cluster-facts.md
shared_facts_sha256: 7d364005ed4a335557afc36ef0b39191a9b81b3ecfc5b8b23c2d348fc91485d2
---

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
- **Spoken words** go inside the dialogue tag with a language label; who speaks and how stays outside it:
  `(S1) The vendor says warmly: <d>[Chinese] 来,刚烤好的,趁热吃</d>`, `(S2) She whispers: <d>[English] Don't look back.</d>`.
  Copy the line character for character (same punctuation, same spaces, no translation). Stable ids `S1`, `S2`, … for speakers only.
- **Visible text** (sign, label, title card) goes in English double quotes: `a neon sign reads "OPEN 24H"`. Nothing else goes in quotes:
  quoted dialogue was burned in as subtitles in the 2026-09-05 A/B sample (raw 3.0 vs rewritten 4.3). Do not mention subtitles/captions unless asked.
- Off-screen voice: `<name> says in an off-screen voiceover: <d>[...] ...</d>` and note that the visible lips stay closed.
- Only `<d>`, `<scenetrans>`, `<cutoff>` are tags; anything else in angle brackets is an error. Description in English; dialogue keeps its language.
- Chinese and English dialogue are covered. A line in another script (Japanese, Korean, Cyrillic, …) is refused with `unsupported_language`.

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
- Hand over `prompt_id` to `video_submit(prompt_id=..., preset="draft", seed=...)`; it is bound to `draft` (reusable unchanged on `fast`/`daily`/
  `quality`, same 5 s) and is never rewritten again. `presets_list` → `prompt_rewrite.supported` is the live coverage table.

## 3. Diagnosing a bad clip (with `video_review`)
| symptom | usual cause | fix in the prompt |
|---|---|---|
| dialogue burned in as subtitles / garbled text | line written in quotes, or the word "subtitle" | move the line into `<d>[Language] ...</d>`, drop quotes |
| wrong language spoken | wrong `[Language]` tag or a translated line | tag = the line's language, copy the line verbatim |
| character drifts (clothes, age) | vague subject line | one explicit subject sentence: age, build, clothing, colour |
| action not performed | two actions in one clause | one beat per sentence, in playback order |
| flat sound | soundscape repeats the dialogue or names music | ambience only in `overall_soundscape`, music only in `non_diegetic_music` |

## 4. A/B two prompts honestly
Same preset, same `seconds`, same `seed`, submitted back to back so both land on the same node when possible (check `backend` in each job); review both
with `video_review(job_id, prompt=<the original brief>)` so the reviewer sees the same brief, not the candidate text. One seed is a lead, not a
statistic — `media-mcp/tools/prompt_ab.py` runs the paired protocol (random order, blinded review, hard generation cap); report deltas per brief.
