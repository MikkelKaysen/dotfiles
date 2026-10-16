---
description: Set, show, or clear the active git worktree context and switch the working directory.
subtask: false
---

Manage git worktree context for this conversation.

User arguments: $ARGUMENTS

Runtime data:
- Current directory: !`pwd`
- Git worktree list (porcelain):
!`git worktree list --porcelain 2>/dev/null || true`
- Current branch (if any): !`git branch --show-current 2>/dev/null || true`
- Git root (if any): !`git rev-parse --show-toplevel 2>/dev/null || true`
- Inside git repo? !`git rev-parse --is-inside-work-tree 2>/dev/null || true`
- Bare repo? !`git rev-parse --is-bare-repository 2>/dev/null || true`

Argument parsing rules:
1. Supported flags are `action=show|set|clear`, `path=<worktree-path>`, `branch=<branch-name>`, `name=<worktree-dir-basename>`.
2. If no arguments are provided, default to `action=show`.
3. If arguments are provided and any are unflagged tokens, interpret the first unflagged token as `branch=<token>` and default `action=set` unless `action=` was explicitly provided.
4. If `action` is omitted and at least one flagged argument is provided, default to `action=set`.
5. Matching should be forgiving and not require exact input:
   - Compare case-insensitively.
   - Treat `/` and `\\` as equivalent separators.
   - Support partial/substring matches for `branch` and `name`.
   - Support prefix or substring matches for `path` against canonical worktree paths.

Behavior:
- If neither inside a git repo nor in a bare repo, return a concise error and stop.
- For `action=set`:
  - Resolve the target worktree from `path`, else `branch`, else `name`.
  - Resolution priority for each selector is: exact match first, then prefix match, then substring match.
  - If exactly one candidate remains after applying the above, select it.
  - If multiple matches exist, return an ambiguity error and list candidates.
  - If no match exists, return a not-found error with quick suggestions.
  - On resolution success, perform the working directory switch inline:
    - Emit this instruction (it persists for subsequent commands since this command runs inline):
      The working directory is now "<resolved-worktree-path>". Use `workdir="<resolved-worktree-path>"` for all bash commands and reference all file paths as absolute paths under "<resolved-worktree-path>" from now on.
    - Output the `## Active Worktree Context` section with Path, Branch, and HEAD bullets.
- For `action=show`:
  - Show the current active worktree context if already set in this conversation.
  - If none is set yet, show `No active worktree context is set.` and list available worktrees.
  - If an active context is set and current directory differs from that path, show a concise drift warning and suggest `/move-cwd <active-worktree-path>`.
  - If available worktrees cannot be determined, suggest a set command.
- For `action=clear`:
  - Clear the active worktree context and confirm it is unset.
  - Do not auto-move on clear.

Execution contract after `action=set`:
- State that all subsequent work in this conversation should target the active worktree path.
- State that shell calls should use that path as `workdir` and file operations should reference paths under that worktree.

Output format requirements:
- Output Markdown only.
- Keep it short and operational.
- Use this section heading exactly when showing a set context: `## Active Worktree Context`.
- Under that heading include bullets for `Path`, `Branch`, and `HEAD`.
