---
description: Switch the session's effective working directory to a git worktree or path.
subtask: false
---

Switch the effective working directory for this session.

User arguments: $ARGUMENTS

Runtime data:
- Current directory: !`pwd`
- Git worktree list (porcelain):
!`git worktree list --porcelain 2>/dev/null || true`
- Inside git repo? !`git rev-parse --is-inside-work-tree 2>/dev/null || true`
- Bare repo? !`git rev-parse --is-bare-repository 2>/dev/null || true`

Target resolution:
1. If `$ARGUMENTS` is empty, return a concise error: `Usage: /move-cwd <branch-or-path>` and stop.
2. Take the full `$ARGUMENTS` as the target selector.
3. If the selector is an existing directory path (absolute, or relative to the current directory), use it directly as the target.
4. Otherwise, resolve it against the worktree list using the same matching rules as `/worktree-context`:
   - Compare case-insensitively; treat `/` and `\` as equivalent separators.
   - Match in priority order: worktree path (exact → prefix → substring), branch short name (strip `refs/heads/`, exact → substring), path basename (exact → substring).
   - Exactly one match → use that worktree path.
   - Multiple matches → return an ambiguity error listing candidates and stop.
   - No match → return a not-found error with quick suggestions and stop.
5. Validate the resolved target:
   - It must exist as a directory. If not, return a concise error and stop.
   - If it is not inside a git worktree, warn briefly but proceed.

On success, output the following:

## Moved

- **Path**: <resolved-path>
- **Branch**: <branch name from porcelain output if determinable, else `unknown`>
- **HEAD**: <short commit hash from porcelain output if determinable, else `unknown`>

Then emit this instruction (this command runs inline, so it persists for subsequent turns):

The working directory is now "<resolved-path>". Use `workdir=<resolved-path>` for all bash commands and reference all file paths as absolute paths under "<resolved-path>" from now on.

Output format:
- Output Markdown only.
- Keep it short and operational.
- Do not output anything after the instruction line.
