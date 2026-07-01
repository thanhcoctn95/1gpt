# Pikit Global Agent Rules

These rules apply to ordinary chat, slash workflows, and subagents in projects that use the Pikit pack.

## Start-of-Work Routing

Before substantive work, classify the request.

| Field | Required content |
| --- | --- |
| Intent | What the user wants done. |
| Input type | Task ID, path, flag, freeform request, git action, UI/design request, research request, or unclear. |
| Route | Direct action or Pikit workflow. |
| Required skills | Skills declared by the workflow or clearly relevant to the request. |
| Extra skills | Additional skills justified by docs, git, security, UI, research, or Pikit pack maintenance. |
| Ambiguity | `none` or exact clarification needed. |
| First action | Read, inspect, ask, plan, execute, verify, or delegate. |

## Report Formatting

For final reports and structured status updates:

| Rule | Requirement |
| --- | --- |
| Structured output | Use Markdown pipe tables. |
| Unicode box tables | Do not use box-drawing tables such as `┌`, `┬`, `│`, `└`, or `─`. |
| Code fences | Do not use fenced code blocks in final reports unless the user explicitly asks for raw file/script/log content. |
| Commands and paths | Put short commands, paths, hashes, and examples inline inside Markdown table cells. |
| Formatter compatibility | Keep Markdown tables outside code fences so `markdown-table` can normalize them. |

## Safety and Verification

| Rule | Requirement |
| --- | --- |
| Scope | Keep changes limited to the user request. |
| User changes | Never revert unrelated user work without explicit approval. |
| Git | Do not commit, push, tag, reset, clean, or force-push unless explicitly asked. |
| Evidence | Do not claim ready, fixed, synced, or pushed without fresh verification evidence. |
| Destructive actions | Ask before irreversible or destructive operations. |

## Pikit References

| Reference | Purpose |
| --- | --- |
| `.pi/skills/using-skills/SKILL.md` | Intent, route, and skill-selection protocol. |
| `.pi/skills/pikit-workflow/SKILL.md` | Pikit resource and workflow rules. |
| `.pi/docs/intent-and-skill-routing.md` | Routing model. |
| `.pi/docs/apply-pikit-to-project.md` | Applying/updating Pikit in another project. |
