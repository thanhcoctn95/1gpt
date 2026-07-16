# Pikit Global Agent Rules

These rules apply to ordinary chat, slash workflows, and subagents in projects that use the Pikit pack.

## Behavioral Kernel

Always-on execution loop for non-trivial work. It stays active even when the rest of the prompt is noisy. For trivial one-liners, use judgment.

1. Clarify before committing. Surface assumptions or ask instead of silently choosing one interpretation from several valid readings. If a simpler approach exists, say so.
2. Choose the smallest working change. Solve today's problem directly before inventing flexibility; no speculative abstractions or error handling for impossible scenarios.
3. Keep diffs surgical. Every changed line traces to the current request and matches existing style. Log unrelated issues as `NOTICED BUT NOT TOUCHING: ...` and keep moving.
4. Define proof before acting. Name the success check (command, test path, or evidence) before implementing, then run that proof after.

When you catch yourself adding abstraction for a single use case, editing adjacent code "while you're here", postponing verification, or claiming completion without a named proof path, stop and re-center on this kernel. See `.pi/skills/context/behavioral-kernel/SKILL.md` for the deep version with examples.

## Start-of-Work Routing

Before substantive, non-trivial work, classify the request internally. Surface a routing summary to the user only when the work is non-trivial or ambiguous; skip it for small, obvious changes and trivial acknowledgements. When you do surface it, prefer a few bullets over a full table.

## Report Formatting

Use the right format for the kind of content. Default to prose and bullet lists. Do not default to tables for everything — reserve tables for genuinely comparative or tabular content.

| Rule | Requirement |
| --- | --- |
| Default format | Prose and bullet lists (`-`). Tables are the exception, not the default. |
| Comparisons / mappings | Use Markdown pipe tables only for genuinely tabular content (items × attributes, status matrices, before/after, pros/cons, agent-to-role mapping). |
| Listings | Use bullet lists (`-`) for simple enumerations (tasks, files, findings, criteria, items). Do not wrap a single-column list in a table. |
| Sequential steps | Use numbered lists (`1.`) for ordered phases, procedures, or processes. |
| Field checklists | When a workflow lists required fields, render them as bullets by default; promote to a table only when columns add comparison value. |
| Unicode box tables | Do not use box-drawing tables such as `┌`, `┬`, `│`, `└`, or `─`. |
| Code fences | Do not use fenced code blocks in final reports unless the user explicitly asks for raw file/script/log content. |
| Commands and paths | Put short commands, paths, hashes, and examples inline inside Markdown table cells or list items. |
| Formatter compatibility | Keep Markdown tables outside code fences so `markdown-table` can normalize them. |

## Safety and Verification

| Rule | Requirement |
| --- | --- |
| Scope | Keep changes limited to the user request. |
| User changes | Never revert unrelated user work without explicit approval. |
| Git | Do not commit, push, tag, reset, clean, or force-push unless explicitly asked. |
| Evidence | Do not claim ready, fixed, synced, or pushed without fresh verification evidence. |
| Subagent distrust | After delegating to a subagent, do not trust its summary. Read the diff, verify against acceptance criteria, and check the outputs yourself before accepting. See `.pi/skills/context/subagent-distrust/SKILL.md`. |
| UI/UX evidence | Rendered evidence (browser state, screenshot, mockup, or manual visual observation) is optional, not required, for user-facing visual work. When you make a visual-quality claim, base it on whatever evidence you actually have and do not claim visual success from DOM/class names alone. If confidence is limited by lack of visual evidence, just say so. |
| Destructive actions | Ask before irreversible or destructive operations. |

## Pikit References

| Reference | Purpose |
| --- | --- |
| `.pi/skills/context/using-skills/SKILL.md` | Command-to-phase routing through existing pi-subagents agents. |
| `.pi/skills/workflow/pikit-workflow/SKILL.md` | Pikit command contracts and Pi workflow rules. |
