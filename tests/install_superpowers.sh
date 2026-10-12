#!/usr/bin/env bash
set -euo pipefail

installer=$(cd "$(dirname "$0")/.." && pwd)/install_superpowers.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
upstream=$tmp/upstream
home=$tmp/home
install_root=$home/.claude

assert_contains() {
  grep -Fq "$2" "$1" || { printf 'Expected %s to contain: %s\n' "$1" "$2" >&2; cat "$1" >&2; exit 1; }
}
reject() {
  if "$@" >"$tmp/out" 2>&1; then
    printf 'Expected failure: %s\n' "$*" >&2
    exit 1
  fi
}
run_in() {
  local directory=$1
  shift
  (cd "$directory" &&
    HOME=$home CCBR_SUPERPOWERS_REPO_URL=$upstream CCBR_SUPERPOWERS_HOSTNAME=${CCBR_SUPERPOWERS_HOSTNAME:-NCI-TEST} \
      bash "$installer" "$@")
}
add_skill() {
  local name=$1
  mkdir -p "$upstream/skills/$name"
  printf '%s\n' '---' "name: $name" 'description: A test skill' '---' >"$upstream/skills/$name/SKILL.md"
}
commit_tag() {
  git -C "$upstream" add .
  git -C "$upstream" -c user.name=Test -c user.email=test@example.com commit -qm "$1"
  git -C "$upstream" tag "$2"
}

git init -q "$upstream"
add_skill brainstorming
add_skill writing-plans
commit_tag initial v6.4.2
git -C "$tmp" init -q project
mkdir -p "$tmp/project/nested/directory"
printf 'Project instructions\n' >"$tmp/project/AGENTS.md"

truncated_home=$tmp/truncated-home
sed '$d' "$installer" | (
  cd "$tmp/project"
  HOME=$truncated_home CCBR_SUPERPOWERS_REPO_URL=$upstream CCBR_SUPERPOWERS_HOSTNAME=NCI-TEST \
    bash -s --
)
[[ ! -e $truncated_home/.claude ]]
[[ $(cat "$tmp/project/AGENTS.md") == 'Project instructions' ]]

reject run_in "$tmp"
assert_contains "$tmp/out" 'Run this installer inside a Git working tree.'
[[ ! -e $install_root ]]

run() { run_in "$tmp/project/nested/directory" "$@"; }

run >"$tmp/out"
assert_contains "$tmp/out" 'Detected environment: GFE.'
assert_contains "$tmp/out" 'Superpowers v6.4.2: 2 created, 0 repaired, 0 already correct, 0 obsolete removed.'
[[ $(git -C "$install_root/repos/superpowers" describe --tags --exact-match) == v6.4.2 ]]
[[ $(readlink "$install_root/skills/brainstorming") == ../repos/superpowers/skills/brainstorming ]]
[[ -f $install_root/skills/brainstorming/SKILL.md ]]
assert_contains "$tmp/project/AGENTS.md" 'Project instructions'
assert_contains "$tmp/project/AGENTS.md" '<!-- CCBR-SUPERPOWERS-START -->'
assert_contains "$tmp/project/AGENTS.md" '`~/.claude/skills/`'
[[ ! -e $tmp/project/nested/directory/AGENTS.md ]]

run >"$tmp/out"
assert_contains "$tmp/out" '0 created, 0 repaired, 2 already correct, 0 obsolete removed.'
run --status >"$tmp/out"
assert_contains "$tmp/out" 'Superpowers v6.4.2 is installed'
assert_contains "$tmp/out" '2 managed skills available'

ln -sfn "$tmp/missing" "$install_root/skills/brainstorming"
run >"$tmp/out"
assert_contains "$tmp/out" '0 created, 1 repaired, 1 already correct, 0 obsolete removed.'
[[ $(readlink "$install_root/skills/brainstorming") == ../repos/superpowers/skills/brainstorming ]]

rm "$install_root/skills/writing-plans"
mkdir "$install_root/skills/writing-plans"
printf 'personal content\n' >"$install_root/skills/writing-plans/notes.txt"
run --replace-conflicts >"$tmp/out"
assert_contains "$tmp/out" 'Backed up conflicting entries to'
[[ -L $install_root/skills/writing-plans ]]
backup=$(find "$install_root/skills" -maxdepth 1 -type d -name '.superpowers-backup-*' -print -quit)
[[ -f $backup/writing-plans/notes.txt ]]

rm -rf "$upstream/skills/writing-plans"
add_skill systematic-debugging
commit_tag update v6.4.3
run --version v6.4.3 >"$tmp/out"
assert_contains "$tmp/out" 'Superpowers v6.4.3: 1 created, 0 repaired, 1 already correct, 1 obsolete removed.'
[[ $(git -C "$install_root/repos/superpowers" describe --tags --exact-match) == v6.4.3 ]]
[[ ! -e $install_root/skills/writing-plans && ! -L $install_root/skills/writing-plans ]]
[[ -L $install_root/skills/systematic-debugging ]]

run --version v6.4.2 >"$tmp/out"
assert_contains "$tmp/out" 'Superpowers v6.4.2: 1 created, 0 repaired, 1 already correct, 1 obsolete removed.'
[[ -L $install_root/skills/writing-plans ]]
[[ ! -e $install_root/skills/systematic-debugging && ! -L $install_root/skills/systematic-debugging ]]

before=$(git -C "$install_root/repos/superpowers" rev-parse HEAD)
reject run --version v9.9.9
assert_contains "$tmp/out" 'tag v9.9.9 was not found'
[[ $(git -C "$install_root/repos/superpowers" rev-parse HEAD) == "$before" ]]

[[ $(grep -Fc '<!-- CCBR-SUPERPOWERS-START -->' "$tmp/project/AGENTS.md") -eq 1 ]]
cp "$tmp/project/AGENTS.md" "$tmp/agents-original"
run >"$tmp/out"
cmp -s "$tmp/project/AGENTS.md" "$tmp/agents-original"

git -C "$tmp" init -q no-policy
run_in "$tmp/no-policy" --no-agents-policy >"$tmp/out"
[[ ! -e $tmp/no-policy/AGENTS.md ]]

unknown_home=$tmp/unknown-home
(cd "$tmp/project" &&
  HOME=$unknown_home CCBR_SUPERPOWERS_REPO_URL=$upstream CCBR_SUPERPOWERS_HOSTNAME=elsewhere \
    bash "$installer" --no-agents-policy) >"$tmp/out" 2>&1
assert_contains "$tmp/out" 'Unrecognized host; installing safely under HOME'
[[ -L $unknown_home/.claude/skills/brainstorming ]]

printf 'All installer tests passed.\n'
