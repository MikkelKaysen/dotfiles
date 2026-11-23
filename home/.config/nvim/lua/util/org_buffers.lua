-- ---------------------------------------------------------------------------
-- Org (org.nvim) buffer/window classification shared by the note close logic
-- (plugins/org.lua) and the restart guard (config/keymaps.lua).
--
-- Markers come from org.nvim v3.6.1 source (not guessed):
--   capture buffer   : require("org.capture").sessions[buf] (session table,
--                      buffer named CAPTURE-<key>, buftype "acwrite")
--   source-edit buf  : require("org.special").edits[buf] (edit buffer named
--                      org-special://..., buftype "acwrite")
--   agenda buffer    : filetype "orgagenda"
--   log note buffer  : filetype "org" named "*Org Note*" (a split, not a float)
-- org.nvim's help (g?) and calendar windows are plain floats with no filetype
-- or name, so there is no marker for them and they are not classified here.
-- ---------------------------------------------------------------------------

local M = {}

local function valid(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

--- Is `buf` an org.nvim capture buffer that is still open?
---@param buf integer
---@return boolean
function M.is_capture(buf)
  if not valid(buf) then
    return false
  end
  local ok, capture = pcall(require, "org.capture")
  return ok and type(capture.sessions) == "table" and capture.sessions[buf] ~= nil
end

--- Is `buf` an org.nvim source-edit buffer (src block / table formulas)?
---@param buf integer
---@return boolean
function M.is_special_edit(buf)
  if not valid(buf) then
    return false
  end
  local ok, special = pcall(require, "org.special")
  return ok and type(special.edits) == "table" and special.edits[buf] ~= nil
end

--- Is `buf` the `*Org Note*` buffer (org.nvim's log-note split)?
---@param buf integer
---@return boolean
function M.is_note_ui(buf)
  if not valid(buf) or vim.bo[buf].filetype ~= "org" then
    return false
  end
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= "" and vim.fn.fnamemodify(name, ":t") == "*Org Note*"
end

--- Is `buf` the org.nvim agenda buffer?
---@param buf integer
---@return boolean
function M.is_agenda(buf)
  return valid(buf) and vim.bo[buf].filetype == "orgagenda"
end

--- Any org.nvim-owned buffer that must not be treated as a regular file
--- (capture, source-edit, note UI, agenda).
---@param buf integer
---@return boolean
function M.is_org_temp(buf)
  return M.is_capture(buf) or M.is_special_edit(buf) or M.is_note_ui(buf) or M.is_agenda(buf)
end

return M
