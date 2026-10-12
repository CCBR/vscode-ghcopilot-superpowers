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
configure_repo=1
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
      --replace-conflicts Back up conflicting files/directories without prompting
      --no-agents-policy Do not update AGENTS.md with the CCBR policy
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
      shift 2
      ;;
    --status)
      show_status=1
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

if ((show_status)); then
  status
  exit $?
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
  if [[ -f $file && -r $file ]] && awk -v name="$name" '
    NR == 1 { if ($0 != "---") exit 1; next }
    $0 == "---" { closed=1; exit !(found_name && found_description) }
    /^name: / { found_name = (substr($0, 7) == name) }
    /^description: / { found_description = (length($0) > 13) }
    END { if (!closed || !found_name || !found_description) exit 1 }
  ' "$file"; then
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
  cat > "$policy" <<'POLICY'
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
