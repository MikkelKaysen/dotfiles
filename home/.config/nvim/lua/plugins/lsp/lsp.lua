-- ---------------------------------------------------------------------------
-- LSP core: diagnostics config, inlay hints, folds, shared capabilities and
-- the LSP keymaps (ported from LazyVim's plugins/lsp/init.lua).
--
-- Keymaps: Neovim 0.12 provides native LSP defaults:
-- grn (rename), gra (code action, n/x), gri (implementation), grt (type
-- definition), grx (codelens), gO (document symbols), and insert-mode <C-s>
-- (signature help). `grr` is overridden below with a buffer-local,
-- capability-filtered quickfix view; the remaining native defaults stay as-is.
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

-- Custom LSP keymaps (capability-filtered via util.lsp.set)
lsp.set({}, {
  -- Navigation
  { "gd", vim.lsp.buf.definition, desc = "Goto Definition", has = "definition" },
  { "gD", vim.lsp.buf.declaration, desc = "Goto Declaration" },
  -- Info
  { "gK", function() return vim.lsp.buf.signature_help() end, desc = "Signature Help", has = "signatureHelp" },
  -- Refactor / Code actions
  { "<leader>cC", vim.lsp.codelens.refresh, desc = "Refresh & Display Codelens", mode = "n", has = "codeLens" },
  { "<leader>cR", function() Snacks.rename.rename_file() end, desc = "Rename File", has = { "workspace/didRenameFiles", "workspace/willRenameFiles" } },
  { "<leader>cA", lsp.action.source, desc = "Source Action", has = "codeAction" },
  { "<leader>co", lsp.action["source.organizeImports"], desc = "Organize Imports", has = "codeAction" },
  -- Symbols / Calls
  { "<leader>sS", function() Snacks.picker.lsp_workspace_symbols({ filter = require("util.icons").kind_filter }) end, desc = "LSP Workspace Symbols", has = "workspace/symbols" },
  { "gai", function() Snacks.picker.lsp_incoming_calls() end, desc = "C[a]lls Incoming", has = "callHierarchy/incomingCalls" },
  { "gao", function() Snacks.picker.lsp_outgoing_calls() end, desc = "C[a]lls Outgoing", has = "callHierarchy/outgoingCalls" },
  { "<leader>cl", function() Snacks.picker.lsp_config() end, desc = "Lsp Info" },
  -- Reference jumping (snacks.words)
  { "]]", function() Snacks.words.jump(vim.v.count1) end, desc = "Next Reference", has = "documentHighlight", enabled = function() return Snacks.words.is_enabled() end },
  { "[[", function() Snacks.words.jump(-vim.v.count1) end, desc = "Prev Reference", has = "documentHighlight", enabled = function() return Snacks.words.is_enabled() end },
  { "<a-n>", function() Snacks.words.jump(vim.v.count1, true) end, desc = "Next Reference", has = "documentHighlight", enabled = function() return Snacks.words.is_enabled() end },
  { "<a-p>", function() Snacks.words.jump(-vim.v.count1, true) end, desc = "Prev Reference", has = "documentHighlight", enabled = function() return Snacks.words.is_enabled() end },
  {
    "grr",
    function()
      vim.lsp.buf.references(nil, {
        on_list = function(what)
          if not what or not what.items then
            return
          end
          local items = {}
          for _, item in ipairs(what.items) do
            items[#items + 1] = {
              filename = item.filename,
              lnum = item.lnum,
              col = item.col,
              end_lnum = item.end_lnum,
              end_col = item.end_col,
            }
          end
          what.items = vim.list.unique(items)
          vim.fn.setqflist({}, " ", what)
          vim.cmd("botright copen")
        end,
      })
    end,
    desc = "References",
    has = "references",
    mode = "n",
    buffer = 0,
  },
})

-- Register the LSP formatter (fallback behind conform's primary)
require("util.format").register(lsp.formatter())