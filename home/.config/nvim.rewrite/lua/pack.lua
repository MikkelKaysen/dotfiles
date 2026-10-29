-- ---------------------------------------------------------------------------
-- Plugin packages — installed and managed by the built-in `vim.pack`
-- (Neovim 0.12+). This replaces lazy.nvim / LazyVim.
-- Called during init.lua sourcing, so `load` defaults to false: every plugin
-- is placed on the runtimepath (require() works) at add-time. Their `plugin/`
-- files are still sourced by Neovim's startup plugin phase (after init.lua
-- runs), so plugin-defined commands exist at VimEnter; our `.setup()` calls
-- in lua/plugins/ therefore run first and take precedence.
--
-- To truly defer a plugin (no rtp, no plugin/ sourcing until a trigger),
-- pass a `load = function(plug_data) ... end` callable in its spec — it is
-- then fully responsible for loading (e.g. `vim.cmd("packadd! " .. name)`).
-- See Phase 7 (lazy-load tuning).
-- No dependency resolution here: every repo is listed explicitly, including
-- shared deps (plenary.nvim, nui.nvim).
--
-- `version` pins a branch (from the old lazy-lock.json) rather than semver,
-- to avoid repos that lack v* tags. The lockfile (nvim-pack-lock.json,
-- generated on first run — commit it) records the exact revisions.
-- ---------------------------------------------------------------------------

local start = vim.uv.hrtime()

local gh = function(repo)
  return "https://github.com/" .. repo .. ".git"
end

local plugins = {
    -- core / shared deps
    { src = gh("folke/snacks.nvim"), version = "main" },
    { src = gh("nvim-lua/plenary.nvim"), version = "master" },
    { src = gh("MunifTanjim/nui.nvim"), version = "main" },

    -- icons + text manipulation (standalone mini.* repos, as in the old install)
    { src = gh("nvim-mini/mini.icons"), version = "main" },
    { src = gh("nvim-mini/mini.pairs"), version = "main" },
    { src = gh("nvim-mini/mini.surround"), version = "main" },
    { src = gh("nvim-mini/mini.animate"), version = "main" },

    -- ui
    { src = gh("catppuccin/nvim"), name = "catppuccin", version = "main" },
    { src = gh("folke/which-key.nvim"), version = "main" },
    { src = gh("folke/noice.nvim"), version = "main" },
    { src = gh("nvim-lualine/lualine.nvim"), version = "master" },
    { src = gh("akinsho/bufferline.nvim"), version = "main" },
    { src = gh("lewis6991/gitsigns.nvim"), version = "main" },
    { src = gh("folke/flash.nvim"), version = "main" },
    { src = gh("MagicDuck/grug-far.nvim"), version = "main" },
    { src = gh("folke/trouble.nvim"), version = "main" },
    { src = gh("folke/todo-comments.nvim"), version = "main" },
    { src = gh("folke/ts-comments.nvim"), version = "main" },
    { src = gh("windwp/nvim-ts-autotag"), version = "main" },
    { src = gh("folke/persistence.nvim"), version = "main" },
    { src = gh("gbprod/yanky.nvim"), version = "main" },

    -- completion
    -- pinned to the exact commit of the previous working install (v1.10.2);
    -- `main` is now v2 with a different setup API + new deps
    { src = gh("saghen/blink.cmp"), version = "78336bc89ee5365633bcf754d93df01678b5c08f" },
    { src = gh("L3MON4D3/LuaSnip"), version = "master" },
    { src = gh("rafamadriz/friendly-snippets"), version = "main" },

    -- treesitter
    { src = gh("nvim-treesitter/nvim-treesitter"), version = "main" },
    { src = gh("nvim-treesitter/nvim-treesitter-textobjects"), version = "main" },

    -- lsp
    { src = gh("neovim/nvim-lspconfig"), version = "master" },
    
    { src = gh("mason-org/mason.nvim"), version = "main" },
    { src = gh("mason-org/mason-lspconfig.nvim"), version = "main" },
    { src = gh("stevearc/conform.nvim"), version = "master" },
    { src = gh("mfussenegger/nvim-lint"), version = "master" },
    { src = gh("stevearc/overseer.nvim"), version = "master" },
    { src = gh("b0o/SchemaStore.nvim"), version = "main" },

    -- markdown
    { src = gh("MeanderingProgrammer/render-markdown.nvim"), version = "main" },
    { src = gh("iamcco/markdown-preview.nvim"), version = "master" },

    -- git
    { src = gh("NeogitOrg/neogit"), version = "master" },
    { src = gh("sindrets/diffview.nvim"), version = "main" },
    { src = gh("polarmutex/git-worktree.nvim"), version = "main" },
  }

vim.pack.add(
  plugins,
  {
    -- auto-install on first run (like lazy.nvim used to) instead of a prompt
    confirm = false,
  }
)

return { plugins = plugins, start = start }