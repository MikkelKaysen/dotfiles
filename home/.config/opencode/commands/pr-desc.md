---
description: Generate an Azure DevOps-ready PR description from current branch changes and commits.
agent: general
---

Generate a pull request description in Markdown for Azure DevOps.

User arguments: $ARGUMENTS

Runtime data:
- Current directory: !`pwd`
- Git worktree list (porcelain):
!`git worktree list --porcelain 2>/dev/null || true`

Target directory resolution:
- Parse `worktree=<value>` (alias `path=<value>`) from `$ARGUMENTS`.
- If provided, resolve `<value>` against the worktree list above:
  - Compare case-insensitively; treat `/` and `\` as equivalent separators.
  - Match in this priority order: worktree path (exact → prefix → substring), branch short name (strip `refs/heads/`, exact → substring), path basename (exact → substring).
  - Exactly one match → use that worktree path as the target directory.
  - Multiple matches → return an ambiguity error listing candidates and stop.
  - No match → return a not-found error with quick suggestions and stop.
  - Resolved path missing or not a git worktree → return a concise path error and stop.
- If no `worktree=`/`path=` argument is provided, use the current directory as the target.
- If the effective target is a bare repository and no worktree argument was provided, return a concise error telling the user to pass `worktree=<branch-or-path>`, then stop.
- Strip `worktree=...` and `path=...` from `$ARGUMENTS` before further parsing; `<target>` below refers to the resolved directory.

Requirements:
- Parse `tone=<value>` from the remaining `$ARGUMENTS` (after stripping `worktree=`/`path=`).
- Parse `style=<value>` from the remaining `$ARGUMENTS`.
- Supported tones: `funny`, `formal`, `dank`, `professional`, `concise`, `technical`, `executive`, `neutral`, `playful`, `retro`.
- Default tone is `funny` when `tone` is missing or invalid.
- Supported styles: `default`, `trump`, `obama`, `csi-miami`.
- Accept style aliases: `csi_miami`, `csi miami`, `csi` -> `csi-miami`.
- Default style is `default` when `style` is missing or invalid.
- Treat any remaining argument text (after removing `tone=...` and `style=...`) as extra context to incorporate.
- Tone behavior guidance:
  - `professional`: clear, polished, and stakeholder-friendly.
  - `concise`: shortest useful wording, minimal fluff.
  - `technical`: implementation detail and engineering rationale emphasized.
  - `executive`: outcome-focused, impact-oriented, low implementation detail.
  - `neutral`: straightforward and matter-of-fact.
  - `playful`: light and friendly without reducing clarity.
  - `retro`: playful old-school internet/dev flavor, still readable.
- Style behavior guidance:
  - `default`: no persona imitation, standard voice matching the chosen tone.
  - `trump`: short punchy lines, emphatic phrasing, still factual and professional-safe.
  - `obama`: calm, structured, and explanatory cadence, still concise.
  - `csi-miami`: dramatic one-liners and investigation flavor, but keep technical accuracy.
- Safety and professionalism constraints for style:
  - Never fabricate facts, metrics, incidents, or test results.
  - Avoid insults, political persuasion, or content that could be construed as harassment.
  - Keep output suitable for real engineering workflows regardless of selected style.

Git analysis requirements:
1. Determine the base branch in this order:
   - `main` if it exists
   - otherwise `master` if it exists
   - if neither exists, state this briefly in the output and continue with best-effort from working tree changes.
2. Identify commits on current branch not present in base using `<base>..HEAD`.
3. Use non-merge commit messages to inform the narrative.
4. Include a `## Commits Included` section listing those commit messages (newest first).
5. All branch and commit detection must run in the effective target directory (`<target>`, resolved per the Target directory resolution above).

Output requirements:
- Output Markdown only, copy-paste ready for Azure DevOps PR description.
- Wrap the entire generated PR description in a single fenced Markdown code block using ```md.
- No HTML.
- No placeholder text.
- Keep it concise and specific to actual changes.
- Reflect requested tone, but keep it useful for a professional engineering workflow.
- Add a short PR title at the very top as a Markdown H1 (`# ...`).
- Include relevant emojis in the title and section headers, but keep usage light and readable.

Generate these sections in this order:
## 🧾 Summary
## 🔧 What Changed
## 🎯 Why
## ✅ Testing
## ⚠️ Risks and Rollback
## 🧱 Commits Included
## 🔗 Work Items

Work item rules:
- Detect and list work items (for example `AB#1234`) from branch name, commit messages, and extra context.
- If no work items are found, omit the `## 🔗 Work Items` section entirely.

Style rules:
- Use bullet points where appropriate.
- Keep bullets short and concrete.
- Avoid hype or vague filler.
- If information is unavailable, state that briefly and move on.

Operational notes:
- Prefer these command patterns so analysis is always scoped correctly:
  - `git -C <target> rev-parse --is-bare-repository`
  - `git -C <target> rev-parse --verify --quiet refs/heads/main`
  - `git -C <target> rev-parse --verify --quiet refs/heads/master`
  - `git -C <target> branch --show-current`
  - `git -C <target> log --no-merges --pretty=format:%s <base>..HEAD`
