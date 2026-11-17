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
        { "<localleader>m", group = "toggle" },
      },
      { buffer = ev.buf }
    )

    local map = function(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = ev.buf, desc = desc, silent = true })
    end

    local function trim(s)
      return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function clamp_depth(depth)
      local n = tonumber(depth) or 1
      return math.max(1, math.min(6, n))
    end

    local function parse_norg_line(line)
      local indent, rest = (line or ""):match("^(%s*)(.*)$")
      local parsed = { indent = indent or "", kind = "plain", depth = 1, body = "" }
      if rest == "" then
        return parsed
      end

      local stars = rest:match("^(%*+)")
      if stars and rest:sub(#stars + 1):match("^%s") then
        parsed.kind = "heading"
        parsed.depth = clamp_depth(#stars)
        parsed.body = trim(rest:sub(#stars + 1))
        return parsed
      end

      local dashes, status, body = rest:match("^(-+)%s*(%([^)]*%))?%s*(.*)$")
      if dashes then
        if status then
          parsed.kind = "todo"
          parsed.depth = clamp_depth(#dashes)
          parsed.body = trim(body)
          return parsed
        end
        parsed.kind = "unordered"
        parsed.depth = clamp_depth(#dashes)
        parsed.body = trim(body)
        return parsed
      end

      local tildes = rest:match("^(~+)")
      if tildes then
        parsed.kind = "ordered"
        parsed.depth = clamp_depth(#tildes)
        parsed.body = trim(rest:sub(#tildes + 1))
        return parsed
      end

      parsed.body = trim(rest)
      return parsed
    end

    local function nearest_heading_level()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      for line = row, 1, -1 do
        local text = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1] or ""
        local stars = text:match("^%s*(%*+)")
        if stars then
          return clamp_depth(#stars)
        end
      end
      return 1
    end

    local function current_list_depth()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local text = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
      local parsed = parse_norg_line(text)
      if parsed.kind == "ordered" or parsed.kind == "unordered" or parsed.kind == "todo" then
        return parsed.depth
      end
      return 1
    end

    local function insert_marker_line(kind)
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
      local indent = line:match("^(%s*)") or ""
      local depth = kind == "heading" and nearest_heading_level() or current_list_depth()
      local prefix
      if kind == "heading" then
        prefix = string.rep("*", clamp_depth(depth)) .. " "
      elseif kind == "unordered" then
        prefix = string.rep("-", clamp_depth(depth)) .. " "
      elseif kind == "ordered" then
        prefix = string.rep("~", clamp_depth(depth)) .. " "
      else
        prefix = string.rep("-", clamp_depth(depth)) .. " ( ) "
      end
      local new_line = indent .. prefix
      vim.api.nvim_buf_set_lines(0, row, row, false, { new_line })
      vim.api.nvim_win_set_cursor(0, { row + 1, #new_line })
      vim.cmd("startinsert")
    end

    local function toggle_norg_line(line, target)
      local parsed = parse_norg_line(line)
      if target == "plain" or parsed.kind == target then
        return parsed.indent .. parsed.body
      end

      local depth = parsed.kind == "plain" and 1 or clamp_depth(parsed.depth)
      local prefix
      if target == "heading" then
        prefix = string.rep("*", depth) .. " "
      elseif target == "unordered" then
        prefix = string.rep("-", depth) .. " "
      elseif target == "ordered" then
        prefix = string.rep("~", depth) .. " "
      elseif target == "todo" then
        prefix = string.rep("-", depth) .. " ( ) "
      else
        return parsed.indent .. parsed.body
      end

      return parsed.indent .. prefix .. (parsed.body ~= "" and parsed.body or "")
    end

    local function apply_toggle_range(target, start_row, end_row)
      local rows = {}
      for row = start_row, end_row do
        local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
        rows[#rows + 1] = toggle_norg_line(line, target)
      end
      vim.api.nvim_buf_set_lines(0, start_row - 1, end_row, false, rows)
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
    map("n", "<LocalLeader>ih", function() insert_marker_line("heading") end, "[neorg] Insert heading below")
    map("n", "<LocalLeader>il", function() insert_marker_line("unordered") end, "[neorg] Insert list below")
    map("n", "<LocalLeader>io", function() insert_marker_line("ordered") end, "[neorg] Insert ordered list below")
    map("n", "<LocalLeader>it", function() insert_marker_line("todo") end, "[neorg] Insert todo below")
    map("n", "<LocalLeader>mh", function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, { toggle_norg_line(line, "heading") })
    end, "[neorg] Toggle Heading")
    map("n", "<LocalLeader>ml", function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, { toggle_norg_line(line, "unordered") })
    end, "[neorg] Toggle Unordered List")
    map("n", "<LocalLeader>mo", function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, { toggle_norg_line(line, "ordered") })
    end, "[neorg] Toggle Ordered List")
    map("n", "<LocalLeader>mt", function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, { toggle_norg_line(line, "todo") })
    end, "[neorg] Toggle Todo")
    map("v", "<LocalLeader>ml", function()
      local start_row = vim.fn.line("'<")
      local end_row = vim.fn.line("'>")
      apply_toggle_range("unordered", start_row, end_row)
    end, "[neorg] Toggle Unordered List (Range)")
    map("v", "<LocalLeader>mo", function()
      local start_row = vim.fn.line("'<")
      local end_row = vim.fn.line("'>")
      apply_toggle_range("ordered", start_row, end_row)
    end, "[neorg] Toggle Ordered List (Range)")
    map("v", "<LocalLeader>mt", function()
      local start_row = vim.fn.line("'<")
      local end_row = vim.fn.line("'>")
      apply_toggle_range("todo", start_row, end_row)
    end, "[neorg] Toggle Todo (Range)")
    map("n", "<LocalLeader>?", function()
      require("which-key").show({ keys = "<localleader>", loop = true })
    end, "[neorg] Browse keymaps")
    map("i", "<M-CR>", "<Plug>(neorg.itero.next-iteration)", "[neorg] Continue Object")
    map("i", "<M-d>", "<Plug>(neorg.tempus.insert-date.insert-mode)", "[neorg] Insert Date")
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

local function is_neorg_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local name = vim.api.nvim_buf_get_name(buf)
  return vim.bo[buf].filetype == "norg" or name:match("%.norg$") ~= nil
end

local function usable_non_neorg_buffer()
  local function usable(buf)
    if not vim.api.nvim_buf_is_valid(buf) or is_neorg_buffer(buf) then
      return false
    end
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
      return true
    end
    if vim.bo[buf].modified then
      return true
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if #lines > 1 then
      return true
    end
    if #lines == 1 and lines[1] ~= "" then
      return true
    end
    return false
  end

  local alt = vim.fn.bufnr("#")
  if alt ~= -1 and usable(alt) then
    return alt
  end

  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local buf = info.bufnr
    if usable(buf) then
      return buf
    end
  end

  return nil
end

local function close_neorg_buffers()
  local neorg_buffers = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if is_neorg_buffer(buf) then
      neorg_buffers[#neorg_buffers + 1] = buf
    end
  end

  if #neorg_buffers == 0 then
    return
  end

  local saves = {}
  local failures = {}
  for _, buf in ipairs(neorg_buffers) do
    if vim.bo[buf].modified then
      local name = vim.api.nvim_buf_get_name(buf)
      local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
        vim.cmd("update")
      end)
      if not ok or vim.bo[buf].modified then
        failures[#failures + 1] = string.format("%s: %s", name ~= "" and name or ("buf #%d"):format(buf), err or "save failed")
      else
        saves[#saves + 1] = buf
      end
    else
      saves[#saves + 1] = buf
    end
  end

  local destination = usable_non_neorg_buffer()
  if destination ~= nil then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.tbl_contains(neorg_buffers, buf) then
        vim.api.nvim_win_set_buf(win, destination)
      end
    end
  end

  local closing = {}
  for _, buf in ipairs(saves) do
    if vim.api.nvim_buf_is_valid(buf) then
      closing[#closing + 1] = buf
    end
  end

  for _, buf in ipairs(closing) do
    local ok, err = pcall(vim.api.nvim_buf_delete, buf, { force = false })
    if not ok then
      failures[#failures + 1] = string.format("%s: %s", vim.api.nvim_buf_get_name(buf), err or "close failed")
    end
  end

  if #failures > 0 then
    vim.notify(("Failed to save or close Neorg buffers:\n- %s"):format(table.concat(failures, "\n- ")), vim.log.levels.ERROR, {
      title = "Neorg close",
    })
    return
  end

  if destination == nil then
    vim.cmd("only")
    if Snacks and Snacks.dashboard then
      Snacks.dashboard()
    end
  end
end

local function map(lhs, rhs, desc)
  vim.keymap.set("n", "<leader>j" .. lhs, rhs, { desc = desc, silent = true })
end

map("p", function() vim.cmd("Neorg workspace personal") end, "Workspace: personal")
map("w", function() vim.cmd("Neorg workspace work") end, "Workspace: work")
map("i", function() vim.cmd("Neorg index") end, "Workspace index")
map("j", function() vim.cmd("Neorg journal today") end, "Journal today")
map("n", function() dirman().new_note() end, "New note (current workspace)")
map("q", close_neorg_buffers, "Close Neorg buffers")
map("s", function() vim.cmd("NotesSync") end, "Sync notes repo")
map("f", function()
  Snacks.picker.files({ cwd = WORKSPACES[current_workspace()] })
end, "Find notes (current workspace)")
map("g", function()
  Snacks.picker.grep({ dirs = { WORKSPACES.personal, WORKSPACES.work } })
end, "Grep notes (personal + work)")

return M
