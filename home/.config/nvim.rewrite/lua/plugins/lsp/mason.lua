-- ---------------------------------------------------------------------------
-- mason.nvim: tool binaries (ensure_installed) + mason-lspconfig.nvim for
-- LSP server packages (install + auto-enable).
--
-- mason.setup() must run BEFORE mason-lspconfig.setup(). mason also puts
-- its bin dir on $PATH so conform formatters (stylua, shfmt, prettier, ...)
-- and the LSP server binaries resolve.
--
-- Servers get their base config from nvim-lspconfig's `lsp/<name>.lua`
-- files (auto-loaded from the runtimepath by `vim.lsp.config`);
-- per-language overrides live in plugins/lsp/languages.lua.
-- ---------------------------------------------------------------------------

require("mason").setup({
  ensure_installed = {
    "stylua",
    "shellcheck",
    "shfmt",
    "prettier",
    "eslint",
    "pyright",
    "markdownlint-cli2",
    "markdown-toc",
  },
})

-- Installs the mason packages for the listed servers and auto-enables them
-- (vim.lsp.enable) once the package is installed — for packages already
-- installed at setup time, and on every `package:install:success` event.
-- Note: the ensure_installed install is skipped in headless mode; gate
-- scripts install explicitly via :MasonInstall (which still triggers the
-- install:success auto-enable).
require("mason-lspconfig").setup({
  ensure_installed = {
    "ts_ls",
    "angularls",
    "jsonls",
    "yamlls",
    "taplo",
    "marksman",
    "pyright",
    "eslint",
  },
  automatic_enable = true,
})

Snacks.keymap.set("n", "<leader>cm", "<cmd>Mason<cr>", { desc = "Mason" })