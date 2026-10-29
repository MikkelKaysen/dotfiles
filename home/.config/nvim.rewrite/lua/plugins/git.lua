-- ---------------------------------------------------------------------------
-- git (ported from the old config's lua/plugins/git.lua — the telescope
-- extension is replaced with a Snacks picker/input).
-- neogit + git-worktree.nvim.
-- The <leader>gg/gG/gw/gW maps in config/keymaps.lua require this module
-- lazily. No setup is needed for git-worktree (this version has no setup());
-- diffview only exists as a neogit dependency, same as the old config.
-- ---------------------------------------------------------------------------

local Snacks = require("snacks")

local M = {}

-- neogit (matches the old config's `opts = {}`)
require("neogit").setup({})

---@param opts? { cwd?: string }
function M.open_neogit(opts)
  require("neogit").open(opts)
end

-- ---------------------------------------------------------------------------
-- git worktrees (polarmutex/git-worktree.nvim)
-- ---------------------------------------------------------------------------

-- List worktrees via `git worktree list --porcelain` (NUL-free, line-based,
-- so paths containing spaces are preserved intact). Skips bare entries only;
-- records without a HEAD SHA are kept (sha is ""). Primary identity is NOT
-- inferred from list order (see find_primary).
-- Returns nil when git errors (e.g. not inside a repository).
---@return { path: string, sha: string, branch: string?, detached: boolean }[] | nil
local function worktrees()
  local output = vim.fn.systemlist({ "git", "worktree", "list", "--porcelain" })
  if vim.v.shell_error ~= 0 then
    return nil
  end
  local ret = {}
  local cur = nil
  local function flush()
    if cur and cur.path and not cur.bare then
      cur.sha = cur.sha or ""
      ret[#ret + 1] = cur
    end
    cur = nil
  end
  for _, line in ipairs(output) do
    if line == "" then
      flush()
    elseif vim.startswith(line, "worktree ") then
      flush()
      cur = { path = line:sub(#"worktree " + 1), detached = false }
    elseif not cur then
      -- ignore anything outside a worktree record
    elseif vim.startswith(line, "HEAD ") then
      cur.sha = line:sub(#"HEAD " + 1)
    elseif vim.startswith(line, "branch ") then
      cur.branch = line:sub(#"branch " + 1):gsub("^refs/heads/", "")
    elseif line == "detached" then
      cur.detached = true
    elseif line == "bare" then
      cur.bare = true
    end
  end
  flush()
  return ret
end

-- Git root (absolute, no trailing newline) or nil.
---@return string?
local function git_root()
  local out = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 or not out[1] or out[1] == "" then
    return nil
  end
  return (out[1]:gsub("/+$", ""))
end

-- Path relative to root: "." for the root itself, "../x" style for siblings,
-- falling back to the original path if no relative path can be computed.
-- (vim.fs.relpath only handles descendants, so ".." segments are built here.)
---@param root string?
---@param path string
---@return string
local function rel_to_root(root, path)
  if not root or root == "" then
    return path
  end
  local base = root:gsub("/+$", "")
  local target = path:gsub("/+$", "")
  if target == base then
    return "."
  end
  local function split(p)
    local parts = {}
    for seg in p:gmatch("[^/]+") do
      parts[#parts + 1] = seg
    end
    return parts
  end
  local b, t = split(base), split(target)
  if #b == 0 or #t == 0 or (vim.startswith(path, "/") ~= vim.startswith(root, "/")) then
    return path
  end
  local i = 0
  while i < #b and i < #t and b[i + 1] == t[i + 1] do
    i = i + 1
  end
  local out = {}
  for _ = i + 1, #b do
    out[#out + 1] = ".."
  end
  for j = i + 1, #t do
    out[#out + 1] = t[j]
  end
  if #out == 0 then
    return "."
  end
  return table.concat(out, "/")
end

-- ---------------------------------------------------------------------------
-- worktree deletion (Alt-D inside the worktree picker)
-- ---------------------------------------------------------------------------

-- Normalized absolute path (symlinks resolved, no trailing slash) for comparisons.
---@param p string
---@return string
local function norm(p)
  local uv = vim.uv or vim.loop
  local real = uv.fs_realpath(p) or p
  return (real:gsub("/+$", ""))
end

-- Run git with an argv array (never shell-concatenated) in `cwd`.
---@return boolean ok, string msg
local function git(cwd, args)
  local argv = vim.list_extend({ "git" }, args)
  local res = vim.system(argv, { cwd = cwd, text = true }):wait()
  if res.code == 0 then
    return true, ""
  end
  local msg = vim.trim(res.stderr or "")
  if msg == "" then
    msg = vim.trim(res.stdout or "")
  end
  return false, msg ~= "" and msg or ("git exited with code " .. res.code)
end

-- Only one deletion flow may run at a time.
local busy = false

-- Resume a deletion coroutine, surfacing errors and releasing the busy guard.
local function step(co, ...)
  local ok, err = coroutine.resume(co, ...)
  if not ok then
    busy = false
    vim.notify("Worktree deletion aborted: " .. tostring(err), vim.log.levels.ERROR)
  end
end

-- Async-safe yes/no prompt. Must be called inside a coroutine started by `step`.
-- Returns "Yes", "No", or nil (cancelled). vim.ui.select callbacks may fire
-- synchronously or later, so both orders are handled.
---@return string?
local function ask(prompt, choices)
  local co = coroutine.running()
  local done, answer, waiting = false, nil, false
  vim.ui.select(choices, { prompt = prompt }, function(choice)
    done, answer = true, choice
    if waiting then
      step(co)
    end
  end)
  if not done then
    waiting = true
    coroutine.yield()
  end
  return answer
end

-- Run a git query and return trimmed stdout, or nil on failure.
---@return string?
local function git_out(cwd, args)
  local res = vim.system(vim.list_extend({ "git" }, args), { cwd = cwd, text = true }):wait()
  if res.code ~= 0 then
    return nil
  end
  return vim.trim(res.stdout or "")
end

-- Identify the primary checkout without relying on worktree-list order.
-- Bare repos have no primary (primary = nil, lookup_failed = false).
-- Non-bare repos: the parent of the common git dir is the primary checkout;
-- match it against the parsed worktree paths. lookup_failed = true only when
-- git cannot answer or no listed worktree matches in a non-bare repo.
---@param cwd string
---@param all table[]
---@return { bare: boolean, primary: table?, lookup_failed: boolean }
local function find_primary(cwd, all)
  if git_out(cwd, { "rev-parse", "--is-bare-repository" }) == "true" then
    return { bare = true, primary = nil, lookup_failed = false }
  end
  local common = git_out(cwd, { "rev-parse", "--path-format=absolute", "--git-common-dir" })
  if not common or common == "" then
    return { bare = false, primary = nil, lookup_failed = true }
  end
  local common_key = norm(common)
  local parent = norm(vim.fs.dirname(common_key))
  for _, wt in ipairs(all) do
    if norm(wt.path) == parent then
      return { bare = false, primary = wt, lookup_failed = false }
    end
  end
  return { bare = false, primary = nil, lookup_failed = true }
end

-- True when the worktree at `path` contains `cwd` (equal, or cwd is a descendant).
---@param path string
---@param cwd string
---@return boolean
local function contains_path(path, cwd)
  local p, c = norm(path), norm(cwd)
  return c == p or vim.startswith(c, p .. "/")
end

-- Body of a deletion batch. Runs inside a coroutine.
---@param picker table?
---@param targets { path: string, branch: string?, detached: boolean }[]
local function delete_batch(picker, targets)
  local all = worktrees()
  if not all then
    busy = false
    return vim.notify("Could not list git worktrees; nothing deleted", vim.log.levels.ERROR)
  end
  local nvim_cwd = vim.fn.getcwd()
  local info = find_primary(nvim_cwd, all)
  local main_wt = info.primary
  -- Git command cwd: the primary checkout when known, otherwise the current cwd.
  local git_cwd = main_wt and main_wt.path or nvim_cwd
  if info.lookup_failed then
    vim.notify(
      "Could not identify the primary checkout; Git will refuse to remove it if selected",
      vim.log.levels.WARN
    )
  end

  -- Protect the primary (if known) and any worktree containing Neovim's cwd.
  local eligible, protected = {}, {}
  for _, wt in ipairs(targets) do
    if main_wt and norm(wt.path) == norm(main_wt.path) then
      protected[#protected + 1] = wt.path .. " (primary worktree)"
    elseif contains_path(wt.path, nvim_cwd) then
      protected[#protected + 1] = wt.path .. " (current worktree)"
    else
      eligible[#eligible + 1] = wt
    end
  end
  if #protected > 0 then
    vim.notify("Skipping protected worktree(s):\n" .. table.concat(protected, "\n"), vim.log.levels.WARN)
  end
  if #eligible == 0 then
    busy = false
    return
  end

  local confirm = ask(("Delete %d selected worktree(s)?"):format(#eligible), { "Yes", "No" })
  if confirm ~= "Yes" then
    busy = false
    return -- picker stays open
  end
  if picker then
    pcall(function()
      picker:close()
    end)
  end

  -- Phase 1: worktree removal, sequential, one failure never aborts the batch.
  local removed, skipped, failed = {}, {}, {}
  for _, wt in ipairs(eligible) do
    local ok, err = git(git_cwd, { "worktree", "remove", wt.path })
    if ok then
      removed[#removed + 1] = wt
    else
      vim.notify(("git worktree remove failed for %s:\n%s"):format(wt.path, err), vim.log.levels.WARN)
      local force = ask(("Force-remove worktree %s?"):format(wt.path), { "Yes", "No" })
      if force == "Yes" then
        local ok2, err2 = git(git_cwd, { "worktree", "remove", "--force", wt.path })
        if ok2 then
          removed[#removed + 1] = wt
        else
          failed[#failed + 1] = wt.path .. ": " .. err2
        end
      else
        skipped[#skipped + 1] = wt.path
      end
    end
  end

  -- Phase 2: branches, only after all worktree removals so that multiple
  -- selected branches are no longer checked out.
  local br_deleted, br_kept, br_failed = {}, {}, {}
  for _, wt in ipairs(removed) do
    if wt.branch and not wt.detached then
      local br = wt.branch
      local ok, err = git(git_cwd, { "branch", "-d", "--", br })
      if ok then
        br_deleted[#br_deleted + 1] = br
      else
        vim.notify(("git branch -d %s failed:\n%s"):format(br, err), vim.log.levels.WARN)
        local force = ask(("Force-delete branch %s with -D?"):format(br), { "Yes", "No" })
        if force == "Yes" then
          local ok2, err2 = git(git_cwd, { "branch", "-D", "--", br })
          if ok2 then
            br_deleted[#br_deleted + 1] = br
          else
            br_failed[#br_failed + 1] = br .. ": " .. err2
          end
        else
          br_kept[#br_kept + 1] = br
        end
      end
    end
  end

  -- Summary
  local lines = {
    ("Removed worktrees: %d"):format(#removed),
    ("Deleted branches: %d"):format(#br_deleted),
  }
  if #skipped > 0 then
    lines[#lines + 1] = "Skipped worktrees:\n  " .. table.concat(skipped, "\n  ")
  end
  if #failed > 0 then
    lines[#lines + 1] = "Failed worktrees:\n  " .. table.concat(failed, "\n  ")
  end
  if #br_kept > 0 then
    lines[#lines + 1] = "Kept branches:\n  " .. table.concat(br_kept, "\n  ")
  end
  if #br_failed > 0 then
    lines[#lines + 1] = "Failed branches:\n  " .. table.concat(br_failed, "\n  ")
  end
  local level = (#failed + #br_failed + #skipped) > 0 and vim.log.levels.WARN or vim.log.levels.INFO
  vim.notify(table.concat(lines, "\n"), level)

  busy = false
  -- Reopen a fresh picker so stale rows and selections are gone.
  M.worktree_select()
end

-- Entry point for the Alt-D picker action.
---@param picker table
local function delete_selected(picker)
  if busy then
    return vim.notify("A worktree deletion is already in progress", vim.log.levels.WARN)
  end
  local targets, seen = {}, {}
  for _, item in ipairs(picker:selected({ fallback = true })) do
    local wt = item.wt
    if wt and wt.path and not seen[wt.path] then
      seen[wt.path] = true
      targets[#targets + 1] = wt
    end
  end
  if #targets == 0 then
    return
  end
  busy = true
  step(coroutine.create(delete_batch), picker, targets)
end

-- <leader>gw — pick an existing worktree and switch to it
function M.worktree_select()
  local wts = worktrees()
  if not wts or #wts == 0 then
    return vim.notify("No git worktrees found (are you in a git repository?)", vim.log.levels.ERROR)
  end
  local root = git_root()
  local gap = "  "

  -- Build display rows first so widths can be computed across all rows.
  local rows = {}
  for _, wt in ipairs(wts) do
    local branch = wt.detached and "(detached HEAD)" or (wt.branch or "(unknown)")
    rows[#rows + 1] = {
      wt = wt,
      branch = branch,
      rel = rel_to_root(root, wt.path),
      sha = wt.sha or "",
    }
  end
  local w = { 0, 0, 0 }
  for _, r in ipairs(rows) do
    w[1] = math.max(w[1], vim.fn.strdisplaywidth(r.branch))
    w[2] = math.max(w[2], vim.fn.strdisplaywidth(r.rel))
    w[3] = math.max(w[3], vim.fn.strdisplaywidth(r.sha))
  end
  local function pad(s, width)
    return s .. string.rep(" ", width - vim.fn.strdisplaywidth(s))
  end

  local items = {}
  for _, r in ipairs(rows) do
    items[#items + 1] = {
      -- searchable text across all columns; wt carries the absolute path
      text = table.concat({ r.branch, r.rel, r.sha }, " "),
      wt = r.wt,
      cols = r,
    }
  end

  Snacks.picker({
    title = "Git Worktrees",
    layout = { preview = false },
    items = items,
    actions = {
      -- overrides Snacks' default <a-d> (inspect) for this picker only
      worktree_delete = delete_selected,
    },
    win = {
      input = {
        keys = { ["<a-d>"] = { "worktree_delete", mode = { "n", "i" }, desc = "Delete worktree(s)" } },
      },
      list = {
        keys = { ["<a-d>"] = { "worktree_delete", mode = { "n" }, desc = "Delete worktree(s)" } },
      },
    },
    format = function(item)
      local r = item.cols
      return {
        { pad(r.branch, w[1]), r.wt.detached and "Comment" or "Special" },
        { gap },
        { pad(r.rel, w[2]), "Directory" },
        { gap },
        { pad(r.sha, w[3]), "Number" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      require("git-worktree").switch_worktree(item.wt.path)
    end,
  })
end

-- <leader>gW — prompt for branch + path, then create a worktree and switch to it
function M.worktree_create()
  Snacks.input({ prompt = "New worktree branch:" }, function(branch)
    branch = (branch or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if branch == "" then
      return
    end
    Snacks.input(
      { prompt = "Worktree path:", default = "../" .. branch },
      function(path)
        path = (path or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if path == "" then
          return
        end
        require("git-worktree").create_worktree(path, branch, nil)
      end
    )
  end)
end

return M
