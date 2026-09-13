# Sources and scope of the media skills

Checked 2026-09-13. The five vagaa skills are project-maintained integration guidance. They are not MiniMax, ComfyUI, or Anthropic official skills.

Read the relevant source when changing a model workflow or prompt format, rather than loading all vendor guidance into every request:

- **Vendor-official H3 prompting skill:** [MiniMax-AI H3 Prompt Writing](https://github.com/MiniMax-AI/MiniMax-H3/tree/main/skills/h3-prompt-writing). Its entrypoint selects a base-mode or full-reference guide. [Entrypoint](https://raw.githubusercontent.com/MiniMax-AI/MiniMax-H3/main/skills/h3-prompt-writing/SKILL.md), [base-mode reference](https://raw.githubusercontent.com/MiniMax-AI/MiniMax-H3/main/skills/h3-prompt-writing/references/base-en.txt), [full-reference reference](https://raw.githubusercontent.com/MiniMax-AI/MiniMax-H3/main/skills/h3-prompt-writing/references/ref-en.txt). Vendor model modes are broader than this gateway's `prompt_rewrite` coverage; consult live profiles before submitting.
- **ComfyUI official example graph:** [H3 T2V workflow](https://github.com/Comfy-Org/workflow_templates/blob/main/templates/video_minimax_h3_t2v.json). Node IDs, model files and installed versions still need checking on the target node.
- **ACE-Step publisher skills:** [ace-step/ace-step-skills](https://github.com/ace-step/ace-step-skills) provides generation and documentation skills, with API references loaded on demand. These target the ACE-Step API; this deployment's `music_submit` uses ComfyUI. Borrow applicable music guidance, but do not import API commands or claim its continuation/repainting features are exposed here.
- **Community director integration, maintained by its author:** [AIMixer/ComfyUI_MiniMaxH3_Director](https://github.com/AIMixer/ComfyUI_MiniMaxH3_Director). Its source and examples describe timeline inputs and segment continuation. It builds on official H3 nodes; AIMixer is not the model vendor.
- **Harness contracts:** [Claude Code hooks](https://code.claude.com/docs/en/hooks), [Claude Code skills and on-demand loading](https://code.claude.com/docs/en/skills), [MCP tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools). Verify the actual Claude Code loader and hook runner as well as the manifest.

Paths such as `reference/research/...` and `tools/evals/...` in the specialist skills identify historical evidence in the private DGX deploy repository, not files bundled with this plugin. They are provenance, not required reads for a plugin consumer. Do not invent their contents or claim their old measurements were reproduced. For new aesthetic or continuity changes, study relevant human workflows, compare actual rendered candidates, retain the baseline and roll back a failed experiment.

Machine review, frame-boundary metrics and human taste answer different questions. Report each separately; passing a seam check does not establish narrative or aesthetic quality.
