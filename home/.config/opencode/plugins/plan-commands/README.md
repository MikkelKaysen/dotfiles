# opencode-plugin-plan-commands

Local OpenCode TUI plugin that provides commands for working with plan files
in `~/.opencode/plan`.

## Commands

| Command | Slash | Description |
|---|---|---|
| Attach a plan | `/plan:existing` | Pick a plan and attach it to the current session (or create a new session) |
| Delete a plan | `/plan:remove` | Pick a plan and delete its file after confirmation |
| Implement a plan | `/plan:implement` | Pick a plan and start implementing it (switches agent to `build`) |

## How it works

- Plans are `.md` files read from `~/.opencode/plan`.
- The picker sorts them newest-first by modification time.
- The display title comes from the first `# ` heading in each file.
- Each command is a slash command, palette entry, and keymap binding.

## Installation

This is a **local plugin** auto-discovered from `~/.config/opencode/plugins/`.
No config entry is needed — just place the directory under `~/.config/opencode/plugins/`
and the OpenCode service will pick it up automatically (config is file-watched).

## Running tests

```bash
npm install
node --test plan-picker.test.ts
```
