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

fake_bin=$tmp/fake-bin
failed_home=$tmp/failed-home
mkdir -p "$fake_bin"
cat >"$fake_bin/git" <<EOF
#!/usr/bin/env bash
if [[ \$1 == clone ]]; then
  destination=\${!#}
  mkdir -p "\$destination"
  printf 'partial clone\n' >"\$destination/incomplete"
  exit 1
fi
exec $(command -v git) "\$@"
EOF
chmod +x "$fake_bin/git"
if (cd "$tmp/project" &&
  PATH="$fake_bin:$PATH" HOME=$failed_home CCBR_SUPERPOWERS_REPO_URL=$upstream CCBR_SUPERPOWERS_HOSTNAME=NCI-TEST \
    bash "$installer") >"$tmp/out" 2>&1; then
  printf 'Expected simulated clone failure\n' >&2
  exit 1
fi
[[ ! -e $failed_home/.claude/repos/superpowers ]]
[[ -z $(find "$failed_home/.claude/repos" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null) ]]

invalid_home=$tmp/invalid-home
mkdir -p "$invalid_home/.claude/repos/superpowers"
printf 'keep me\n' >"$invalid_home/.claude/repos/superpowers/file"
if (cd "$tmp/project" &&
  HOME=$invalid_home CCBR_SUPERPOWERS_REPO_URL=$upstream CCBR_SUPERPOWERS_HOSTNAME=NCI-TEST \
    bash "$installer") >"$tmp/out" 2>&1; then
  printf 'Expected invalid checkout failure\n' >&2
  exit 1
fi
assert_contains "$tmp/out" "Back up anything you need, delete $invalid_home/.claude/repos/superpowers, and try again."
[[ -f $invalid_home/.claude/repos/superpowers/file ]]

git -C "$tmp" init -q malformed-policy
malformed_home=$tmp/malformed-home
printf '%s\n' '<!-- CCBR-SUPERPOWERS-START -->' 'incomplete policy' >"$tmp/malformed-policy/AGENTS.md"
if (cd "$tmp/malformed-policy" &&
  HOME=$malformed_home CCBR_SUPERPOWERS_REPO_URL=$upstream CCBR_SUPERPOWERS_HOSTNAME=NCI-TEST \
    bash "$installer") >"$tmp/out" 2>&1; then
  printf 'Expected malformed AGENTS.md failure\n' >&2
  exit 1
fi
assert_contains "$tmp/out" 'AGENTS.md has incomplete, repeated, or out-of-order CCBR markers'
[[ ! -e $malformed_home/.claude ]]

git -C "$tmp" init -q linked-policy
linked_home=$tmp/linked-home
printf 'Shared instructions\n' >"$tmp/shared-agents.md"
ln -s "$tmp/shared-agents.md" "$tmp/linked-policy/AGENTS.md"
if (cd "$tmp/linked-policy" &&
  HOME=$linked_home CCBR_SUPERPOWERS_REPO_URL=$upstream CCBR_SUPERPOWERS_HOSTNAME=NCI-TEST \
    bash "$installer") >"$tmp/out" 2>&1; then
  printf 'Expected symlinked AGENTS.md failure\n' >&2
  exit 1
fi
assert_contains "$tmp/out" 'AGENTS.md must be a readable regular file (not a symlink)'
[[ ! -e $linked_home/.claude ]]

opt_out_home=$tmp/opt-out-home
(cd "$tmp/malformed-policy" &&
  HOME=$opt_out_home CCBR_SUPERPOWERS_REPO_URL=$upstream CCBR_SUPERPOWERS_HOSTNAME=NCI-TEST \
    bash "$installer" --no-agents-policy) >"$tmp/out"
[[ -L $opt_out_home/.claude/skills/brainstorming ]]

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

git -C "$install_root/repos/superpowers" remote set-url origin "$tmp/wrong-origin"
reject run
assert_contains "$tmp/out" "Back up anything you need, delete $install_root/repos/superpowers, and try again."
git -C "$install_root/repos/superpowers" remote set-url origin "$upstream"

printf 'local change\n' >"$install_root/repos/superpowers/local-change"
reject run
assert_contains "$tmp/out" "Back up anything you need, delete $install_root/repos/superpowers, and try again."
rm "$install_root/repos/superpowers/local-change"

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
