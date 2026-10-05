#!/usr/bin/env bash
set -euo pipefail

installer=$(cd "$(dirname "$0")/.." && pwd)/install_superpowers.sh
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export CCBR_SUPERPOWERS_ROOT=$tmp/shared
mkdir -p "$CCBR_SUPERPOWERS_ROOT/skills"
git -C "$tmp" init -q repo
repo=$tmp/repo

skill() {
  mkdir -p "$CCBR_SUPERPOWERS_ROOT/skills/$1"
  printf '%s\n' '---' "name: $1" 'description: A test skill' '---' > "$CCBR_SUPERPOWERS_ROOT/skills/$1/SKILL.md"
}
run() { (cd "$1" && bash "$installer"); }
reject() {
  if run "$1" > "$tmp/out" 2>&1; then
    printf 'Expected failure: %s\n' "$1" >&2
    exit 1
  fi
  grep -Fq "$2" "$tmp/out" || { cat "$tmp/out" >&2; exit 1; }
}
assert_same() { cmp -s "$1" "$2" || { printf 'Unexpected content: %s\n' "$1" >&2; exit 1; }; }

skill brainstorming
reject "$tmp" 'inside a Git working tree'
mv "$CCBR_SUPERPOWERS_ROOT" "$tmp/hidden"
reject "$repo" 'Shared Superpowers installation'
mv "$tmp/hidden" "$CCBR_SUPERPOWERS_ROOT"
mv "$CCBR_SUPERPOWERS_ROOT/skills" "$tmp/hidden"
reject "$repo" 'Shared skills directory'
mv "$tmp/hidden" "$CCBR_SUPERPOWERS_ROOT/skills"

mkdir -p "$CCBR_SUPERPOWERS_ROOT/skills/invalid" "$CCBR_SUPERPOWERS_ROOT/skills/malformed"
printf '%s\n' 'not YAML' > "$CCBR_SUPERPOWERS_ROOT/skills/malformed/SKILL.md"
mkdir -p "$repo/.github/skills/project-release" "$repo/subdir"
echo 'Project instructions' > "$repo/AGENTS.md"
echo 'Project-owned skill' > "$repo/.github/skills/project-release/SKILL.md"
echo 'Existing Copilot policy' > "$repo/.github/copilot-instructions.md"
cp "$repo/.github/copilot-instructions.md" "$tmp/copilot-original"
run "$repo/subdir" > "$tmp/out"
grep -Fq '1 created' "$tmp/out"
[[ $(readlink "$repo/.github/skills/brainstorming") == "$CCBR_SUPERPOWERS_ROOT/skills/brainstorming" ]]
[[ ! -e $repo/.github/skills/invalid && ! -e $repo/.github/skills/malformed ]]
grep -Fxq 'Project instructions' "$repo/AGENTS.md"
grep -Fxq 'Project-owned skill' "$repo/.github/skills/project-release/SKILL.md"
assert_same "$repo/.github/copilot-instructions.md" "$tmp/copilot-original"
[[ ! -e $repo/.github/prompts ]]
cp "$repo/AGENTS.md" "$tmp/agents-original"
run "$repo" > "$tmp/out"
grep -Fq '0 created, 1 already correct' "$tmp/out"
assert_same "$repo/AGENTS.md" "$tmp/agents-original"
[[ $(grep -Fc '<!-- CCBR-SUPERPOWERS-START -->' "$repo/AGENTS.md") -eq 1 ]]

sed -i '/Superpowers is an optional workflow framework/c\OLD POLICY' "$repo/AGENTS.md"
run "$repo" > "$tmp/out"
grep -Fq 'AGENTS.md: updated' "$tmp/out"
assert_same "$repo/AGENTS.md" "$tmp/agents-original"

skill debugging
mkdir "$repo/.github/skills/debugging"
reject "$repo" 'Conflicts'
[[ -d $repo/.github/skills/debugging && ! -L $repo/.github/skills/debugging ]]
assert_same "$repo/AGENTS.md" "$tmp/agents-original"
 rmdir "$repo/.github/skills/debugging"
ln -s "$tmp/missing" "$repo/.github/skills/debugging"
reject "$repo" 'broken or unexpected symlink'
[[ -L $repo/.github/skills/debugging ]]
unlink "$repo/.github/skills/debugging"
ln -s "$CCBR_SUPERPOWERS_ROOT/skills/brainstorming" "$repo/.github/skills/debugging"
reject "$repo" 'broken or unexpected symlink'
unlink "$repo/.github/skills/debugging"
run "$repo" > "$tmp/out"
[[ -L $repo/.github/skills/debugging ]]

printf '%s\n' '<!-- CCBR-SUPERPOWERS-START -->' >> "$repo/AGENTS.md"
reject "$repo" 'incomplete, repeated, or out-of-order'
[[ $(grep -Fc '<!-- CCBR-SUPERPOWERS-START -->' "$repo/AGENTS.md") -eq 2 ]]
cp "$tmp/agents-original" "$repo/AGENTS.md"

git -C "$tmp" init -q clean
run "$tmp/clean" > "$tmp/out"
[[ -L $tmp/clean/.github/skills/brainstorming && -f $tmp/clean/AGENTS.md ]]
printf 'All installer tests passed.\n'
