---
description: Delete a plan file after implementation is complete.
subtask: false
---

Delete the specified plan file from `~/.opencode/plan/`.

User arguments: $ARGUMENTS

Runtime data:
- Plan directory listing: !`ls -1 ~/.opencode/plan/ 2>/dev/null || echo "(empty or missing)"`

Procedure:
1. If `$ARGUMENTS` is empty, show the available plans and stop.
2. Take the first argument as the plan name (append `.md` if the argument lacks one).
3. Resolve the target as `~/.opencode/plan/<name>.md`.
4. If the target does not exist, say `Plan not found.` and list the available plans, then stop.
5. Delete the target file with `rm ~/.opencode/plan/<name>.md`.
   - If direct shell execution is denied by permissions, delegate the exact `rm`
     command to @tool-runner instead.
6. Confirm with `Deleted: <filename>`.

Do not delete or modify any other files.
