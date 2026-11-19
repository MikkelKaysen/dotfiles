-- ---------------------------------------------------------------------------
-- Orgmode notes: notes.org root + agenda/capture + NotesSync integration.
-- ---------------------------------------------------------------------------

local NOTES_ROOT = vim.fs.normalize("/home/mkay/code/personal/notes.org")
local NOTES_INDEX = NOTES_ROOT .. "/index.org"

local function org_files_picker()
  require("snacks").picker.files({ cwd = NOTES_ROOT, glob = "*.org" })
end

local function org_grep()
  require("snacks").picker.grep({ cwd = NOTES_ROOT, glob = "*.org" })
end

local function org_heading_grep()
  require("snacks").picker.grep({
    cwd = NOTES_ROOT,
    search = "^\\*+ ",
    regex = true,
    glob = "*.org",
  })
end

local function save_note_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return true
  end
  if vim.bo[buf].filetype ~= "org" then
    return true
  end
  if not vim.bo[buf].modified then
    return true
  end

  local ok = pcall(vim.api.nvim_buf_call, buf, function()
    vim.cmd.write()
  end)
  if not ok then
    vim.notify("Orgmode: failed to save note buffer before close", vim.log.levels.ERROR)
    return false
  end
  return true
end

local function usable_non_note_buffer()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
      local ft = vim.bo[buf].filetype
      if ft ~= "org" and ft ~= "orgagenda" and ft ~= "orgmode" and vim.bo[buf].buflisted then
        return buf
      end
    end
  end

  local newbuf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(newbuf, "org-closer-buffer")
  return newbuf
end

local function under_notes_root(path)
  local norm = vim.fs.normalize(path or "")
  return norm == NOTES_ROOT or norm:sub(1, #NOTES_ROOT + 1) == NOTES_ROOT .. "/"
end

local function close_org_buffers()
  local org_buffers = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if vim.bo[buf].filetype == "org" and under_notes_root(name) then
        org_buffers[#org_buffers + 1] = buf
      end
    end
  end

  if #org_buffers == 0 then
    vim.notify("Orgmode: no org buffers under notes root to close", vim.log.levels.INFO)
    return
  end

  local target = usable_non_note_buffer()
  for _, buf in ipairs(org_buffers) do
    if not save_note_buffer(buf) then
      vim.notify("Orgmode: save failed; aborting note close", vim.log.levels.ERROR)
      return
    end
    local wins = vim.fn.win_findbuf(buf)
    for _, win in ipairs(wins) do
      if vim.api.nvim_win_is_valid(win) then
        local cur = vim.api.nvim_get_current_win()
        if win == cur then
          if vim.api.nvim_win_is_valid(vim.fn.win_getid(vim.fn.win_findbuf(target)[1] or vim.api.nvim_get_current_win())) then
            vim.api.nvim_set_current_win(vim.fn.win_getid(vim.fn.win_findbuf(target)[1] or vim.api.nvim_get_current_win()))
          end
        end
        vim.api.nvim_win_set_buf(win, target)
      end
    end
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

require("orgmode").setup({
  org_agenda_files = { NOTES_ROOT .. "/**/*.org" },
  org_default_notes_file = NOTES_INDEX,
  org_todo_keywords = { "TODO", "NEXT", "|", "DONE" },
  org_capture_templates = {
    j = {
      description = "Journal",
      template = "\n*** %<%Y-%m-%d> %<%A>\n**** %U\n\n%?",
      target = NOTES_ROOT .. "/journal.org",
      datetree = true,
    },
    t = {
      description = "Task",
      template = "* TODO %?\n %u",
      target = NOTES_INDEX,
    },
  },
  mappings = {
    global = {
      org_agenda = "<leader>ja",
      org_capture = "<leader>jc",
    },
  },
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "org",
  group = vim.api.nvim_create_augroup("orgmode_buffer_opts", { clear = true }),
  callback = function()
    vim.opt_local.conceallevel = 2
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.spell = true
  end,
})

require("util.notes_sync").setup({
  root = NOTES_ROOT,
  expected_remote = "git@github.com:MikkelKaysen/notes.org.git",
})

vim.keymap.set("n", "<leader>j", "", { desc = "Orgmode", remap = false })
vim.keymap.set("n", "<leader>ji", function()
  vim.cmd.edit(NOTES_INDEX)
end, { desc = "Open Notes Index" })
vim.keymap.set("n", "<leader>jj", function()
  require("orgmode").instance().capture:open_template_by_shortcut("j")
end, { desc = "Open Journal Capture" })
vim.keymap.set("n", "<leader>ja", function()
  vim.cmd.OrgAgenda()
end, { desc = "Org Agenda" })
vim.keymap.set("n", "<leader>jc", function()
  require("orgmode").capture.prompt()
end, { desc = "Capture" })
vim.keymap.set("n", "<leader>jf", function()
  org_files_picker()
end, { desc = "Files" })
vim.keymap.set("n", "<leader>jg", function()
  org_grep()
end, { desc = "Grep" })
vim.keymap.set("n", "<leader>jh", function()
  org_heading_grep()
end, { desc = "Grep headings" })
vim.keymap.set("n", "<leader>js", function()
  vim.cmd.NotesSync()
end, { desc = "NotesSync" })
vim.keymap.set("n", "<leader>jq", close_org_buffers, { desc = "Close note buffers" })

require("which-key").add({ { "<leader>j", group = "org" } }, { notify = false })
