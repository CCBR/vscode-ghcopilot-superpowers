#!/usr/bin/env bash
set -euo pipefail

main() {
default_version=v6.4.2
official_repo=https://github.com/obra/superpowers.git
version=$default_version
repo_url=${CCBR_SUPERPOWERS_REPO_URL:-$official_repo}
install_root=${CCBR_SUPERPOWERS_INSTALL_ROOT:-"$HOME/.claude"}
checkout=$install_root/repos/superpowers
skills_dir=$install_root/skills
manifest=$install_root/.ccbr-superpowers-managed
replace_conflicts=0
show_status=0
list_versions=0
show_verify=0
dry_run=0
configure_repo=1
version_requested=0
start='<!-- CCBR-SUPERPOWERS-START -->'
end='<!-- CCBR-SUPERPOWERS-END -->'
temporary_paths=()

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
fail_checkout() {
  printf 'Error: %s\n' "$1" >&2
  printf 'Back up anything you need, delete %s, and try again.\n' "$checkout" >&2
  exit 1
}
cleanup() {
  local path
  for path in "${temporary_paths[@]}"; do rm -rf "$path"; done
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: install_superpowers.sh [OPTIONS]

Install, update, or repair personal Superpowers skills.

Options:
  -v, --version TAG       Install an exact upstream tag (default: v6.4.2)
      --status            Report the installed version and managed skills
      --list-versions     List available upstream versions without making changes
      --verify            Verify installation and policy health without making changes
      --dry-run           Preview installer changes without modifying files or Git state
      --replace-conflicts Back up conflicting files/directories without prompting
      --no-agents-policy  Do not update AGENTS.md with the CCBR policy
  -h, --help              Show this help

Environment variables intended for testing or mirrors:
  CCBR_SUPERPOWERS_REPO_URL      Override the official upstream URL
  CCBR_SUPERPOWERS_INSTALL_ROOT  Override ~/.claude
EOF
}

while (($#)); do
  case "$1" in
    -v|--version)
      (($# >= 2)) || fail "$1 requires a tag."
      version=$2
      version_requested=1
      shift 2
      ;;
    --status)
      show_status=1
      shift
      ;;
    --list-versions)
      list_versions=1
      shift
      ;;
    --verify)
      show_verify=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --replace-conflicts)
      replace_conflicts=1
      shift
      ;;
    --no-agents-policy)
      configure_repo=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *) fail "Unknown option: $1 (use --help)." ;;
  esac
done
(($# == 0)) || fail "Unexpected argument: $1"
((!show_status || !list_versions)) || fail '--status and --list-versions cannot be used together.'
if ((show_verify && (show_status || list_versions || version_requested || replace_conflicts))); then
  fail '--verify cannot be combined with --status, --list-versions, --version, or --replace-conflicts.'
fi
if ((dry_run && (show_status || list_versions || show_verify))); then
  fail '--dry-run cannot be combined with --status, --list-versions, or --verify.'
fi

command -v git >/dev/null 2>&1 || fail 'Git is required.'
repo=$(git rev-parse --show-toplevel 2>/dev/null) || fail 'Run this installer inside a Git working tree.'
repo=$(cd "$repo" && pwd -P)

installed_version() {
  [[ -d $checkout/.git ]] || return 1
  git -C "$checkout" describe --tags --exact-match 2>/dev/null
}

manifest_skills() {
  [[ -f $manifest ]] || return 0
  sed -n 's/^skill=//p' "$manifest"
}

status() {
  local current count=0 name target value state
  if ! current=$(installed_version); then
    printf 'Superpowers is not installed at %s.\n' "$checkout"
    return 1
  fi
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    target=$skills_dir/$name
    if [[ -L $target ]]; then
      value=$(readlink "$target")
      if [[ $value == "../repos/superpowers/skills/$name" || $value == "$checkout/skills/$name" ]] &&
        [[ -f $target/SKILL.md ]]; then
        state=ok
        ((count+=1))
      else
        state=unexpected
      fi
    else
      state=missing
    fi
    printf '  %s: %s\n' "$name" "$state"
  done < <(manifest_skills)
  printf 'Superpowers %s is installed at %s (%d managed skills available).\n' "$current" "$checkout" "$count"
}

list_available_versions() {
  local current refs versions listed=0 item
  if ! refs=$(git ls-remote --tags "$repo_url" 'refs/tags/v*' 2>/dev/null); then
    fail "Could not list Superpowers versions from $repo_url. Check network access and the repository URL."
  fi
  versions=$(printf '%s\n' "$refs" | awk '
    $2 ~ /^refs\/tags\/v[0-9]+\.[0-9]+\.[0-9]+(\^\{\})?$/ {
      ref=$2
      sub(/^refs\/tags\/v/, "", ref)
      sub(/\^\{\}$/, "", ref)
      if (!seen[ref]++) {
        split(ref, part, ".")
        printf "%s\t%s\t%s\tv%s\n", part[1], part[2], part[3], ref
      }
    }
  ' | sort -t "$(printf '\t')" -k1,1nr -k2,2nr -k3,3nr | awk -F '\t' '{ print $4 }')
  [[ -n $versions ]] || fail "No semantic Superpowers version tags were found in $repo_url."
  current=$(installed_version || true)
  printf 'Available Superpowers versions:\n'
  while IFS= read -r item; do
    [[ -n $item ]] || continue
    if [[ $item == "$current" ]]; then
      printf '  %s (installed)\n' "$item"
    else
      printf '  %s\n' "$item"
    fi
    ((listed+=1))
  done <<< "$versions"
  printf '%d version(s) available. Install one with --version TAG.\n' "$listed"
}

if ((show_status)); then
  status
  exit $?
fi

if ((list_versions)); then
  list_available_versions
  exit 0
fi

command -v tar >/dev/null 2>&1 || fail 'tar is required.'
git check-ref-format "refs/tags/$version" >/dev/null 2>&1 || fail "Invalid version tag: $version"

printf 'Using personal Superpowers directory: %s\n' "$install_root"

normalize_url() {
  local value=$1
  value=${value%/}
  value=${value%.git}
  printf '%s' "$value"
}

expected_remote() {
  local actual normalized
  actual=$1
  normalized=$(normalize_url "$actual")
  if [[ -n ${CCBR_SUPERPOWERS_REPO_URL:-} ]]; then
    [[ $normalized == "$(normalize_url "$repo_url")" ]]
    return
  fi
  case "$normalized" in
    https://github.com/obra/superpowers|git@github.com:obra/superpowers|ssh://git@github.com/obra/superpowers) return 0 ;;
    *) return 1 ;;
  esac
}

skill_frontmatter_status() {
  local expected=$1 file=$2
  awk -v name="$expected" '
    { line=$0; sub(/\r$/, "", line) }
    NR == 1 { if (line != "---") malformed=1; next }
    line == "---" { closed=1; exit }
    /^name: / { found_name = (substr(line, 7) == name) }
    /^description: / { found_description = (length(line) > 13) }
    END {
      if (!found_name) exit 2
      if (malformed || !closed || !found_description) exit 3
    }
  ' "$file"
}

write_policy() {
  cat <<'POLICY'
<!-- CCBR-SUPERPOWERS-START -->
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
POLICY
}

preview_installation() {
  local preview_checkout current='' origin dirty source_skills dir file name target value policy_state manifest_expected manifest_actual
  local expected_policy existing_policy writable_parent
  local -a preview_skills=() planned_actions=() correct_items=() previous_skills=()

  printf 'DRY RUN: no repository or personal installation changes will be made.\n'

  writable_parent=$install_root
  while [[ ! -e $writable_parent ]]; do writable_parent=${writable_parent%/*}; done
  [[ -d $writable_parent && -w $writable_parent ]] ||
    fail "Personal installation parent is not writable: $writable_parent"
  if ((configure_repo)); then
    [[ -w $repo ]] || fail "Repository is not writable for an AGENTS.md update: $repo"
  fi

  if [[ -e $checkout && ! -d $checkout/.git ]]; then
    fail_checkout "Existing path is not a Superpowers Git checkout: $checkout"
  elif [[ -d $checkout/.git ]]; then
    origin=$(git -C "$checkout" config --get remote.origin.url || true)
    expected_remote "$origin" || fail_checkout "Unexpected Superpowers origin: ${origin:-none}"
    dirty=$(GIT_OPTIONAL_LOCKS=0 git -C "$checkout" status --porcelain --untracked-files=all 2>/dev/null || printf 'unreadable')
    [[ -z $dirty ]] || fail_checkout "Superpowers checkout has local changes: $checkout"
    current=$(installed_version || true)
  else
    planned_actions+=("Clone Superpowers into $checkout.")
  fi
  planned_actions+=("Fetch upstream Superpowers tags.")

  printf 'Inspecting requested version %s from %s...\n' "$version" "$repo_url"
  preview_checkout=$(mktemp -d "${TMPDIR:-/tmp}/ccbr-superpowers-preview.XXXXXX")
  temporary_paths+=("$preview_checkout")
  git clone --quiet --no-checkout "$repo_url" "$preview_checkout" ||
    fail "Could not inspect Superpowers from $repo_url. Check network access and the repository URL."
  git -C "$preview_checkout" rev-parse --verify --quiet "refs/tags/$version^{commit}" >/dev/null ||
    fail "Superpowers tag $version was not found; no changes were made."
  git -C "$preview_checkout" checkout --detach --quiet "refs/tags/$version"
  source_skills=$preview_checkout/skills

  shopt -s nullglob
  for dir in "$source_skills"/*; do
    [[ -d $dir && ! -L $dir ]] || continue
    name=${dir##*/}
    file=$dir/SKILL.md
    if [[ -f $file && -r $file ]] && skill_frontmatter_status "$name" "$file"; then
      preview_skills+=("$name")
    else
      warn "Skipping invalid skill in $version: $name"
    fi
  done
  ((${#preview_skills[@]})) || fail "No valid skills were found in Superpowers $version."

  if [[ $current == "$version" ]]; then
    correct_items+=("Checkout is already at $version.")
  else
    planned_actions+=("Check out $version.")
  fi

  while IFS= read -r name; do
    [[ -n $name ]] && previous_skills+=("$name")
  done < <(manifest_skills)

  for name in "${preview_skills[@]}"; do
    target=$skills_dir/$name
    if [[ -L $target ]]; then
      value=$(readlink "$target")
      if [[ $value == "../repos/superpowers/skills/$name" || $value == "$checkout/skills/$name" ]] &&
        [[ -f $target/SKILL.md ]]; then
        correct_items+=("Managed skill link is already correct: $name.")
      else
        planned_actions+=("Repair managed skill link: $name.")
      fi
    elif [[ -e $target ]]; then
      if ((replace_conflicts)); then
        planned_actions+=("Back up conflicting skill entry: $target.")
        planned_actions+=("Create managed skill link: $name.")
      else
        fail "Conflict at $target requires --replace-conflicts; no changes were made."
      fi
    else
      planned_actions+=("Create managed skill link: $name.")
    fi
  done

  for name in "${previous_skills[@]}"; do
    if ! list_contains_preview "$name" "${preview_skills[@]}"; then
      target=$skills_dir/$name
      if [[ -L $target ]]; then
        value=$(readlink "$target")
        if [[ $value == "../repos/superpowers/skills/$name" || $value == "$checkout/skills/$name" ]]; then
          planned_actions+=("Remove obsolete managed skill link: $name.")
        fi
      fi
    fi
  done

  manifest_expected=$(printf 'version=%s\n' "$version"; printf 'skill=%s\n' "${preview_skills[@]}")
  manifest_actual=$(cat "$manifest" 2>/dev/null || true)
  if [[ $manifest_actual == "$manifest_expected" ]]; then
    correct_items+=("Managed-skills manifest is already correct for $version.")
  else
    planned_actions+=("Write managed-skills manifest for $version (${#preview_skills[@]} skills).")
  fi

  if ((configure_repo)); then
    agents=$repo/AGENTS.md
    if [[ -e $agents || -L $agents ]]; then
      [[ -f $agents && ! -L $agents && -r $agents ]] ||
        fail "AGENTS.md must be a readable regular file (not a symlink): $agents"
      if awk -v s="$start" -v e="$end" '
        { line=$0; sub(/\r$/, "", line) }
        line == s { a++; if (a != 1 || b) exit 1 }
        line == e { b++; if (b != 1 || a != 1) exit 1 }
        END { if (a != b || a > 1 || b > 1) exit 1 }
      ' "$agents"; then
        if grep -Fq "$start" "$agents"; then
          expected_policy=$(write_policy)
          existing_policy=$(awk -v s="$start" -v e="$end" '
            { line=$0; sub(/\r$/, "", line) }
            line == s { inside=1 }
            inside { print line }
            line == e { exit }
          ' "$agents")
          if [[ -n $expected_policy && $existing_policy == "$expected_policy" ]]; then
            policy_state=current
          else
            policy_state=update
          fi
        else
          policy_state=update
        fi
      else
        fail 'AGENTS.md has incomplete, repeated, or out-of-order CCBR markers; resolve manually.'
      fi
    else
      policy_state=update
    fi
    if [[ $policy_state == current ]]; then
      correct_items+=("Repository policy is already current: $agents.")
    else
      planned_actions+=("Update repository policy: $agents.")
    fi
  else
    correct_items+=('Repository policy update is disabled by --no-agents-policy.')
  fi

  printf 'Planned changes:\n'
  if ((${#planned_actions[@]})); then printf '  %s\n' "${planned_actions[@]}"; else printf '  None.\n'; fi
  printf 'Already correct:\n'
  if ((${#correct_items[@]})); then printf '  %s\n' "${correct_items[@]}"; else printf '  None.\n'; fi
}

list_contains_preview() {
  local wanted=$1 candidate
  shift
  for candidate in "$@"; do [[ $candidate == "$wanted" ]] && return 0; done
  return 1
}

if ((dry_run)); then
  preview_installation
  exit 0
fi

verify_installation() {
  local healthy=0 warnings=0 errors=0 current commit origin dirty manifest_version='' line name target value
  local marker_count active_count=0 manifest_count=0 frontmatter_status
  local -a active_skills=() managed_skills=()

  verify_ok() { printf 'OK: %s\n' "$*"; ((healthy+=1)); }
  verify_warning() { printf 'WARNING: %s\n' "$*"; ((warnings+=1)); }
  verify_error() { printf 'ERROR: %s\n' "$*"; ((errors+=1)); }
  repair() { printf '  Repair: %s\n' "$*"; }
  list_contains() {
    local wanted=$1 candidate
    shift
    for candidate in "$@"; do [[ $candidate == "$wanted" ]] && return 0; done
    return 1
  }
  valid_skill_name() { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }
  if [[ ! -d $checkout/.git ]]; then
    verify_error "Superpowers checkout is missing or is not a Git repository: $checkout."
    repair 'rerun the installer to create a verified checkout.'
  else
    if current=$(installed_version); then
      verify_ok "Installed version: $current"
    else
      verify_error 'Checkout is not at an exact version tag.'
      repair 'rerun the installer with --version TAG.'
    fi
    if commit=$(git -C "$checkout" rev-parse HEAD 2>/dev/null); then
      verify_ok "Checkout commit: $commit"
    else
      verify_error 'Checkout commit could not be read.'
      repair "back up changes, delete $checkout, and rerun the installer."
    fi
    origin=$(git -C "$checkout" config --get remote.origin.url || true)
    if expected_remote "$origin"; then
      verify_ok "Checkout origin: $origin"
    else
      verify_error "Checkout origin is unexpected: ${origin:-none}."
      repair "back up changes, delete $checkout, and rerun the installer."
    fi
    dirty=$(GIT_OPTIONAL_LOCKS=0 git -C "$checkout" status --porcelain --untracked-files=all 2>/dev/null || printf 'unreadable')
    if [[ -z $dirty ]]; then
      verify_ok 'Checkout has no local changes.'
    else
      verify_error 'Checkout has local changes.'
      repair "back up changes, delete $checkout, and rerun the installer."
    fi

    shopt -s nullglob
    for target in "$checkout/skills"/*; do
      [[ -d $target && ! -L $target ]] || continue
      name=${target##*/}
      active_skills+=("$name")
      ((active_count+=1))
      if [[ ! -f $target/SKILL.md || ! -r $target/SKILL.md ]]; then
        verify_error "Skill is missing a readable SKILL.md: $name."
        repair 'back up changes, delete the checkout, and rerun the installer.'
      else
        if skill_frontmatter_status "$name" "$target/SKILL.md"; then
          :
        else
          frontmatter_status=$?
          if ((frontmatter_status == 2)); then
            verify_error "Skill frontmatter name does not match its directory: $name."
          else
            verify_error "Skill frontmatter is invalid: $name."
          fi
          repair 'back up changes, delete the checkout, and rerun the installer.'
        fi
      fi
    done
    if ((active_count == 0)); then
      verify_error 'Checkout contains no skill directories.'
      repair "back up changes, delete $checkout, and rerun the installer."
    fi
  fi

  if [[ ! -f $manifest || -L $manifest || ! -r $manifest ]]; then
    verify_error "Managed-skills manifest is missing or unreadable: $manifest."
    repair "rerun the installer${current:+ for $current}."
  else
    marker_count=0
    while IFS= read -r line || [[ -n $line ]]; do
      case "$line" in
        version=*)
          ((marker_count+=1))
          manifest_version=${line#version=}
          [[ $manifest_version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || marker_count=99
          ;;
        skill=*)
          name=${line#skill=}
          if ! valid_skill_name "$name" || list_contains "$name" "${managed_skills[@]}"; then
            marker_count=99
          else
            managed_skills+=("$name")
            ((manifest_count+=1))
          fi
          ;;
        *) marker_count=99 ;;
      esac
    done < "$manifest"
    if ((marker_count != 1)); then
      verify_error "Managed-skills manifest is malformed: $manifest."
      repair "rerun the installer${current:+ for $current}."
    elif [[ -n $current && $manifest_version != "$current" ]]; then
      verify_error "Manifest version $manifest_version does not match installed version $current."
      repair "rerun the installer for $current."
    fi
  fi

  if [[ -d $checkout/.git ]]; then
    for name in "${active_skills[@]}"; do
      if ! list_contains "$name" "${managed_skills[@]}"; then
        verify_error "Manifest is missing active skill: $name."
        repair "rerun the installer${current:+ for $current}."
      fi
      target=$skills_dir/$name
      if [[ ! -L $target ]]; then
        if [[ -e $target ]]; then
          verify_error "Managed skill path is not a symbolic link: $name."
        else
          verify_error "Managed skill link is missing: $name."
        fi
        repair "rerun the installer${current:+ for $current}."
      else
        value=$(readlink "$target")
        if [[ $value != "../repos/superpowers/skills/$name" && $value != "$checkout/skills/$name" ]]; then
          verify_error "Managed skill link has the wrong target: $name."
          repair "rerun the installer${current:+ for $current}."
        elif [[ ! -d $target || ! -f $target/SKILL.md ]]; then
          verify_error "Managed skill link is broken or its target is incomplete: $name."
          repair "rerun the installer${current:+ for $current}."
        elif skill_frontmatter_status "$name" "$target/SKILL.md"; then
          verify_ok "Skill $name is healthy."
        else
          verify_error "Managed skill has invalid frontmatter: $name."
          repair "rerun the installer${current:+ for $current}."
        fi
      fi
    done
    for name in "${managed_skills[@]}"; do
      if ! list_contains "$name" "${active_skills[@]}"; then
        verify_error "Manifest contains obsolete skill: $name."
        repair "rerun the installer${current:+ for $current}."
        target=$skills_dir/$name
        if [[ ! -L $target ]]; then
          if [[ -e $target ]]; then
            verify_error "Obsolete managed skill path is not a symbolic link: $name."
          else
            verify_error "Obsolete managed skill link is missing: $name."
          fi
          repair "rerun the installer${current:+ for $current}."
        else
          value=$(readlink "$target")
          if [[ $value != "../repos/superpowers/skills/$name" && $value != "$checkout/skills/$name" ]]; then
            verify_error "Obsolete managed skill link has the wrong target: $name."
            repair "rerun the installer${current:+ for $current}."
          elif [[ ! -d $target || ! -f $target/SKILL.md ]]; then
            verify_error "Obsolete managed skill link is broken: $name."
            repair "rerun the installer${current:+ for $current}."
          fi
        fi
      fi
    done
    shopt -s nullglob
    for target in "$skills_dir"/*; do
      [[ -L $target ]] || continue
      name=${target##*/}
      value=$(readlink "$target")
      case "$value" in
        ../repos/superpowers/skills/*|"$checkout"/skills/*)
          if ! list_contains "$name" "${managed_skills[@]}"; then
            verify_error "Unexpected managed-looking skill link: $name."
            repair 'remove the obsolete link or rerun the installer.'
          fi
          ;;
      esac
    done
    if ((errors == 0 && manifest_count == active_count)); then
      verify_ok "Manifest matches active checkout ($active_count skills)."
    fi
  fi

  agents=$repo/AGENTS.md
  if ((!configure_repo)); then
    verify_warning 'Repository policy verification was skipped by --no-agents-policy.'
  elif [[ ! -f $agents || -L $agents || ! -r $agents ]]; then
    verify_error "Repository policy is missing or is not a readable regular file: $agents."
    repair 'rerun the installer to create the repository policy.'
  elif awk -v s="$start" -v e="$end" '
    { line=$0; sub(/\r$/, "", line) }
    line == s { a++; if (a != 1 || b) exit 1 }
    line == e { b++; if (b != 1 || a != 1) exit 1 }
    END { if (a != 1 || b != 1) exit 1 }
  ' "$agents"; then
    verify_ok "Repository policy markers are valid: $agents"
  else
    verify_error "Repository policy markers are incomplete, repeated, or out of order: $agents."
    repair 'resolve the CCBR marker section manually, then rerun the installer.'
  fi

  printf 'Verification summary: %d healthy, %d warnings, %d errors.\n' "$healthy" "$warnings" "$errors"
  ((errors == 0))
}

if ((show_verify)); then
  verify_installation
  exit $?
fi

preflight_repository() {
  local probe
  agents=$repo/AGENTS.md
  has_policy=0
  if [[ -e $agents || -L $agents ]]; then
    [[ -f $agents && ! -L $agents && -r $agents ]] ||
      fail "AGENTS.md must be a readable regular file (not a symlink): $agents"
    has_policy=$(awk -v s="$start" -v e="$end" '
      { line=$0; sub(/\r$/, "", line) }
      line == s { a++; if (a != 1 || b) exit 1 }
      line == e { b++; if (b != 1 || a != 1) exit 1 }
      END { if (a != b || a > 1 || b > 1) exit 1; print a+0 }
    ' "$agents") || fail 'AGENTS.md has incomplete, repeated, or out-of-order CCBR markers; resolve manually.'
  fi
  probe=$(mktemp "$repo/.ccbr-superpowers-preflight.XXXXXX") ||
    fail "Cannot create a temporary policy file in repository: $repo"
  rm -f "$probe"
}

if ((configure_repo)); then preflight_repository; fi

mkdir -p "$install_root/repos" "$skills_dir"

new_checkout=0
if [[ -e $checkout && ! -d $checkout/.git ]]; then
  fail_checkout "Existing path is not a Superpowers Git checkout: $checkout"
elif [[ ! -d $checkout/.git ]]; then
  clone_tmp=$(mktemp -d "$install_root/repos/.superpowers-clone.XXXXXX")
  temporary_paths+=("$clone_tmp")
  printf 'Cloning Superpowers into %s...\n' "$checkout"
  git clone --quiet "$repo_url" "$clone_tmp"
  [[ -d $clone_tmp/.git ]] || fail 'The temporary Superpowers clone is not a Git checkout.'
  clone_origin=$(git -C "$clone_tmp" config --get remote.origin.url || true)
  expected_remote "$clone_origin" || fail "Unexpected Superpowers origin: ${clone_origin:-none}"
  mv "$clone_tmp" "$checkout"
  new_checkout=1
fi

origin=$(git -C "$checkout" config --get remote.origin.url || true)
expected_remote "$origin" || fail_checkout "Unexpected Superpowers origin: ${origin:-none}"
if [[ -n $(git -C "$checkout" status --porcelain --untracked-files=all 2>/dev/null) ]]; then
  fail_checkout "Superpowers checkout has local changes: $checkout"
fi

printf 'Fetching Superpowers tags...\n'
git -C "$checkout" fetch --quiet --tags --force origin
git -C "$checkout" rev-parse --verify --quiet "refs/tags/$version^{commit}" >/dev/null ||
  fail "Superpowers tag $version was not found; the current installation was not changed."

stage=$(mktemp -d "${TMPDIR:-/tmp}/ccbr-superpowers.XXXXXX")
temporary_paths+=("$stage")
git -C "$checkout" archive --format=tar "refs/tags/$version" skills | tar -xf - -C "$stage"

valid_skills=()
shopt -s nullglob
for dir in "$stage/skills"/*; do
  [[ -d $dir && ! -L $dir ]] || continue
  name=${dir##*/}
  file=$dir/SKILL.md
  if [[ -f $file && -r $file ]] && skill_frontmatter_status "$name" "$file"; then
    valid_skills+=("$name")
  else
    warn "Skipping invalid skill in $version: $name"
  fi
done
((${#valid_skills[@]})) || fail "No valid skills were found in Superpowers $version."

contains_skill() {
  local wanted=$1 item
  for item in "${valid_skills[@]}"; do [[ $item == "$wanted" ]] && return 0; done
  return 1
}

desired_link() { printf '../repos/superpowers/skills/%s' "$1"; }
link_is_managed() {
  local target=$1 name=$2 value
  [[ -L $target ]] || return 1
  value=$(readlink "$target")
  [[ $value == "$(desired_link "$name")" || $value == "$checkout/skills/$name" ]]
}

conflicts=()
for name in "${valid_skills[@]}"; do
  target=$skills_dir/$name
  if [[ -e $target && ! -L $target ]]; then conflicts+=("$target"); fi
done
if ((${#conflicts[@]})); then
  printf 'The following entries conflict with approved Superpowers skills:\n' >&2
  printf '  %s\n' "${conflicts[@]}" >&2
  if ((!replace_conflicts)); then
    if [[ -r /dev/tty && -w /dev/tty ]]; then
      printf 'Back them up and install managed links? [y/N] ' >/dev/tty
      answer=
      IFS= read -r answer </dev/tty || true
      case "$answer" in y|Y|yes|YES|Yes) ;; *) fail 'No changes were made to conflicting skill entries.' ;; esac
    else
      fail 'Conflicts require an interactive confirmation or --replace-conflicts.'
    fi
  fi
fi

git -C "$checkout" checkout --detach --quiet "refs/tags/$version"
current=$(installed_version) || fail_checkout "Could not verify the checked-out version $version."
[[ $current == "$version" ]] || fail_checkout "Expected $version after checkout, found $current."

backup_dir=
if ((${#conflicts[@]})); then
  backup_dir=$skills_dir/.superpowers-backup-$(date '+%Y%m%d-%H%M%S')-$$
  mkdir -p "$backup_dir"
  for target in "${conflicts[@]}"; do mv "$target" "$backup_dir/"; done
  printf 'Backed up conflicting entries to %s.\n' "$backup_dir"
fi

created=0
repaired=0
correct=0
for name in "${valid_skills[@]}"; do
  target=$skills_dir/$name
  if link_is_managed "$target" "$name" && [[ -f $target/SKILL.md ]]; then
    ((correct+=1))
  else
    if [[ -L $target ]]; then rm "$target"; ((repaired+=1)); else ((created+=1)); fi
    ln -s "$(desired_link "$name")" "$target"
  fi
done

removed=0
while IFS= read -r name; do
  [[ -n $name ]] || continue
  if ! contains_skill "$name"; then
    target=$skills_dir/$name
    if link_is_managed "$target" "$name"; then rm "$target"; ((removed+=1)); fi
  fi
done < <(manifest_skills)

manifest_tmp=$(mktemp "$install_root/.ccbr-superpowers-managed.XXXXXX")
temporary_paths+=("$manifest_tmp")
{
  printf 'version=%s\n' "$version"
  for name in "${valid_skills[@]}"; do printf 'skill=%s\n' "$name"; done
} > "$manifest_tmp"
mv "$manifest_tmp" "$manifest"

file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || true
}

configure_repository() {
  local policy output mode inside line newline marker

  policy=$(mktemp "$repo/.ccbr-superpowers-policy.XXXXXX")
  output=$(mktemp "$repo/.AGENTS.md.XXXXXX")
  temporary_paths+=("$policy" "$output")
  write_policy > "$policy"

  if [[ -f $agents ]]; then
    if ((has_policy)); then
      inside=0
      while :; do
        line=
        if IFS= read -r line; then newline=1; elif [[ -n $line ]]; then newline=0; else break; fi
        marker=${line%$'\r'}
        if [[ $marker == "$start" ]]; then
          cat "$policy" >> "$output"
          inside=1
        elif [[ $marker == "$end" ]]; then
          inside=0
        elif ((!inside)); then
          printf '%s' "$line" >> "$output"
          if ((newline)); then printf '\n' >> "$output"; fi
        fi
      done < "$agents"
    else
      cat "$agents" > "$output"
      if [[ -s $agents && $(tail -c 1 "$agents" | wc -l) -eq 0 ]]; then printf '\n' >> "$output"; fi
      printf '\n' >> "$output"
      cat "$policy" >> "$output"
    fi
    mode=$(file_mode "$agents")
    [[ -z $mode ]] || chmod "$mode" "$output"
  else
    cat "$policy" > "$output"
    chmod 644 "$output"
  fi
  if [[ -f $agents ]] && cmp -s "$agents" "$output"; then
    printf 'AGENTS.md in %s is already current.\n' "$repo"
  else
    mv "$output" "$agents"
    printf 'Updated CCBR policy in %s.\n' "$agents"
  fi
}

if ((configure_repo)); then configure_repository; fi

printf 'Superpowers %s: %d created, %d repaired, %d already correct, %d obsolete removed.\n' \
  "$version" "$created" "$repaired" "$correct" "$removed"
if ((new_checkout)); then
  printf 'Installed new checkout at %s.\n' "$checkout"
fi
}

main "$@"
