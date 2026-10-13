<!-- CCBR-SUPERPOWERS-START -->
<!-- superpowers version: v6.4.2 -->
<!-- vscode_ghcopilot_superpowers commit: 90fbdfc -->
<!-- generated_at: 2026-10-13T00:00:00Z -->
## CCBR Superpowers integration

Approved Superpowers skills may be available as personal Agent Skills under `~/.claude/skills/`. The local installation is managed separately. This repository policy determines whether a skill should be invoked; discovery alone never requires its use. Once deliberately selected, follow the chosen skill's workflow.

If a requested Superpowers skill is unavailable, tell the user to run the CCBR Superpowers installer from anywhere inside this repository:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/CCBR/vscode-ghcopilot-superpowers/main/install_superpowers.sh \
  | bash -s --
```

Do not install Superpowers automatically. Do not create or use repository-local links to a machine-specific Superpowers installation.

## Superpowers usage policy

Superpowers is an optional workflow framework, not the default way to perform tasks.

Optimize for **correctness, speed, and token efficiency**. For routine work, prefer direct repository inspection, implementation, and targeted validation using the normal available tools.

Do NOT invoke a Superpowers skill merely because it appears relevant. For small, routine, low-risk, or well-understood tasks, work directly without Superpowers. Examples include documentation, minor configuration, obvious bug fixes, mechanical refactors, routine dependency updates, simple tests, code explanation, and repository exploration.

Consider Superpowers only when the task is sufficiently **large, non-routine, ambiguous, or risky** that a structured workflow is likely to materially improve the result. Good candidates include large features, significant architectural changes, complex bugs with unclear causes, risky refactors, critical infrastructure or interfaces, and explicit user requests. Use the smallest subset of Superpowers necessary; do not automatically chain every workflow.

## TDD policy

**Do NOT use the Superpowers TDD workflow by default.** Reserve it for substantial behavioral changes, complex business or scientific logic, critical shared code, meaningful regression risk, or an explicit user request. Documentation, formatting, simple configuration, obvious fixes, minor refactors, and routine maintenance need only the minimum targeted validation appropriate to the change.

Before invoking any Superpowers workflow, ask whether the task is large, non-routine, ambiguous, or potentially code-breaking; whether the workflow will materially improve correctness or reduce risk; and whether that benefit is proportional to its cost. If not, work directly.
<!-- CCBR-SUPERPOWERS-END -->
