#!/usr/bin/env bash
set -euo pipefail

shared=${CCBR_SUPERPOWERS_ROOT:-/data/CCBR_Pipeliner/db/PipeDB/AI/superpowers}
start='<!-- CCBR-SUPERPOWERS-START -->'
end='<!-- CCBR-SUPERPOWERS-END -->'

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
repo=$(git rev-parse --show-toplevel 2>/dev/null) || fail 'Run this installer inside a Git working tree.'
repo=$(cd "$repo" && pwd -P)
case "$repo/" in
  /data/CCBR_Pipeliner/db/PipeDB/AI/superpowers/*|/data/CCBR_Pipeliner/db/PipeDB/AI/vscode-ghcopilot-superpowers/*)
    fail 'Refusing to configure a shared CCBR checkout.' ;;
esac
[[ -d $shared && -r $shared && -x $shared ]] || fail "Shared Superpowers installation is missing or unreadable: $shared"
if [[ $shared != /* ]]; then shared=$(cd "$shared" && pwd -P); fi
skills=$shared/skills
[[ -d $skills && -r $skills && -x $skills ]] || fail "Shared skills directory is missing or unreadable: $skills"

agents=$repo/AGENTS.md
has_policy=0
for path in "$repo/.github" "$repo/.github/skills"; do
  if [[ -e $path || -L $path ]]; then
    [[ -d $path && ! -L $path ]] || fail "Expected an ordinary directory, not a conflicting entry: $path"
  fi
done
if [[ -e $agents || -L $agents ]]; then
  [[ -f $agents && ! -L $agents && -r $agents ]] || fail "AGENTS.md must be a readable regular file (not a symlink): $agents"
  has_policy=$(awk -v s="$start" -v e="$end" '
    { line=$0; sub(/\r$/, "", line) }
    line == s { a++; if (a != 1 || b) exit 1 }
    line == e { b++; if (b != 1 || a != 1) exit 1 }
    END { if (a != b || a > 1 || b > 1) exit 1; print a+0 }
  ' "$agents") || fail 'AGENTS.md has incomplete, repeated, or out-of-order CCBR markers; resolve manually.'
fi

shopt -s nullglob
valid=()
conflicts=()
invalid=0
correct=0
for dir in "$skills"/*; do
  [[ -d $dir && ! -L $dir ]] || continue
  name=${dir##*/}
  file=$dir/SKILL.md
  if [[ ! -f $file || ! -r $file ]] || ! awk -v name="$name" '
    NR == 1 { if ($0 != "---") exit 1; next }
    $0 == "---" { exit !(found_name && found_description) }
    /^name: / { found_name = (substr($0, 7) == name) }
    /^description: / { found_description = (length($0) > 13) }
    END { if (NR < 2 || $0 != "---" || !found_name || !found_description) exit 1 }
  ' "$file"; then
    printf 'Skipped invalid skill: %s (SKILL.md needs matching name and description frontmatter)\n' "$name" >&2
    ((invalid+=1))
    continue
  fi
  valid+=("$dir")
  target=$repo/.github/skills/$name
  if [[ -L $target ]]; then
    if [[ $(readlink "$target") == "$dir" && -d $target && -f $target/SKILL.md ]]; then
      ((correct+=1))
    else
      conflicts+=("$target (broken or unexpected symlink)")
    fi
  elif [[ -e $target ]]; then
    conflicts+=("$target (existing project-owned entry)")
  fi
done
((${#valid[@]})) || fail "No valid skills found in $skills ($invalid invalid/skipped)."
if ((${#conflicts[@]})); then
  printf 'Conflicts (%d); no changes made:\n' "${#conflicts[@]}" >&2
  printf '  %s\n' "${conflicts[@]}" >&2
  fail 'Resolve skill-name conflicts manually, then rerun.'
fi

policy=$(mktemp "$repo/.ccbr-superpowers-policy.XXXXXX") || fail 'Cannot create temporary policy file.'
output=
trap 'rm -f -- "$policy" ${output:+"$output"}' EXIT
cat > "$policy" <<'POLICY'
<!-- CCBR-SUPERPOWERS-START -->
## CCBR Superpowers integration

Superpowers skills are available through this repository's VS Code Agent Skills integration in `.github/skills/`. The shared CCBR installation is authoritative for skill definitions. This repository policy determines whether a skill should be invoked; discovery alone never requires its use. Once deliberately selected, the chosen skill governs its workflow.

## Superpowers usage policy

Superpowers is an optional workflow framework, not the default way to perform tasks.

Optimize for **correctness, speed, and token efficiency**. For routine work, prefer direct repository inspection, implementation, and targeted validation using the normal available tools.

### Default: do not invoke Superpowers

Do NOT invoke a Superpowers skill merely because it appears relevant to the task.

For small, routine, low-risk, or well-understood tasks, work directly without Superpowers.

Examples that normally should NOT use Superpowers include:

- Documentation, README, comments, spelling, formatting, or other prose-only changes.
- Minor configuration changes.
- Small bug fixes with an obvious cause and solution.
- Small or mechanical refactors.
- Adding or modifying a few lines/functions where the implementation is clear.
- Routine dependency/version updates.
- Simple test changes.
- Code explanation or repository exploration.
- Other inconsequential changes where an elaborate workflow would add more overhead than value.

### When Superpowers is appropriate

Consider Superpowers only when the task is sufficiently **large, non-routine, ambiguous, or risky** that a structured workflow is likely to materially improve the result.

Good candidates include:

- Large or non-routine feature additions.
- Significant architectural or design changes.
- Changes spanning multiple components or subsystems.
- Complex bugs whose root cause is unclear.
- Refactors with substantial regression risk.
- Changes to core infrastructure, pipelines, APIs, schemas, or shared interfaces where mistakes could break existing functionality.
- Work where requirements are ambiguous enough that structured brainstorming or planning would materially reduce risk.
- Tasks where the user explicitly requests a Superpowers workflow.

Use the smallest subset of Superpowers necessary for the task. Do not automatically chain brainstorming, planning, TDD, review, and verification workflows.

## TDD policy

**Do NOT use the Superpowers TDD workflow by default.**

The TDD workflow is intentionally reserved for substantial implementation work where its additional tests, validation steps, and token/latency cost are justified by the risk or complexity of the change.

### Use TDD when

Consider the Superpowers TDD workflow for:

- Large or non-routine feature additions.
- Significant behavioral changes.
- Complex business or scientific logic.
- Changes to critical shared code.
- Refactors where preserving existing behavior is difficult or especially important.
- Bugs where a regression test is important to prevent recurrence.
- Work where the user explicitly requests TDD.

### Do NOT use TDD when

Do not invoke the Superpowers TDD workflow for:

- Documentation, README, comments, or prose changes.
- Formatting or lint-only changes.
- Simple configuration changes.
- Small and obvious bug fixes.
- Minor refactors with low regression risk.
- Mechanical code changes.
- Routine maintenance.
- Changes where existing tests already provide adequate coverage and only targeted validation is necessary.
- Any task where generating substantial new test scaffolding would be disproportionate to the size or risk of the change.

For these tasks, perform only the **minimum targeted validation appropriate to the change**.

For example, a small code fix may warrant running an existing relevant test or a focused command. A documentation-only edit generally does not warrant adding tests or invoking a TDD workflow.

### Decision rule

Before invoking any Superpowers workflow, ask:

1. Is this task large, non-routine, ambiguous, or potentially code-breaking?
2. Will the structured workflow materially improve correctness or reduce meaningful risk?
3. Is that benefit proportional to the additional latency, context usage, tests, and validation work?

If not, do the task directly.

When uncertain, prefer the simpler workflow.

**Do not turn a small task into a large task merely to satisfy a Superpowers process.**
<!-- CCBR-SUPERPOWERS-END -->
POLICY

output=$(mktemp "$repo/.AGENTS.md.XXXXXX") || fail 'Cannot create temporary AGENTS.md.'
if [[ -f $agents ]]; then
  if ((has_policy)); then
    awk -v s="$start" -v e="$end" -v policy="$policy" '
      { marker=$0; sub(/\r$/, "", marker) }
      marker == s { while ((getline line < policy) > 0) print line; inside=1; next }
      marker == e { inside=0; next }
      !inside { print }
    ' "$agents" > "$output"
  else
    cat "$agents" > "$output"
    if [[ -s $agents && $(tail -c 1 "$agents" | wc -l) -eq 0 ]]; then printf '\n' >> "$output"; fi
    printf '\n' >> "$output"
    cat "$policy" >> "$output"
  fi
  chmod --reference="$agents" "$output"
else
  cat "$policy" > "$output"
fi

mkdir -p -- "$repo/.github/skills"
created=0
for dir in "${valid[@]}"; do
  target=$repo/.github/skills/${dir##*/}
  if [[ ! -L $target ]]; then
    ln -s -- "$dir" "$target"
    ((created+=1))
  fi
done
if [[ -f $agents ]] && cmp -s "$agents" "$output"; then
  agents_status='already correct'
else
  if [[ -f $agents ]]; then agents_status=updated; else agents_status=created; fi
  mv -f -- "$output" "$agents"
fi
printf 'Skills: %d created, %d already correct, %d invalid/skipped. AGENTS.md: %s. No conflicts.\n' "$created" "$correct" "$invalid" "$agents_status"
