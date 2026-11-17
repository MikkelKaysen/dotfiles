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
  callback = function(ev)
    vim.opt_local.conceallevel = 2
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.spell = true

    local wk = require("which-key")
    wk.add(
      {
        { "<localleader>t", group = "todo" },
        { "<localleader>l", group = "list" },
        { "<localleader>i", group = "insert" },
      },
      { buffer = ev.buf }
    )

    local map = function(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = ev.buf, desc = desc, silent = true })
    end

    map("n", "<LocalLeader>tu", "<Plug>(neorg.qol.todo-items.todo.task-undone)", "[neorg] Mark as Undone")
    map("n", "<LocalLeader>tp", "<Plug>(neorg.qol.todo-items.todo.task-pending)", "[neorg] Mark as Pending")
    map("n", "<LocalLeader>td", "<Plug>(neorg.qol.todo-items.todo.task-done)", "[neorg] Mark as Done")
    map("n", "<LocalLeader>th", "<Plug>(neorg.qol.todo-items.todo.task-on-hold)", "[neorg] Mark as On Hold")
    map("n", "<LocalLeader>tc", "<Plug>(neorg.qol.todo-items.todo.task-cancelled)", "[neorg] Mark as Cancelled")
    map("n", "<LocalLeader>tr", "<Plug>(neorg.qol.todo-items.todo.task-recurring)", "[neorg] Mark as Recurring")
    map("n", "<LocalLeader>ti", "<Plug>(neorg.qol.todo-items.todo.task-important)", "[neorg] Mark as Important")
    map("n", "<LocalLeader>ta", "<Plug>(neorg.qol.todo-items.todo.task-ambiguous)", "[neorg] Mark as Ambiguous")
    map("n", "<C-Space>", "<Plug>(neorg.qol.todo-items.todo.task-cycle)", "[neorg] Cycle Task")
    map("n", ">.", "<Plug>(neorg.promo.promote)", "[neorg] Promote Object (Non-Recursively)")
    map("n", "<,", "<Plug>(neorg.promo.demote)", "[neorg] Demote Object (Non-Recursively)")
    map("n", ">>", "<Plug>(neorg.promo.promote.nested)", "[neorg] Promote Object (Recursively)")
    map("n", "<<", "<Plug>(neorg.promo.demote.nested)", "[neorg] Demote Object (Recursively)")
    map("n", "<LocalLeader>lt", "<Plug>(neorg.pivot.list.toggle)", "[neorg] Toggle (Un)ordered List")
    map("n", "<LocalLeader>li", "<Plug>(neorg.pivot.list.invert)", "[neorg] Invert (Un)ordered List")
    map("n", "<LocalLeader>id", "<Plug>(neorg.tempus.insert-date)", "[neorg] Insert Date")
    map("n", "<LocalLeader>nn", "<Plug>(neorg.dirman.new-note)", "[neorg] Create New Note")
    map("n", "<LocalLeader>cm", "<Plug>(neorg.looking-glass.magnify-code-block)", "[neorg] Magnify Code Block")
    map("n", "<LocalLeader>?", function()
      require("which-key").show({ keys = "<localleader>", loop = true })
    end, "[neorg] Browse keymaps")
    map("i", "<C-t>", "<Plug>(neorg.promo.promote)", "[neorg] Promote Object (Recursively)")
    map("i", "<C-d>", "<Plug>(neorg.promo.demote)", "[neorg] Demote Object (Recursively)")
    map("v", ">", "<Plug>(neorg.promo.promote.range)", "[neorg] Promote Objects in Range")
    map("v", "<", "<Plug>(neorg.promo.demote.range)", "[neorg] Demote Objects in Range")
  end,
})

-- Neorg v9.6.4 indentexpr calls the legacy vim.fn["nvim_treesitter#indent"]() for
-- injected code blocks, which nvim-treesitter main does not provide. Delegate those
-- lines to the current nvim-treesitter indent; keep Neorg's indent for norg lines.

-- Upstream core.esupports.indent (injected branch) adds the enclosing tag column only while
-- every content row above the line is blank (first content statement). Once real content
-- exists, nvim-treesitter's indent already includes the anchor, so nothing is added.
-- Returns the tag column for that initial-blank case, nil otherwise.
local function initial_blank_tag_column(buf, line)
  local okm, tsint = pcall(function()
    return require("neorg").modules.get_module("core.integrations.treesitter")
  end)
  if not (okm and tsint) then
    return nil
  end
  local ok, node = pcall(tsint.get_first_node_on_line, buf, line)
  while ok and node and node:type() ~= "ranged_verbatim_tag_content" do
    node = node:parent()
  end
  if not (ok and node) then
    return nil
  end
  local start = node:range()
  for row = start, line - 1 do
    local text = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    if not text:match("^%s*$") then
      return nil
    end
  end
  local tag = node:parent()
  if not tag then
    return nil
  end
  local _, col = tag:start()
  return col
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
      local base = initial_blank_tag_column(buf, line)
      if base then
        return raw + base
      end
      return raw
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
