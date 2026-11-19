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
  if not ok or vim.bo[buf].modified then
    vim.notify("Orgmode: failed to save note buffer before close", vim.log.levels.ERROR)
    return false
  end
  return true
end

local function under_notes_root(path)
  local norm = vim.fs.normalize(path or "")
  return norm == NOTES_ROOT or norm:sub(1, #NOTES_ROOT + 1) == NOTES_ROOT .. "/"
end

local function is_note_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return false
  end

  local name = vim.api.nvim_buf_get_name(buf)
  return vim.bo[buf].filetype == "org" and under_notes_root(name)
end

local function is_capture_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  return vim.b[buf].org_capture == true
end

local function is_org_ui_window(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  if is_capture_buffer(buf) then
    return true
  end

  local ft = vim.bo[buf].filetype
  if ft == "orgagenda" or ft == "orghelp" then
    return true
  end
  if vim.b[buf].__org_edit_special_ctx then
    return true
  end

  local name = vim.api.nvim_buf_get_name(buf)
  if name and vim.fn.fnamemodify(name, ":t") == "orgcalendar" then
    return true
  end

  if ft == "org" and not under_notes_root(name) then
    local cfg = vim.api.nvim_win_get_config(win)
    local is_float = cfg.relative ~= "" or cfg.external
    if is_float and name == "" and not vim.bo[buf].modified then
      return true
    end
  end

  return false
end

local function is_usable_non_note_buffer(buf, win)
  if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return false
  end
  if not vim.bo[buf].buflisted then
    return false
  end
  if is_note_buffer(buf) then
    return false
  end
  if is_capture_buffer(buf) then
    return false
  end
  if win and is_org_ui_window(win) then
    return false
  end

  local ft = vim.bo[buf].filetype
  if ft == "orgagenda" or ft == "orghelp" or vim.b[buf].__org_edit_special_ctx then
    return false
  end

  local name = vim.api.nvim_buf_get_name(buf)
  if ft == "org" and not under_notes_root(name) and (name ~= "" or vim.bo[buf].modified) then
    return true
  end

  if name ~= "" or vim.bo[buf].modified then
    return true
  end

  return false
end

local function close_window_if_valid(win, force)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return true
  end

  local ok, err = pcall(vim.api.nvim_win_close, win, force or false)
  if not ok then
    vim.notify("Orgmode: failed to close window: " .. tostring(err), vim.log.levels.WARN)
    return false
  end
  return true
end

local function close_org_buffers()
  local capture_wins = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if vim.api.nvim_win_is_valid(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        if is_capture_buffer(buf) then
          capture_wins[#capture_wins + 1] = win
        end
      end
    end
  end

  for _, win in ipairs(capture_wins) do
    if not close_window_if_valid(win, true) then
      return
    end
  end

  vim.schedule(function()
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if vim.api.nvim_win_is_valid(win) then
          local buf = vim.api.nvim_win_get_buf(win)
          if is_capture_buffer(buf) then
            vim.notify("Orgmode: capture still open; aborting note close", vim.log.levels.INFO)
            return
          end
        end
      end
    end

    local ui_wins = {}
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if is_org_ui_window(win) then
          ui_wins[#ui_wins + 1] = win
        end
      end
    end
    for _, win in ipairs(ui_wins) do
      if not close_window_if_valid(win, true) then
        return
      end
    end

    local note_bufs = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if is_note_buffer(buf) then
        note_bufs[#note_bufs + 1] = buf
      end
    end

    for _, buf in ipairs(note_bufs) do
      if not save_note_buffer(buf) then
        vim.notify("Orgmode: save failed; aborting note close", vim.log.levels.ERROR)
        return
      end
    end

    local current_tab = vim.api.nvim_get_current_tabpage()
    local usable_win = nil
    local usable_tab = nil
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if vim.api.nvim_win_is_valid(win) then
          local buf = vim.api.nvim_win_get_buf(win)
          if is_usable_non_note_buffer(buf, win) then
            if tab == current_tab then
              usable_win = win
              usable_tab = tab
              break
            elseif not usable_win then
              usable_win = win
              usable_tab = tab
            end
          end
        end
      end
      if usable_win and usable_tab == current_tab then
        break
      end
    end

    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if vim.api.nvim_win_is_valid(win) then
          local buf = vim.api.nvim_win_get_buf(win)
          if is_note_buffer(buf) or is_org_ui_window(win) or is_capture_buffer(buf) then
            if usable_win and win == usable_win then
              -- preserve a usable non-note window
            else
              if not close_window_if_valid(win, true) then
                return
              end
            end
          end
        end
      end
    end

    if usable_win then
      if vim.api.nvim_win_get_tabpage(usable_win) ~= current_tab then
        vim.api.nvim_set_current_tabpage(usable_tab)
      end
      vim.api.nvim_set_current_win(usable_win)
      return
    end

    local survivor = nil
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(current_tab)) do
      if vim.api.nvim_win_is_valid(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        if not is_note_buffer(buf) and not is_org_ui_window(win) and not is_capture_buffer(buf) then
          survivor = win
          break
        end
      end
    end

    if not survivor then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(current_tab)) do
        if vim.api.nvim_win_is_valid(win) then
          local buf = vim.api.nvim_win_get_buf(win)
          if not is_note_buffer(buf) and not is_capture_buffer(buf) and not is_org_ui_window(win) then
            survivor = win
            break
          end
        end
      end
    end

    if not survivor or not vim.api.nvim_win_is_valid(survivor) then
      return
    end

    local survivor_buf = vim.api.nvim_win_get_buf(survivor)
    vim.api.nvim_set_current_win(survivor)
    vim.cmd("only")
    require("snacks").dashboard()

    if vim.api.nvim_buf_is_valid(survivor_buf) then
      local name = vim.api.nvim_buf_get_name(survivor_buf)
      local lines = vim.api.nvim_buf_get_lines(survivor_buf, 0, -1, false)
      if name == "" and not vim.bo[survivor_buf].modified and #lines == 1 and lines[1] == "" and #vim.fn.win_findbuf(survivor_buf) == 0 then
        pcall(vim.api.nvim_buf_delete, survivor_buf, { force = false })
      end
    end

    for _, buf in ipairs(note_bufs) do
      if vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) == 0 then
        pcall(vim.api.nvim_buf_delete, buf, { force = false })
      end
    end
  end)
end

require("orgmode").setup({
  org_agenda_files = { NOTES_ROOT .. "/**/*.org" },
  org_default_notes_file = NOTES_INDEX,
  org_todo_keywords = { "TODO", "NEXT", "|", "DONE" },
  org_capture_templates = {
    j = {
      description = "Journal",
      template = "* %U\n\n%?",
      target = NOTES_ROOT .. "/journal.org",
      datetree = true,
    },
    t = {
      description = "Task",
      template = "* TODO %?\n %u",
      target = NOTES_INDEX,
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

vim.keymap.set("n", "<leader>of", function()
  org_files_picker()
end, { desc = "Files" })
vim.keymap.set("n", "<leader>og", function()
  org_grep()
end, { desc = "Grep" })
vim.keymap.set("n", "<leader>os", function()
  vim.cmd.NotesSync()
end, { desc = "NotesSync" })
vim.keymap.set("n", "<leader>oq", close_org_buffers, { desc = "Close note buffers" })

require("which-key").add({ { "<leader>o", group = "org" } }, { notify = false })
