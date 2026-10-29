-- ---------------------------------------------------------------------------
-- Entry point (Phase 5: + LSP/mason + formatting).
-- 1. pack     — install/refresh plugins (vim.pack; rtp only, nothing loaded)
-- 2. config   — options, keymaps, autocmds
-- 3. plugins  — eager UI modules (snacks first: everything uses `Snacks`)
-- ---------------------------------------------------------------------------

require("pack")

require("config.options")
require("config.keymaps")
require("config.autocmds")

-- snacks first: everything else uses `Snacks`
require("plugins.picker")

require("plugins.ui.catppuccin")
require("plugins.ui.which-key")
require("plugins.ui.lualine")
require("plugins.ui.bufferline")
require("plugins.ui.noice")
require("plugins.ui.gitsigns")
require("plugins.ui.flash")
require("plugins.ui.trouble")
require("plugins.ui.misc")

-- git: neogit + git worktrees (wrappers for the <leader>g maps in config/keymaps.lua)
require("plugins.git")

require("plugins.treesitter")
require("plugins.completion")

-- lsp: mason (tool binaries + server packages) → core → per-language
require("plugins.lsp.mason")
require("plugins.lsp.lsp")
require("plugins.lsp.languages")

-- formatting / linting / tasks
require("plugins.formatting")