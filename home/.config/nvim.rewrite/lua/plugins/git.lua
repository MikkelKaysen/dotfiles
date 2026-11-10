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

-- ---------------------------------------------------------------------------
-- worktree creation (<leader>gW)
-- ---------------------------------------------------------------------------

-- Run git and return stdout lines (empty lines dropped), or nil + message.
---@return string[]?, string?
local function git_lines(cwd, args)
  local res = vim.system(vim.list_extend({ "git" }, args), { cwd = cwd, text = true }):wait()
  if res.code ~= 0 then
    return nil, vim.trim(res.stderr or "")
  end
  return vim.split(res.stdout or "", "\n", { plain = true, trimempty = true }), nil
end

-- Fields: refname, symref (non-empty for remote HEAD), objectname, date, subject.
local REF_FORMAT = "--format=%(refname)\t%(symref)\t%(objectname)\t%(committerdate:short)\t%(subject)"

-- Scan local and remote-tracking branches for the creation picker. Symbolic
-- remote HEAD refs are skipped. Branches checked out in a worktree are kept
-- but flagged (`in_use`) so they are shown as unavailable and refused.
---@param cwd string
---@return table?, string?
local function scan_branches(cwd)
  local lines, err = git_lines(cwd, { "for-each-ref", REF_FORMAT, "refs/heads", "refs/remotes" })
  if not lines then
    return nil, err
  end
  local remotes = git_lines(cwd, { "remote" }) or {}
  table.sort(remotes, function(a, b)
    return #a > #b -- longest first, so remote prefixes match exactly
  end)
  local checked = {} -- local branch name -> worktree path
  for _, wt in ipairs(worktrees() or {}) do
    if wt.branch then
      checked[wt.branch] = wt.path
    end
  end
  local st = { entries = {}, locals = {}, remote_entries = {}, remote_shorts = {}, checked = checked }
  for _, line in ipairs(lines) do
    local ref, symref, sha, date, subject = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t?(.*)$")
    if ref and symref == "" then
      local kind, name, short
      if vim.startswith(ref, "refs/heads/") then
        kind, name = "local", ref:sub(#"refs/heads/" + 1)
        short = name
      elseif vim.startswith(ref, "refs/remotes/") then
        local rest = ref:sub(#"refs/remotes/" + 1)
        for _, r in ipairs(remotes) do
          if vim.startswith(rest, r .. "/") then
            kind, short, name = "remote", rest, rest:sub(#r + 2)
            break
          end
        end
      end
      if kind and name ~= "" then
        local in_use = checked[name] ~= nil
        local e = {
          kind = kind,
          name = name, -- local branch name (remote: the name a local would get)
          short = short, -- full remote-tracking name, e.g. origin/feature/x
          display = short,
          sha = sha,
          date = date,
          subject = subject or "",
          kind_label = in_use and "in use" or kind,
          in_use = in_use,
        }
        e.text = table.concat({ short, kind, subject or "" }, " ")
        st.entries[#st.entries + 1] = e
        if kind == "local" then
          st.locals[name] = e
        else
          st.remote_entries[#st.remote_entries + 1] = e
          st.remote_shorts[short] = e
        end
      end
    end
  end
  return st
end

-- Turn a scanned entry into { branch, upstream } or nil (after notifying).
-- Existing local branches are used as-is with no upstream change. A remote
-- without a local gets a new local tracking it; if a local already exists it
-- is used instead and a warning is shown when the hashes differ.
---@return { branch: string, upstream: string? }?
local function resolve_entry(st, e)
  local lname = e.name
  if st.checked[lname] then
    vim.notify(("Branch '%s' is already checked out in %s"):format(lname, st.checked[lname]), vim.log.levels.WARN)
    return nil
  end
  local loc = st.locals[lname]
  if loc then
    if e.kind == "remote" and loc.sha ~= e.sha then
      vim.notify(
        ("Local '%s' (%s) differs from %s (%s); using the local branch and leaving its upstream unchanged"):format(
          lname,
          loc.sha:sub(1, 7),
          e.short,
          e.sha:sub(1, 7)
        ),
        vim.log.levels.WARN
      )
    end
    return { branch = lname, upstream = nil }
  end
  return { branch = lname, upstream = e.short }
end

-- Resolve a typed name that matched no picker item. Existing locals and remote
-- branches with the same local name are used; otherwise a new branch from HEAD.
---@return { branch: string, upstream: string? }?
local function resolve_typed(st, cwd, name)
  if name == "HEAD" then
    vim.notify("'HEAD' is not a valid branch name", vim.log.levels.ERROR)
    return nil
  end
  local ok, msg = git(cwd, { "check-ref-format", "--branch", name })
  if not ok then
    vim.notify(("'%s' is not a valid branch name:\n%s"):format(name, msg), vim.log.levels.ERROR)
    return nil
  end
  if st.locals[name] then
    return resolve_entry(st, st.locals[name])
  end
  if st.remote_shorts[name] then
    return resolve_entry(st, st.remote_shorts[name])
  end
  local matches = {}
  for _, r in ipairs(st.remote_entries) do
    if r.name == name then
      matches[#matches + 1] = r
    end
  end
  if #matches > 1 then
    local names = vim.tbl_map(function(r)
      return r.short
    end, matches)
    vim.notify(
      ("'%s' exists on several remotes; select it from the list:\n%s"):format(name, table.concat(names, "\n")),
      vim.log.levels.WARN
    )
    return nil
  end
  if #matches == 1 then
    return resolve_entry(st, matches[1])
  end
  return { branch = name, upstream = nil }
end

-- Ask for the worktree path (default ../<branch>, slashes kept), then create it.
---@param st table
---@param sel { branch: string, upstream: string? }
local function prompt_path_and_create(st, sel)
  if st.remote_shorts[sel.branch] then
    return vim.notify(
      ("'%s' is also a remote-tracking branch name; refusing to create an ambiguous worktree"):format(sel.branch),
      vim.log.levels.ERROR
    )
  end
  Snacks.input({ prompt = "Worktree path:", default = "../" .. sel.branch }, function(path)
    path = vim.trim(path or "")
    if path == "" then
      return
    end
    require("git-worktree").create_worktree(path, sel.branch, sel.upstream)
  end)
end

-- Only one manual fetch may run at a time.
local fetching = false

-- Asynchronously run `git fetch --all --prune` in the launch cwd, then refresh
-- the picker's list on success. Safe if the picker was closed meanwhile.
---@param picker table?
---@param cwd string
local function fetch_remotes(picker, cwd)
  if fetching then
    return vim.notify("A fetch is already in progress", vim.log.levels.WARN)
  end
  fetching = true
  vim.notify("Fetching all remotes…", vim.log.levels.INFO)
  local ok, err = pcall(vim.system, { "git", "fetch", "--all", "--prune" }, { cwd = cwd, text = true }, function(res)
    vim.schedule(function()
      fetching = false
      if res.code ~= 0 then
        local msg = vim.trim(res.stderr or "")
        if msg == "" then
          msg = "git exited with code " .. res.code
        end
        return vim.notify("git fetch --all --prune failed:\n" .. msg, vim.log.levels.ERROR)
      end
      if picker and not picker.closed then
        pcall(picker.find, picker, { refresh = true })
      end
      vim.notify("Fetched all remotes", vim.log.levels.INFO)
    end)
  end)
  if not ok then
    fetching = false
    vim.notify("Could not start git fetch: " .. tostring(err), vim.log.levels.ERROR)
  end
end

-- <leader>gW — pick a local/remote branch (or type a new name) and create a
-- worktree for it. Creation uses the plugin's create_worktree.
function M.worktree_create()
  local cwd = vim.fn.getcwd()
  local st, err = scan_branches(cwd)
  if not st then
    return vim.notify("Could not list git branches (are you in a git repository?): " .. (err or ""), vim.log.levels.ERROR)
  end

  local gap = "  "
  local w = { 0, 0, 0 } -- name, type, date widths (refreshed on each find)
  local function pad(s, width)
    return s .. string.rep(" ", width - vim.fn.strdisplaywidth(s))
  end

  Snacks.picker({
    title = "Create Worktree from Branch",
    layout = { preview = false },
    finder = function()
      local fresh, ferr = scan_branches(cwd)
      if not fresh then
        vim.notify("Could not list git branches: " .. (ferr or ""), vim.log.levels.ERROR)
        return {}
      end
      w = { 0, 0, 0 }
      for _, e in ipairs(fresh.entries) do
        w[1] = math.max(w[1], vim.fn.strdisplaywidth(e.display))
        w[2] = math.max(w[2], vim.fn.strdisplaywidth(e.kind_label))
        w[3] = math.max(w[3], vim.fn.strdisplaywidth(e.date))
      end
      return fresh.entries
    end,
    actions = {
      worktree_fetch = function(p)
        fetch_remotes(p, cwd)
      end,
    },
    win = {
      input = {
        keys = { ["<a-f>"] = { "worktree_fetch", mode = { "n", "i" }, desc = "Fetch all remotes" } },
      },
      list = {
        keys = { ["<a-f>"] = { "worktree_fetch", mode = { "n" }, desc = "Fetch all remotes" } },
      },
    },
    format = function(item)
      local e = item
      return {
        { pad(e.display, w[1]), e.in_use and "Comment" or (e.kind == "remote" and "Special" or "Function") },
        { gap },
        { pad(e.kind_label, w[2]), e.in_use and "WarningMsg" or "Comment" },
        { gap },
        { pad(e.date, w[3]), "Number" },
        { gap },
        { e.subject, "Normal" },
      }
    end,
    confirm = function(p, item)
      local typed = vim.trim(p.input:get() or "")
      p:close()
      local fresh, ferr = scan_branches(cwd)
      if not fresh then
        return vim.notify("Could not list git branches: " .. (ferr or ""), vim.log.levels.ERROR)
      end
      local sel
      if item then
        sel = resolve_entry(fresh, item)
      elseif typed ~= "" then
        sel = resolve_typed(fresh, cwd, typed)
      end
      if sel then
        prompt_path_and_create(fresh, sel)
      end
    end,
  })
end

return M
