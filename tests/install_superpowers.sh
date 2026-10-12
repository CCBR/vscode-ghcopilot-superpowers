#!/usr/bin/env bash
set -euo pipefail

installer=$(cd "$(dirname "$0")/.." && pwd)/install_superpowers.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
upstream=$tmp/upstream
home=$tmp/home
install_root=$home/.claude

assert_contains() {
  grep -Fq -- "$2" "$1" || { printf 'Expected %s to contain: %s\n' "$1" "$2" >&2; cat "$1" >&2; exit 1; }
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
    HOME=$home CCBR_SUPERPOWERS_REPO_URL=$upstream \
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
git -C "$upstream" -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm v6.9.0
git -C "$upstream" tag v6.9.0
git -C "$upstream" -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm v6.10.0
git -C "$upstream" tag v6.10.0
git -C "$upstream" tag unrelated-tag
git -C "$upstream" reset --hard -q v6.4.2
git -C "$tmp" init -q project
mkdir -p "$tmp/project/nested/directory"
printf 'Project instructions\n' >"$tmp/project/AGENTS.md"

dry_home=$tmp/dry-home
project_status_before=$(git -C "$tmp/project" status --porcelain=v1 --untracked-files=all)
agents_checksum_before=$(cksum "$tmp/project/AGENTS.md")
(cd "$tmp/project/nested/directory" &&
  HOME=$dry_home CCBR_SUPERPOWERS_REPO_URL=$upstream \
    bash "$installer" --dry-run) >"$tmp/out"
assert_contains "$tmp/out" 'DRY RUN: no repository or personal installation changes will be made.'
assert_contains "$tmp/out" 'Planned changes:'
assert_contains "$tmp/out" "Clone Superpowers into $dry_home/.claude/repos/superpowers."
assert_contains "$tmp/out" 'Fetch upstream Superpowers tags.'
assert_contains "$tmp/out" 'Check out v6.4.2.'
assert_contains "$tmp/out" 'Create managed skill link: brainstorming.'
assert_contains "$tmp/out" 'Create managed skill link: writing-plans.'
assert_contains "$tmp/out" 'Write managed-skills manifest for v6.4.2 (2 skills).'
assert_contains "$tmp/out" "Update repository policy: $tmp/project/AGENTS.md."
assert_contains "$tmp/out" 'Already correct:'
[[ ! -e $dry_home/.claude ]]
[[ $(cksum "$tmp/project/AGENTS.md") == "$agents_checksum_before" ]]
[[ $(git -C "$tmp/project" status --porcelain=v1 --untracked-files=all) == "$project_status_before" ]]

linked_dry_home=$tmp/linked-dry-home
mkdir -p "$linked_dry_home/.claude/skills"
ln -s ../repos/superpowers/skills/brainstorming "$linked_dry_home/.claude/skills/brainstorming"
ln -s ../repos/superpowers/skills/missing "$linked_dry_home/.claude/skills/writing-plans"
(cd "$tmp/project" &&
  HOME=$linked_dry_home CCBR_SUPERPOWERS_REPO_URL=$upstream \
    bash "$installer" --dry-run --no-agents-policy) >"$tmp/out"
assert_contains "$tmp/out" 'Managed skill link is already correct: brainstorming.'
assert_contains "$tmp/out" 'Repair managed skill link: writing-plans.'
! grep -Fq 'Repair managed skill link: brainstorming.' "$tmp/out"
[[ $(readlink "$linked_dry_home/.claude/skills/brainstorming") == ../repos/superpowers/skills/brainstorming ]]
[[ ! -e $linked_dry_home/.claude/repos ]]

invalid_version_bin=$tmp/invalid-version-bin
mkdir -p "$invalid_version_bin"
cat >"$invalid_version_bin/git" <<EOF
#!/usr/bin/env bash
if [[ \$1 == clone ]]; then printf 'unexpected clone\n' >&2; exit 99; fi
exec $(command -v git) "\$@"
EOF
chmod +x "$invalid_version_bin/git"
if (cd "$tmp/project" &&
  PATH="$invalid_version_bin:$PATH" HOME=$dry_home CCBR_SUPERPOWERS_REPO_URL=$upstream \
    bash "$installer" --dry-run --version 'bad tag') >"$tmp/out" 2>&1; then
  printf 'Expected invalid dry-run version failure\n' >&2
  exit 1
fi
assert_contains "$tmp/out" 'Invalid version tag: bad tag'
! grep -Fq 'unexpected clone' "$tmp/out"

stdin_dry_home=$tmp/stdin-dry-home
(cd "$tmp/project/nested/directory" &&
  HOME=$stdin_dry_home CCBR_SUPERPOWERS_REPO_URL=$upstream \
    bash -s -- --dry-run <"$installer") >"$tmp/out"
assert_contains "$tmp/out" 'DRY RUN: no repository or personal installation changes will be made.'
assert_contains "$tmp/out" "Update repository policy: $tmp/project/AGENTS.md."
[[ ! -e $stdin_dry_home/.claude ]]

if ! (cd "$tmp/project" &&
  HOME=$dry_home CCBR_SUPERPOWERS_INSTALL_ROOT=relative-install \
    CCBR_SUPERPOWERS_REPO_URL=$upstream \
    timeout 5 bash "$installer" --dry-run --no-agents-policy) >"$tmp/out" 2>&1; then
  printf 'Expected dry-run to handle a relative install root without hanging\n' >&2
  cat "$tmp/out" >&2
  exit 1
fi
assert_contains "$tmp/out" 'Clone Superpowers into relative-install/repos/superpowers.'
[[ ! -e $tmp/project/relative-install ]]

list_home=$tmp/list-home
(cd "$tmp/project" &&
  HOME=$list_home CCBR_SUPERPOWERS_REPO_URL=$upstream \
    bash "$installer" --list-versions) >"$tmp/out"
assert_contains "$tmp/out" 'Available Superpowers versions:'
listed_versions=$(sed -n 's/^  \(v[0-9].*\)$/\1/p' "$tmp/out" | paste -sd ' ' -)
[[ $listed_versions == 'v6.10.0 v6.9.0 v6.4.2' ]]
! grep -Fq 'unrelated-tag' "$tmp/out"
[[ ! -e $list_home/.claude ]]
[[ $(cat "$tmp/project/AGENTS.md") == 'Project instructions' ]]

if (cd "$tmp/project" &&
  HOME=$list_home CCBR_SUPERPOWERS_REPO_URL=$tmp/missing-upstream \
    bash "$installer" --list-versions) >"$tmp/out" 2>&1; then
  printf 'Expected version-list failure\n' >&2
  exit 1
fi
assert_contains "$tmp/out" 'Could not list Superpowers versions from'
[[ ! -e $list_home/.claude ]]

truncated_home=$tmp/truncated-home
sed '$d' "$installer" | (
  cd "$tmp/project"
  HOME=$truncated_home CCBR_SUPERPOWERS_REPO_URL=$upstream \
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
  PATH="$fake_bin:$PATH" HOME=$failed_home CCBR_SUPERPOWERS_REPO_URL=$upstream \
    bash "$installer") >"$tmp/out" 2>&1; then
  printf 'Expected simulated clone failure\n' >&2
  exit 1
fi
[[ ! -e $failed_home/.claude/repos/superpowers ]]
[[ -z $(find "$failed_home/.claude/repos" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null) ]]

missing_tag_home=$tmp/missing-tag-home
if (cd "$tmp/project" &&
  HOME=$missing_tag_home CCBR_SUPERPOWERS_REPO_URL=$upstream \
    bash "$installer" --version v9.9.9 --no-agents-policy) >"$tmp/out" 2>&1; then
  printf 'Expected unavailable fresh-install version failure\n' >&2
  exit 1
fi
assert_contains "$tmp/out" 'Superpowers tag v9.9.9 was not found'
[[ ! -e $missing_tag_home/.claude/repos/superpowers ]]
[[ ! -e $missing_tag_home/.claude/.ccbr-superpowers-managed ]]
[[ -z $(find "$missing_tag_home/.claude/skills" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null) ]]

invalid_upstream=$tmp/invalid-upstream
git clone -q "$upstream" "$invalid_upstream"
rm -rf "$invalid_upstream/skills"
mkdir -p "$invalid_upstream/skills/broken"
printf 'invalid frontmatter\n' >"$invalid_upstream/skills/broken/SKILL.md"
git -C "$invalid_upstream" add .
git -C "$invalid_upstream" -c user.name=Test -c user.email=test@example.com commit -qm invalid
git -C "$invalid_upstream" tag v6.4.3
invalid_skills_home=$tmp/invalid-skills-home
if (cd "$tmp/project" &&
  HOME=$invalid_skills_home CCBR_SUPERPOWERS_REPO_URL=$invalid_upstream \
    bash "$installer" --version v6.4.3 --no-agents-policy) >"$tmp/out" 2>&1; then
  printf 'Expected invalid fresh-install skills failure\n' >&2
  exit 1
fi
assert_contains "$tmp/out" 'No valid skills were found in Superpowers v6.4.3.'
[[ ! -e $invalid_skills_home/.claude/repos/superpowers ]]
[[ ! -e $invalid_skills_home/.claude/.ccbr-superpowers-managed ]]
[[ -z $(find "$invalid_skills_home/.claude/skills" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null) ]]

invalid_home=$tmp/invalid-home
mkdir -p "$invalid_home/.claude/repos/superpowers"
printf 'keep me\n' >"$invalid_home/.claude/repos/superpowers/file"
if (cd "$tmp/project" &&
  HOME=$invalid_home CCBR_SUPERPOWERS_REPO_URL=$upstream \
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
  HOME=$malformed_home CCBR_SUPERPOWERS_REPO_URL=$upstream \
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
  HOME=$linked_home CCBR_SUPERPOWERS_REPO_URL=$upstream \
    bash "$installer" --dry-run) >"$tmp/out" 2>&1; then
  printf 'Expected symlinked AGENTS.md dry-run failure\n' >&2
  exit 1
fi
assert_contains "$tmp/out" 'AGENTS.md must be a readable regular file (not a symlink)'
[[ ! -e $linked_home/.claude ]]
if (cd "$tmp/linked-policy" &&
  HOME=$linked_home CCBR_SUPERPOWERS_REPO_URL=$upstream \
    bash "$installer") >"$tmp/out" 2>&1; then
  printf 'Expected symlinked AGENTS.md failure\n' >&2
  exit 1
fi
assert_contains "$tmp/out" 'AGENTS.md must be a readable regular file (not a symlink)'
[[ ! -e $linked_home/.claude ]]

opt_out_home=$tmp/opt-out-home
(cd "$tmp/malformed-policy" &&
  HOME=$opt_out_home CCBR_SUPERPOWERS_REPO_URL=$upstream \
    bash "$installer" --no-agents-policy) >"$tmp/out"
[[ -L $opt_out_home/.claude/skills/brainstorming ]]

reject run_in "$tmp"
assert_contains "$tmp/out" 'Run this installer inside a Git working tree.'
[[ ! -e $install_root ]]

run() { run_in "$tmp/project/nested/directory" "$@"; }

reject run --verify --status
assert_contains "$tmp/out" '--verify cannot be combined with'
reject run --verify --list-versions
assert_contains "$tmp/out" '--verify cannot be combined with'
reject run --verify --version v6.4.2
assert_contains "$tmp/out" '--verify cannot be combined with'
reject run --verify --replace-conflicts
assert_contains "$tmp/out" '--verify cannot be combined with'

run >"$tmp/out"
assert_contains "$tmp/out" "Using personal Superpowers directory: $install_root"
assert_contains "$tmp/out" 'Superpowers v6.4.2: 2 created, 0 repaired, 0 already correct, 0 obsolete removed.'
[[ $(git -C "$install_root/repos/superpowers" describe --tags --exact-match) == v6.4.2 ]]
[[ $(readlink "$install_root/skills/brainstorming") == ../repos/superpowers/skills/brainstorming ]]
[[ -f $install_root/skills/brainstorming/SKILL.md ]]
assert_contains "$tmp/project/AGENTS.md" 'Project instructions'
assert_contains "$tmp/project/AGENTS.md" '<!-- CCBR-SUPERPOWERS-START -->'
assert_contains "$tmp/project/AGENTS.md" '`~/.claude/skills/`'
assert_contains "$tmp/project/AGENTS.md" 'If a requested Superpowers skill is unavailable'
assert_contains "$tmp/project/AGENTS.md" 'https://raw.githubusercontent.com/CCBR/vscode-ghcopilot-superpowers/main/install_superpowers.sh'
assert_contains "$tmp/project/AGENTS.md" 'Do not install Superpowers automatically.'
assert_contains "$tmp/project/AGENTS.md" 'Do not create or use repository-local links'
[[ ! -e $tmp/project/nested/directory/AGENTS.md ]]

find "$install_root" "$tmp/project" -printf '%p|%y|%m|%s|%T@|%l\n' | sort >"$tmp/verify-state-before"
run --verify >"$tmp/out"
assert_contains "$tmp/out" 'OK: Installed version: v6.4.2'
assert_contains "$tmp/out" "OK: Checkout commit: $(git -C "$install_root/repos/superpowers" rev-parse HEAD)"
assert_contains "$tmp/out" 'OK: Manifest matches active checkout (2 skills).'
assert_contains "$tmp/out" 'OK: Skill brainstorming is healthy.'
assert_contains "$tmp/out" 'OK: Repository policy markers are valid:'
assert_contains "$tmp/out" 'Verification summary:'
assert_contains "$tmp/out" '8 healthy, 0 warnings, 0 errors.'
find "$install_root" "$tmp/project" -printf '%p|%y|%m|%s|%T@|%l\n' | sort >"$tmp/verify-state-after"
cmp -s "$tmp/verify-state-before" "$tmp/verify-state-after"

find "$install_root" "$tmp/project" -printf '%p|%y|%m|%s|%T@|%l\n' | sort >"$tmp/dry-state-before"
run --dry-run >"$tmp/out"
assert_contains "$tmp/out" 'Checkout is already at v6.4.2.'
assert_contains "$tmp/out" 'Managed skill link is already correct: brainstorming.'
assert_contains "$tmp/out" 'Managed skill link is already correct: writing-plans.'
assert_contains "$tmp/out" 'Managed-skills manifest is already correct for v6.4.2.'
assert_contains "$tmp/out" 'Repository policy is already current:'
find "$install_root" "$tmp/project" -printf '%p|%y|%m|%s|%T@|%l\n' | sort >"$tmp/dry-state-after"
cmp -s "$tmp/dry-state-before" "$tmp/dry-state-after"

run --dry-run --no-agents-policy >"$tmp/out"
assert_contains "$tmp/out" 'Repository policy update is disabled by --no-agents-policy.'

cp "$tmp/project/AGENTS.md" "$tmp/agents-dry-good"
sed -i 's/## CCBR Superpowers integration/## Stale CCBR Superpowers integration/' "$tmp/project/AGENTS.md"
run --dry-run >"$tmp/out"
assert_contains "$tmp/out" "Update repository policy: $tmp/project/AGENTS.md."
cp "$tmp/agents-dry-good" "$tmp/project/AGENTS.md"

reject run --dry-run --version v9.9.9
assert_contains "$tmp/out" 'Superpowers tag v9.9.9 was not found; no changes were made.'

printf 'dirty\n' >"$install_root/repos/superpowers/dry-run-dirty"
reject run --dry-run
assert_contains "$tmp/out" "Superpowers checkout has local changes: $install_root/repos/superpowers"
rm "$install_root/repos/superpowers/dry-run-dirty"

printf '%s\n' '<!-- CCBR-SUPERPOWERS-START -->' 'incomplete policy' >"$tmp/project/AGENTS.md"
reject run --dry-run
assert_contains "$tmp/out" 'AGENTS.md has incomplete, repeated, or out-of-order CCBR markers'
cmp -s "$tmp/project/AGENTS.md" <(printf '%s\n' '<!-- CCBR-SUPERPOWERS-START -->' 'incomplete policy')
cp "$tmp/agents-dry-good" "$tmp/project/AGENTS.md"

rm "$install_root/skills/writing-plans"
mkdir "$install_root/skills/writing-plans"
printf 'personal content\n' >"$install_root/skills/writing-plans/notes.txt"
reject run --dry-run
assert_contains "$tmp/out" 'requires --replace-conflicts; no changes were made'
run --dry-run --replace-conflicts >"$tmp/out"
assert_contains "$tmp/out" "Back up conflicting skill entry: $install_root/skills/writing-plans."
assert_contains "$tmp/out" 'Create managed skill link: writing-plans.'
[[ -f $install_root/skills/writing-plans/notes.txt && ! -L $install_root/skills/writing-plans ]]
rm -rf "$install_root/skills/writing-plans"
ln -s ../repos/superpowers/skills/writing-plans "$install_root/skills/writing-plans"

rm "$install_root/skills/brainstorming"
reject run --verify
assert_contains "$tmp/out" 'ERROR: Managed skill link is missing: brainstorming.'
assert_contains "$tmp/out" 'Repair: rerun the installer for v6.4.2.'
ln -s ../repos/superpowers/skills/brainstorming "$install_root/skills/brainstorming"

ln -sfn ../repos/superpowers/skills/writing-plans "$install_root/skills/brainstorming"
reject run --verify
assert_contains "$tmp/out" 'ERROR: Managed skill link has the wrong target: brainstorming.'
assert_contains "$tmp/out" 'Repair: rerun the installer for v6.4.2.'
ln -sfn ../repos/superpowers/skills/brainstorming "$install_root/skills/brainstorming"

ln -sfn ../repos/superpowers/skills/missing "$install_root/skills/brainstorming"
reject run --verify
assert_contains "$tmp/out" 'ERROR: Managed skill link has the wrong target: brainstorming.'
assert_contains "$tmp/out" 'Repair: rerun the installer for v6.4.2.'
ln -sfn ../repos/superpowers/skills/brainstorming "$install_root/skills/brainstorming"

printf 'dirty\n' >"$install_root/repos/superpowers/dirty"
reject run --verify
assert_contains "$tmp/out" 'ERROR: Checkout has local changes.'
assert_contains "$tmp/out" "Repair: back up changes, delete $install_root/repos/superpowers, and rerun the installer."
rm "$install_root/repos/superpowers/dirty"

git -C "$install_root/repos/superpowers" remote set-url origin "$tmp/wrong-origin"
reject run --verify
assert_contains "$tmp/out" "ERROR: Checkout origin is unexpected: $tmp/wrong-origin."
assert_contains "$tmp/out" "Repair: back up changes, delete $install_root/repos/superpowers, and rerun the installer."
git -C "$install_root/repos/superpowers" remote set-url origin "$upstream"

cp "$install_root/.ccbr-superpowers-managed" "$tmp/manifest-good"
printf '%s\n' 'version=v6.4.2' 'skill=brainstorming' 'invalid manifest line' >"$install_root/.ccbr-superpowers-managed"
reject run --verify
assert_contains "$tmp/out" 'ERROR: Managed-skills manifest is malformed:'
assert_contains "$tmp/out" 'Repair: rerun the installer for v6.4.2.'
cp "$tmp/manifest-good" "$install_root/.ccbr-superpowers-managed"

cp "$tmp/project/AGENTS.md" "$tmp/agents-good"
printf '%s\n' '<!-- CCBR-SUPERPOWERS-START -->' 'incomplete policy' >"$tmp/project/AGENTS.md"
reject run --verify
assert_contains "$tmp/out" 'ERROR: Repository policy markers are incomplete, repeated, or out of order:'
assert_contains "$tmp/out" 'Repair: resolve the CCBR marker section manually, then rerun the installer.'
run --verify --no-agents-policy >"$tmp/out"
assert_contains "$tmp/out" 'WARNING: Repository policy verification was skipped by --no-agents-policy.'
assert_contains "$tmp/out" '7 healthy, 1 warnings, 0 errors.'
cp "$tmp/agents-good" "$tmp/project/AGENTS.md"

printf '%s\n' 'version=v6.4.2' 'skill=brainstorming' >"$install_root/.ccbr-superpowers-managed"
reject run --verify
assert_contains "$tmp/out" 'ERROR: Manifest is missing active skill: writing-plans.'
cp "$tmp/manifest-good" "$install_root/.ccbr-superpowers-managed"

mv "$install_root/repos/superpowers/skills/brainstorming" "$tmp/brainstorming-missing"
reject run --verify
assert_contains "$tmp/out" 'ERROR: Manifest contains obsolete skill: brainstorming.'
assert_contains "$tmp/out" 'ERROR: Obsolete managed skill link is broken: brainstorming.'
assert_contains "$tmp/out" 'Repair: rerun the installer for v6.4.2.'
mv "$tmp/brainstorming-missing" "$install_root/repos/superpowers/skills/brainstorming"

printf '%s\n' 'version=v6.4.2' 'skill=brainstorming' 'skill=writing-plans' 'skill=obsolete' >"$install_root/.ccbr-superpowers-managed"
ln -s ../repos/superpowers/skills/obsolete "$install_root/skills/obsolete"
reject run --verify
assert_contains "$tmp/out" 'ERROR: Manifest contains obsolete skill: obsolete.'
assert_contains "$tmp/out" 'Repair: rerun the installer for v6.4.2.'
rm "$install_root/skills/obsolete"
cp "$tmp/manifest-good" "$install_root/.ccbr-superpowers-managed"

mkdir -p "$install_root/repos/superpowers/skills/obsolete"
printf '%s\n' '---' 'name: obsolete' 'description: Obsolete test skill' '---' >"$install_root/repos/superpowers/skills/obsolete/SKILL.md"
ln -s ../repos/superpowers/skills/obsolete "$install_root/skills/obsolete"
reject run --verify
assert_contains "$tmp/out" 'ERROR: Unexpected managed-looking skill link: obsolete.'
assert_contains "$tmp/out" 'Repair: remove the obsolete link or rerun the installer.'
rm "$install_root/skills/obsolete"
rm -rf "$install_root/repos/superpowers/skills/obsolete"

cp "$install_root/repos/superpowers/skills/brainstorming/SKILL.md" "$tmp/skill-good"
sed -i 's/name: brainstorming/name: wrong-name/' "$install_root/repos/superpowers/skills/brainstorming/SKILL.md"
reject run --verify
assert_contains "$tmp/out" 'ERROR: Skill frontmatter name does not match its directory: brainstorming.'
assert_contains "$tmp/out" 'Repair: back up changes, delete the checkout, and rerun the installer.'
cp "$tmp/skill-good" "$install_root/repos/superpowers/skills/brainstorming/SKILL.md"

sed -i '/^description: /d' "$install_root/repos/superpowers/skills/brainstorming/SKILL.md"
reject run --verify
assert_contains "$tmp/out" 'ERROR: Skill frontmatter is invalid: brainstorming.'
assert_contains "$tmp/out" 'Repair: back up changes, delete the checkout, and rerun the installer.'
cp "$tmp/skill-good" "$install_root/repos/superpowers/skills/brainstorming/SKILL.md"

verify_fake_bin=$tmp/verify-fake-bin
mkdir -p "$verify_fake_bin"
cat >"$verify_fake_bin/git" <<EOF
#!/usr/bin/env bash
case " \$* " in
  *' fetch '*|*' ls-remote '*) printf 'verify attempted network access\n' >&2; exit 99 ;;
esac
exec $(command -v git) "\$@"
EOF
chmod +x "$verify_fake_bin/git"
(cd "$tmp/project/nested/directory" &&
  PATH="$verify_fake_bin:$PATH" HOME=$home CCBR_SUPERPOWERS_REPO_URL=$upstream \
    bash "$installer" --verify) >"$tmp/out"
  assert_contains "$tmp/out" '8 healthy, 0 warnings, 0 errors.'

run >"$tmp/out"
assert_contains "$tmp/out" '0 created, 0 repaired, 2 already correct, 0 obsolete removed.'
run --status >"$tmp/out"
assert_contains "$tmp/out" 'Superpowers v6.4.2 is installed'
assert_contains "$tmp/out" '2 managed skills available'
checkout_before=$(git -C "$install_root/repos/superpowers" rev-parse HEAD)
cp "$install_root/.ccbr-superpowers-managed" "$tmp/manifest-before"
find "$install_root/skills" -maxdepth 1 -type l -printf '%f=%l\n' | sort >"$tmp/links-before"
cp "$tmp/project/AGENTS.md" "$tmp/agents-before-list"
run --list-versions >"$tmp/out"
assert_contains "$tmp/out" '  v6.4.2 (installed)'
[[ $(git -C "$install_root/repos/superpowers" rev-parse HEAD) == "$checkout_before" ]]
cmp -s "$install_root/.ccbr-superpowers-managed" "$tmp/manifest-before"
find "$install_root/skills" -maxdepth 1 -type l -printf '%f=%l\n' | sort >"$tmp/links-after"
cmp -s "$tmp/links-before" "$tmp/links-after"
cmp -s "$tmp/project/AGENTS.md" "$tmp/agents-before-list"

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
find "$install_root" "$tmp/project" -printf '%p|%y|%m|%s|%T@|%l\n' | sort >"$tmp/upgrade-dry-before"
run --dry-run --version v6.4.3 >"$tmp/out"
assert_contains "$tmp/out" 'Check out v6.4.3.'
assert_contains "$tmp/out" 'Managed skill link is already correct: brainstorming.'
assert_contains "$tmp/out" 'Create managed skill link: systematic-debugging.'
assert_contains "$tmp/out" 'Remove obsolete managed skill link: writing-plans.'
assert_contains "$tmp/out" 'Write managed-skills manifest for v6.4.3 (2 skills).'
find "$install_root" "$tmp/project" -printf '%p|%y|%m|%s|%T@|%l\n' | sort >"$tmp/upgrade-dry-after"
cmp -s "$tmp/upgrade-dry-before" "$tmp/upgrade-dry-after"
[[ $(git -C "$install_root/repos/superpowers" describe --tags --exact-match) == v6.4.2 ]]

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
  HOME=$unknown_home CCBR_SUPERPOWERS_REPO_URL=$upstream \
    bash "$installer" --no-agents-policy) >"$tmp/out" 2>&1
assert_contains "$tmp/out" "Using personal Superpowers directory: $unknown_home/.claude"
[[ -L $unknown_home/.claude/skills/brainstorming ]]

printf 'All installer tests passed.\n'
