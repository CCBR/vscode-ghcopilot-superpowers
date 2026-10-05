# CCBR Superpowers for VS Code on BioWulf

This repository is a small bootstrap utility for development on **NIH BioWulf through VS Code Remote SSH with GitHub Copilot**. It exposes skills from [upstream Superpowers](https://github.com/obra/superpowers) to a Git repository using VS Code's native Agent Skills location. It does not fork, install, download, update, or copy Superpowers.

CCBR maintains the shared upstream checkout at `/data/CCBR_Pipeliner/db/PipeDB/AI/superpowers` (currently **v6.4.2**) and separately deploys this installer at `/data/CCBR_Pipeliner/db/PipeDB/AI/vscode-ghcopilot-superpowers`. Administrators maintain both checkouts; normal users only need read/execute permission. Running the deployed installer needs neither internet access nor GitHub authentication.

## Install in a repository

Prerequisites: Bash, Git, access to both shared checkouts, write permission in the target Git working tree, and VS Code Remote SSH with GitHub Copilot and Agent Skills enabled (`chat.useAgentSkills`). Run from the repository root **or any subdirectory**:

```bash
cd /path/to/target/repository
/data/CCBR_Pipeliner/db/PipeDB/AI/vscode-ghcopilot-superpowers/install_superpowers.sh
```

`bash /data/CCBR_Pipeliner/db/PipeDB/AI/vscode-ghcopilot-superpowers/install_superpowers.sh` also works. No personal checkout, home-directory changes, or copy of this script is needed.

The installer finds the Git working-tree root and:

- Creates `.github/skills/` if necessary and adds **one directory symlink per valid shared skill**, for example `.github/skills/brainstorming -> /data/CCBR_Pipeliner/db/PipeDB/AI/superpowers/skills/brainstorming`. A skill needs readable `SKILL.md` with `name` matching its directory and a `description` in YAML frontmatter. Skills lacking these are skipped and reported. The shared files remain authoritative; no skill contents are copied.
- Creates `AGENTS.md`, or inserts/refreshes **only** the section between `<!-- CCBR-SUPERPOWERS-START -->` and `<!-- CCBR-SUPERPOWERS-END -->`. All other project instructions remain in place. Existing malformed or duplicate markers cause a safe failure requiring manual resolution.
- Leaves existing unrelated `.github/skills` entries alone. A name already occupied by anything other than the expected working symlink is a conflict; it is reported without modifying the repository. This includes broken or redirected symlinks.

It does **not** touch `.github/copilot-instructions.md`, create `.github/prompts/`, or modify either shared checkout. Repository owners may separately configure Copilot instructions to refer to `AGENTS.md` if their environment does not load it automatically. Rerun the installer after CCBR adds skills; repeated runs leave correct links and policy unchanged.

## Usage policy

The managed `AGENTS.md` section contains the full CCBR policy: **Superpowers is optional, not the default**. For small or routine work (docs, configuration, obvious fixes, mechanical refactors, simple tests), work directly with targeted validation. Consider only the smallest appropriate subset of Superpowers for large, ambiguous, non-routine, or risky changes where structured workflow materially reduces risk. **Do not invoke TDD by default**: reserve it for substantial behavior, critical shared code, significant regression risk, or an explicit user request. The repository policy determines *whether* to use a skill; only after a skill is deliberately selected do its instructions govern the workflow. Merely discovering a skill is not a command to use it.

## Verify discovery on BioWulf

[VS Code's Agent Skills documentation](https://code.visualstudio.com/docs/copilot/customization/agent-skills) documents `.github/skills/` as a workspace skill location, `SKILL.md` frontmatter, and the Configure Skills menu. [Upstream v6.4.2](https://github.com/obra/superpowers/tree/v6.4.2/skills) contains skill directories with `SKILL.md` files. **It does not conclusively document that VS Code Remote SSH follows directory symlinks while discovering skills.** The installer uses symlinks as proposed; discovery on your BioWulf VS Code installation must be confirmed rather than assumed:

1. Run the installer in a disposable test Git repository on BioWulf. Confirm `ls -l .github/skills/brainstorming` shows a link to the shared skill and `cat .github/skills/brainstorming/SKILL.md` shows its upstream frontmatter.
2. Open the **repository folder** via VS Code Remote SSH, then run **Developer: Reload Window** (or reopen the folder) after installation. Ensure GitHub Copilot is enabled and `chat.useAgentSkills` is on.
3. In Copilot Chat, choose **Configure Chat → Skills** or type `/skills` to open Configure Skills. Check whether `brainstorming` (and other shared skill names) appears. In a disposable chat, explicitly ask Copilot to use the `brainstorming` skill and verify that it references the upstream skill's contents, rather than merely claiming it can see the link. This is a discovery test, not a recommendation to use brainstorming for routine tasks.
4. If absent, compare with a disposable ordinary directory skill under `.github/skills/` in the same test repository (with matching frontmatter). If that appears but the symlink does not, report the VS Code/Copilot version and Remote SSH setup to CCBR. Do not silently replace shared symlinks with copied skill files.

VS Code may need a window reload to refresh skills after installation. Skill availability does not guarantee automatic selection for every prompt.

## Troubleshooting and removal

- **Missing shared path / permission denied:** ask CCBR administrators to verify read and traversal permissions on the shared Superpowers checkout, its `skills` directory, and this installer. The installer does not fix shared deployments.
- **Broken or unexpected link / name conflict:** inspect `ls -l .github/skills/<name>`; decide who owns the entry before manually changing it. The installer never deletes or replaces existing skills.
- **Skill not listed in VS Code:** check `SKILL.md` frontmatter and name, `chat.useAgentSkills`, the opened workspace root, Remote SSH permissions, reload, and the validation procedure above. Directory-symlink discovery is an open compatibility question until verified on BioWulf.
- **Invalid AGENTS.md markers:** resolve unmatched, reversed, or repeated CCBR marker lines by hand while retaining other instructions, then rerun.

To remove the integration, inspect `.github/skills/` and remove **only** symlinks that point to `/data/CCBR_Pipeliner/db/PipeDB/AI/superpowers/skills/<same-name>`; leave project-owned skills and directories alone. Remove only the CCBR-marked section from `AGENTS.md`, preserving everything else. Delete `AGENTS.md` or `.github/skills/` only if you have confirmed they contain no other project content. Neither shared checkout needs changing.

## Development

Run the isolated test suite with `bash tests/install_superpowers.sh`. It uses temporary Git repositories and fixture skills, not the BioWulf paths. For tests/development only, `CCBR_SUPERPOWERS_ROOT` overrides the production source; normal users need no configuration.

Credit for the skill definitions and workflows belongs to [obra/superpowers](https://github.com/obra/superpowers). This repository only integrates CCBR's centrally managed deployment with VS Code/GitHub Copilot.
