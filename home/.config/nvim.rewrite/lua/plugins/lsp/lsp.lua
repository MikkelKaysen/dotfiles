-- ---------------------------------------------------------------------------
-- LSP core: diagnostics config, inlay hints, folds, shared capabilities and
-- the LSP keymaps (ported from LazyVim's plugins/lsp/init.lua).
--
-- Per-server configs: plugins/lsp/languages.lua
-- Server install + enable: plugins/lsp/mason.lua (mason-lspconfig)
-- ---------------------------------------------------------------------------

local icons = require("util.icons").icons
local lsp = require("util.lsp")

-- Diagnostics
vim.diagnostic.config({
  underline = true,
  update_in_insert = false,
  virtual_text = {
    spacing = 4,
    source = "if_many",
    prefix = "●",
  },
  severity_sort = true,
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = icons.diagnostics.Error,
      [vim.diagnostic.severity.WARN] = icons.diagnostics.Warn,
      [vim.diagnostic.severity.HINT] = icons.diagnostics.Hint,
      [vim.diagnostic.severity.INFO] = icons.diagnostics.Info,
    },
  },
})

-- Inlay hints: enable when a client provides them (skip vue — volar does its own)
Snacks.util.lsp.on({ method = "textDocument/inlayHint" }, function(buffer)
  if
    vim.api.nvim_buf_is_valid(buffer)
    and vim.bo[buffer].buftype == ""
    and not vim.tbl_contains({ "vue" }, vim.bo[buffer].filetype)
  then
    vim.lsp.inlay_hint.enable(true, { bufnr = buffer })
  end
end)

-- Folds: use LSP folding ranges when provided
Snacks.util.lsp.on({ method = "textDocument/foldingRange" }, function()
  if vim.o.foldmethod == "manual" or vim.o.foldmethod == "indent" then
    vim.opt.foldmethod = "expr"
    vim.opt.foldexpr = "v:lua.vim.lsp.foldexpr()"
  end
end)

-- Capabilities for all servers
vim.lsp.config("*", {
  capabilities = {
    workspace = {
      fileOperations = {
        didRename = true,
        willRename = true,
      },
    },
  },
})

-- LSP keymaps (capability-filtered via util.lsp.set)
lsp.set({}, {
  -- Navigation (picker-based where a list of results can occur)
  { "gd", function() Snacks.picker.lsp_definitions() end, desc = "Goto Definition", has = "definition" },
  { "gr", function() Snacks.picker.lsp_references() end, nowait = true, desc = "References" },
  { "gI", function() Snacks.picker.lsp_implementations() end, desc = "Goto Implementation" },
  { "gy", function() Snacks.picker.lsp_type_definitions() end, desc = "Goto T[y]pe Definition" },
  { "gD", vim.lsp.buf.declaration, desc = "Goto Declaration" },
  -- Info
  { "K", function() return vim.lsp.buf.hover() end, desc = "Hover" },
  { "gK", function() return vim.lsp.buf.signature_help() end, desc = "Signature Help", has = "signatureHelp" },
  { "<c-k>", function() return vim.lsp.buf.signature_help() end, mode = "i", desc = "Signature Help", has = "signatureHelp" },
  -- Rename / Refactor
  { "<leader>ca", vim.lsp.buf.code_action, desc = "Code Action", mode = { "n", "x" }, has = "codeAction" },
  { "<leader>cc", vim.lsp.codelens.run, desc = "Run Codelens", mode = { "n", "x" }, has = "codeLens" },
  { "<leader>cC", vim.lsp.codelens.refresh, desc = "Refresh & Display Codelens", mode = "n", has = "codeLens" },
  { "<leader>cR", function() Snacks.rename.rename_file() end, desc = "Rename File", has = { "workspace/didRenameFiles", "workspace/willRenameFiles" } },
  { "<leader>cr", vim.lsp.buf.rename, desc = "Rename", has = "rename" },
  { "<leader>cA", lsp.action.source, desc = "Source Action", has = "codeAction" },
  { "<leader>co", lsp.action["source.organizeImports"], desc = "Organize Imports", has = "codeAction" },
  -- Symbols / Calls
  { "<leader>ss", function() Snacks.picker.lsp_symbols({ filter = require("util.icons").kind_filter }) end, desc = "LSP Symbols", has = "documentSymbol" },
  { "<leader>sS", function() Snacks.picker.lsp_workspace_symbols({ filter = require("util.icons").kind_filter }) end, desc = "LSP Workspace Symbols", has = "workspace/symbols" },
  { "gai", function() Snacks.picker.lsp_incoming_calls() end, desc = "C[a]lls Incoming", has = "callHierarchy/incomingCalls" },
  { "gao", function() Snacks.picker.lsp_outgoing_calls() end, desc = "C[a]lls Outgoing", has = "callHierarchy/outgoingCalls" },
  { "<leader>cl", function() Snacks.picker.lsp_config() end, desc = "Lsp Info" },
  -- Reference jumping (snacks.words)
  { "]]", function() Snacks.words.jump(vim.v.count1) end, desc = "Next Reference", has = "documentHighlight", enabled = function() return Snacks.words.is_enabled() end },
  { "[[", function() Snacks.words.jump(-vim.v.count1) end, desc = "Prev Reference", has = "documentHighlight", enabled = function() return Snacks.words.is_enabled() end },
  { "<a-n>", function() Snacks.words.jump(vim.v.count1, true) end, desc = "Next Reference", has = "documentHighlight", enabled = function() return Snacks.words.is_enabled() end },
  { "<a-p>", function() Snacks.words.jump(-vim.v.count1, true) end, desc = "Prev Reference", has = "documentHighlight", enabled = function() return Snacks.words.is_enabled() end },
})

-- Register the LSP formatter (fallback behind conform's primary)
require("util.format").register(lsp.formatter())