-- ---------------------------------------------------------------------------
-- Neorg notes (personal + work workspaces) in ~/code/personal/notes.neorg.
-- Requires the norg parser (built by util/norg_parser.lua, :NorgParserBuild) and the
-- norg_meta parser (registered in plugins/treesitter.lua).
-- Git sync lives in util/notes_sync.lua (:NotesSync, automatic on note save).
-- Completion: none from neorg; blink.cmp is unchanged.
-- ---------------------------------------------------------------------------

local NOTES_ROOT = vim.fs.normalize(vim.fn.expand("~/code/personal/notes.neorg"))
local WORKSPACES = {
  personal = NOTES_ROOT .. "/personal",
  work = NOTES_ROOT .. "/work",
}
local DEFAULT_WORKSPACE = "personal"

-- Current workspace name, falling back to personal when dirman reports anything unknown.
local function current_workspace()
  local ok, dirman = pcall(function()
    return require("neorg").modules.get_module("core.dirman")
  end)
  if ok and dirman then
    local cur = dirman.get_current_workspace()
    if cur and WORKSPACES[cur[1]] then
      return cur[1]
    end
  end
  return DEFAULT_WORKSPACE
end

local function dirman()
  return require("neorg").modules.get_module("core.dirman")
end

require("neorg").setup({
  load = {
    ["core.defaults"] = {},
    ["core.concealer"] = {},
    -- Neorg's default keybinds map a global gO (TOC) that shadows native LSP
    -- document symbols. Disable them; notes keys are defined explicitly below.
    ["core.keybinds"] = {
      config = { default_keybinds = false },
    },
    ["core.dirman"] = {
      config = {
        workspaces = WORKSPACES,
        default_workspace = DEFAULT_WORKSPACE,
        index = "index.norg",
        open_last_workspace = false, -- no startup index takeover
        use_popup = true,
      },
    },
    ["core.journal"] = {
      config = {
        workspace = nil, -- current workspace
        journal_folder = "journal",
        strategy = "flat", -- YYYY-MM-DD.norg
      },
    },
    ["core.summary"] = {},
  },
})

require("util.notes_sync").setup({
  root = NOTES_ROOT,
  expected_remote = "git@github.com:MikkelKaysen/notes.neorg.git",
})

-- norg buffers: concealment for markup, soft wrap and spelling (buffer-local options)
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("neorg_buffer_opts", { clear = true }),
  pattern = "norg",
  callback = function()
    vim.opt_local.conceallevel = 2
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.spell = true
  end,
})

-- Neorg v9.6.4 indentexpr calls the legacy vim.fn["nvim_treesitter#indent"]() for
-- injected code blocks, which nvim-treesitter main does not provide. Delegate those
-- lines to the current nvim-treesitter indent; keep Neorg's indent for norg lines.

-- Column of the enclosing ranged tag (e.g. the "@code" line) for a line inside injected
-- code. The raw nvim-treesitter indent is relative to column 0, so the tag column is
-- added for every injected line (upstream only does this for blank leading lines).
local function enclosing_tag_column(buf, line, text)
  local ok, node = pcall(vim.treesitter.get_node, {
    bufnr = buf,
    pos = { line, #text },
    ignore_injections = true,
  })
  while ok and node do
    if node:type() == "ranged_verbatim_tag" then
      local _, col = node:start()
      return col
    end
    node = node:parent()
  end
  return 0
end

local M = {}
M.indentexpr = function()
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.v.lnum - 1
  local text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or ""
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "norg")
  if ok and parser then
    parser:parse(true) -- injections must exist before the range lookup
    local lang = parser:language_for_range({ line, #text, line, #text })
    if lang and lang:lang() ~= "norg" then
      local raw = require("nvim-treesitter").indentexpr()
      if type(raw) ~= "number" or raw < 0 then
        return raw -- -1 keeps Neovim's own indent
      end
      return raw + enclosing_tag_column(buf, line, text)
    end
  end
  return require("neorg").modules.get_module("core.esupports.indent").indentexpr(buf, line)
end

-- FileType matches the filetype "norg"; BufEnter matches the file pattern. Both are
-- registered after neorg setup, so this wrapper runs after Neorg's own BufEnter indentexpr.
vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
  group = vim.api.nvim_create_augroup("neorg_indent_wrapper", { clear = true }),
  pattern = { "norg", "*.norg" },
  callback = function(ev)
    -- pattern "*.norg" can match a non-norg buffer (e.g. a file literally named "norg"); only norg buffers get the wrapper
    if vim.bo[ev.buf].filetype ~= "norg" then
      return
    end
    vim.bo[ev.buf].indentexpr = "v:lua.require'plugins.neorg'.indentexpr()"
  end,
})

require("which-key").add({ { "<leader>j", group = "neorg" } }, { notify = false })

local function map(lhs, rhs, desc)
  vim.keymap.set("n", "<leader>j" .. lhs, rhs, { desc = desc, silent = true })
end

map("p", function() vim.cmd("Neorg workspace personal") end, "Workspace: personal")
map("w", function() vim.cmd("Neorg workspace work") end, "Workspace: work")
map("i", function() vim.cmd("Neorg index") end, "Workspace index")
map("j", function() vim.cmd("Neorg journal today") end, "Journal today")
map("n", function() dirman().new_note() end, "New note (current workspace)")
map("r", function() vim.cmd("Neorg return") end, "Return from neorg")
map("s", function() vim.cmd("NotesSync") end, "Sync notes repo")
map("f", function()
  Snacks.picker.files({ cwd = WORKSPACES[current_workspace()] })
end, "Find notes (current workspace)")
map("g", function()
  Snacks.picker.grep({ dirs = { WORKSPACES.personal, WORKSPACES.work } })
end, "Grep notes (personal + work)")

return M
