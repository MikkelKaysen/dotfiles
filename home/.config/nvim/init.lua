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

-- mason first: its setup() registers the registry sources that
-- util/treesitter.lua needs to install the tree-sitter CLI, and puts the
-- mason bin dir on $PATH.
require("plugins.lsp.mason")

require("plugins.treesitter")
require("plugins.orgmode")
require("plugins.completion")

-- lsp: core → per-language
require("plugins.lsp.lsp")
require("plugins.lsp.languages")

-- formatting / linting / tasks
require("plugins.formatting")