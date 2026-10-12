# CCBR Superpowers installer

This repository provides a portable installer for [obra/superpowers](https://github.com/obra/superpowers). It installs personal Agent Skills for VS Code and other compatible agents on BioWulf, FRCE, and CCBR government-furnished equipment (GFE).

Each environment gets its own checkout under that environment's home directory:

```text
~/.claude/
├── repos/
│   └── superpowers/                 # Upstream Git checkout at an exact tag
└── skills/
    ├── brainstorming -> ../repos/superpowers/skills/brainstorming
    └── ...
```

Because both directories are relative to `$HOME`, the same link layout works locally and through VS Code Remote SSH. BioWulf, FRCE, and the GFE do not share one checkout; run the installer once in each environment. The personal skills are then available to every repository opened in that environment.

The installer must be run from inside a Git working tree. It may be run from the repository root or any subdirectory. By default, it also adds or refreshes the CCBR Superpowers policy in the repository root's `AGENTS.md`.

## Install

Prerequisites are Bash, Git, `tar`, HTTPS access to GitHub, write access to `$HOME/.claude`, and a target Git working tree. The default Superpowers version is `v6.4.2`.

From anywhere inside the target repository, run the installer directly from GitHub:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/CCBR/vscode-ghcopilot-superpowers/main/install_superpowers.sh \
  | bash -s --
```

### Alternative installation methods

To inspect the script before running it, download it first:

```bash
curl -fsSLo /tmp/install-superpowers.sh \
  https://raw.githubusercontent.com/CCBR/vscode-ghcopilot-superpowers/main/install_superpowers.sh
bash /tmp/install-superpowers.sh
```

From a checkout of this repository:

```bash
bash install_superpowers.sh
```

Arguments for direct GitHub execution go after `bash -s --`, as shown in the examples below.

The installer recognizes these hostname patterns for reporting:

- `biowulf.nih.gov` and `cnNNNN`: BioWulf
- `*.ncifcrf.gov`: FRCE
- `NCI-*`: GFE

An unrecognized hostname is not fatal. Installation still uses the current `$HOME`, which is the source of truth for the environment-specific location.

## Update or roll back

Use the same command with an exact upstream tag:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/CCBR/vscode-ghcopilot-superpowers/main/install_superpowers.sh \
  | bash -s -- --version v6.4.3
```

This fetches upstream tags, validates the requested release, switches the personal checkout to that tag, and reconciles the personal skill links. It dynamically adds skills introduced by the release and removes obsolete links only when they were previously managed by this installer. Existing valid links continue to point through the stable checkout path.

The operation also supports intentional rollback:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/CCBR/vscode-ghcopilot-superpowers/main/install_superpowers.sh \
  | bash -s -- --version v6.4.2
```

If the requested tag does not exist, the active checkout remains unchanged. The installer refuses to switch versions when the checkout has local changes or its `origin` is not the official `obra/superpowers` repository.

If the existing checkout is invalid, has the wrong origin, has local changes, or cannot be verified after a version switch, the installer stops and asks you to back up anything needed, delete `~/.claude/repos/superpowers`, and try again. The installer never deletes that directory for you. Deleting it discards any local changes inside it.

Check the installed version and managed links with:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/CCBR/vscode-ghcopilot-superpowers/main/install_superpowers.sh \
  | bash -s -- --status
```

## Existing skills and conflicts

For every valid skill in the selected release, the installer:

- Leaves a correct managed link unchanged.
- Replaces a wrong or broken symlink.
- Creates a missing link.
- Leaves unrelated personal skills alone.
- Asks before replacing an ordinary file or directory with the same skill name.

Accepted conflicting files and directories are moved into a timestamped backup under `~/.claude/skills/`; they are not deleted. For noninteractive use, approve that behavior explicitly:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/CCBR/vscode-ghcopilot-superpowers/main/install_superpowers.sh \
  | bash -s -- --replace-conflicts
```

The installer does not modify `~/.claude/skills/synced/`.

## Repository policy

The default installation adds or refreshes the CCBR usage policy in the current Git repository's root-level `AGENTS.md`. Running the command from a subdirectory still updates the repository root:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/CCBR/vscode-ghcopilot-superpowers/main/install_superpowers.sh \
  | bash -s --
```

Personal skill discovery does not itself require `AGENTS.md`. To install or update the personal skills without changing the current repository's policy, use the explicit opt-out:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/CCBR/vscode-ghcopilot-superpowers/main/install_superpowers.sh \
  | bash -s -- --no-agents-policy
```

The managed section says that personal Superpowers skills may be available under `~/.claude/skills/`, but their presence does not require their use. Agents should use the smallest appropriate workflow only for sufficiently large, ambiguous, non-routine, or risky tasks. The Superpowers test-driven-development workflow is not the default for small or routine work.

The installer creates or refreshes only the content between these markers:

```markdown
<!-- CCBR-SUPERPOWERS-START -->
...
<!-- CCBR-SUPERPOWERS-END -->
```

All repository-owned content outside the markers is preserved. The installed Superpowers version is intentionally absent from `AGENTS.md`, so a personal version update does not require changes across repositories.

## Options

```text
-v, --version TAG       Install or switch to an exact upstream tag
    --status            Report the installed version and managed links
    --replace-conflicts Back up conflicting files/directories without prompting
  --no-agents-policy Do not update AGENTS.md with the CCBR policy
-h, --help              Show help
```

Environment variables intended for tests or approved mirrors:

- `CCBR_SUPERPOWERS_REPO_URL`: override the upstream repository URL.
- `CCBR_SUPERPOWERS_INSTALL_ROOT`: override `~/.claude`.
- `CCBR_SUPERPOWERS_HOSTNAME`: override hostname detection.

## Development

Run the isolated test suite with:

```bash
bash tests/install_superpowers.sh
```

The tests create temporary homes and local tagged Git repositories. They do not modify the user's personal installation or require network access.

Credit for the skills and workflows belongs to [obra/superpowers](https://github.com/obra/superpowers). This repository provides installation and CCBR usage-policy management only.
