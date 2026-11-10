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

-- True when Neovim's cwd is no longer the directory the flow was started from.
-- The worktree helper reads the ambient cwd, so creation must not proceed then.
---@param cwd string
---@return boolean
local function cwd_changed(cwd)
  return norm(vim.fn.getcwd()) ~= norm(cwd)
end

-- Reject newly entered worktree paths that would become option-like arguments
-- or break the plugin's unescaped `cd` (vim.cmd) command.
---@param p string
---@return string?
local function path_problem(p)
  if vim.startswith(p, "-") then
    return "must not start with '-'"
  end
  if p:find("[\n\r|]") then
    return "must not contain a newline, carriage return or '|'"
  end
  return nil
end

-- Scan local and remote-tracking branches for the creation picker. Symbolic
-- remote HEAD refs are skipped. Branches checked out in a worktree are kept
-- but flagged (`in_use`) so they are shown as unavailable and refused.
---@param cwd string
---@return table?, string?
local function scan_branches(cwd)
  if cwd_changed(cwd) then
    return nil, "working directory changed since the picker was opened; reopen <leader>gW"
  end
  local lines, err = git_lines(cwd, { "for-each-ref", REF_FORMAT, "refs/heads", "refs/remotes" })
  if not lines then
    return nil, err
  end
  local remotes, rerr = git_lines(cwd, { "remote" })
  if not remotes then
    return nil, (rerr ~= "" and rerr) or "git remote failed"
  end
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

-- Default path for a new worktree of `branch` (slashes kept). Only bare-repo
-- layouts change it; everything else, and any detection failure, keeps the
-- sibling default "../<branch>".
--   Layout B: the shared git dir is itself the bare repo -> <common>/<branch>.
--   Layout A: <root>/.git is a gitdir file whose target resolves to the bare
--             shared dir (e.g. <root>/.bare) -> <root>/<branch>.
---@param cwd string
---@param branch string
---@return string
local function default_worktree_path(cwd, branch)
  local fallback = "../" .. branch
  local ok, result = pcall(function()
    local common = git_out(cwd, { "rev-parse", "--path-format=absolute", "--git-common-dir" })
    if not common or common == "" then
      return fallback
    end
    local common_key = norm(common)
    local cfg = vim.system({ "git", "--git-dir", common_key, "config", "--bool", "core.bare" }, { text = true }):wait()
    if cfg.code ~= 0 or vim.trim(cfg.stdout or "") ~= "true" then
      return fallback
    end
    local root = vim.fs.dirname(common_key)
    local uv = vim.uv or vim.loop
    local dotgit = root .. "/.git"
    local st = uv.fs_stat(dotgit)
    if st and st.type == "file" then
      local read_ok, lines = pcall(vim.fn.readfile, dotgit, "", 1)
      local target = read_ok and type(lines[1]) == "string" and lines[1]:match("^gitdir:%s*(.-)%s*$") or nil
      if target and target ~= "" then
        if not vim.startswith(target, "/") then
          target = root .. "/" .. target
        end
        if norm(target) == common_key then
          return root .. "/" .. branch
        end
      end
    end
    return common_key .. "/" .. branch
  end)
  return ok and result or fallback
end

-- ---------------------------------------------------------------------------
-- worktree creation safety + git worktree add (replaces the plugin's create,
-- which hides Git errors and interpolates the cd command unescaped)
-- ---------------------------------------------------------------------------

local uv = vim.uv or vim.loop
local Hooks = nil -- git-worktree.hooks, required lazily when a flow runs

-- Direct children of a bare common dir that Git itself uses; never a worktree.
-- (Unknown custom dirs are not guessed: they stay allowed as user paths.)
local RESERVED = {}
for _, n in ipairs({
  "objects", "refs", "worktrees", "hooks", "info", "logs", "branches", "modules", "lfs",
  "rr-cache", "config", "config.worktree", "HEAD", "packed-refs", "shallow", "commondir",
  "description", "index", "FETCH_HEAD", "ORIG_HEAD", "MERGE_HEAD", "MERGE_MSG", "SQUASH_MSG",
  "AUTO_MERGE", "REBASE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "COMMIT_EDITMSG",
  "BISECT_LOG", "BISECT_START", "gc.log", "gc.pid", "svn", "rebase-apply", "rebase-merge",
  "sequencer",
}) do
  RESERVED[n] = true
end
local MAX_SCAN = 50000

-- Lexical collapse of "." and ".." segments (only used after walk_raw).
local function collapse(p)
  local out = {}
  for seg in p:gmatch("[^/]+") do
    if seg == ".." then
      out[#out] = nil
    elseif seg ~= "." then
      out[#out + 1] = seg
    end
  end
  return "/" .. table.concat(out, "/")
end

-- lstat: stat, or nil when ENOENT. Raises on any other access error (fail closed).
local function lstat_strict(p)
  local st, err, name = uv.fs_lstat(p)
  if st then
    return st
  end
  if name == "ENOENT" then
    return nil
  end
  error(("cannot inspect %s: %s"):format(p, tostring(err)), 0)
end

-- Walk the raw absolute path component by component BEFORE any ".." collapse,
-- refusing any symlink (leaf, ancestor or dangling). Returns the leaf stat or nil
-- when missing. A ".." after a missing component is refused (cannot be resolved safely).
local function walk_raw(abs)
  local cur, leaf = "", nil
  local segs = vim.split(abs, "/", { plain = true, trimempty = true })
  for i, seg in ipairs(segs) do
    cur = cur .. "/" .. seg
    local st = lstat_strict(cur)
    if not st then
      if abs:find("/%.%./") or abs:find("/%.%.$") then
        error("cannot resolve '..' below a missing directory: " .. abs, 0)
      end
      return nil
    end
    if st.type == "link" then
      error("refusing: symlink in path at " .. cur, 0)
    end
    if i == #segs then
      leaf = st
    end
  end
  return leaf
end

-- Entries of a directory (raises on error). Names and types only; never follows links.
local function dir_entries(p)
  local req, err = uv.fs_scandir(p)
  if not req then
    error(("cannot read %s: %s"):format(p, tostring(err)), 0)
  end
  local out = {}
  for name, typ in function()
    return uv.fs_scandir_next(req)
  end do
    out[#out + 1] = { name = name, type = typ }
  end
  return out
end

-- True when `p` holds Git metadata: a .git entry, or bare-repo markers.
local function is_git_repo_dir(p)
  return lstat_strict(p .. "/.git") ~= nil
    or (lstat_strict(p .. "/HEAD") ~= nil and lstat_strict(p .. "/objects") ~= nil and lstat_strict(p .. "/refs") ~= nil)
end

-- Refuse nested Git repos and cross-device directories while walking `dir`.
-- Symlinks are never followed (removed as links). `top` skips the target's own
-- .git (a registered worktree's own gitfile) but still inspects its children.
local function scan_foreign(dir, budget, dev, top)
  local ents = dir_entries(dir)
  budget.n = budget.n + #ents
  if budget.n > MAX_SCAN then
    error("too many entries to verify safely under " .. dir, 0)
  end
  if not top and is_git_repo_dir(dir) then
    error("contains a nested repository: " .. dir, 0)
  end
  for _, e in ipairs(ents) do
    if e.type ~= "link" then
      local st = lstat_strict(dir .. "/" .. e.name)
      if st and st.type == "directory" then
        if st.dev ~= dev then
          error("crosses a device boundary: " .. dir .. "/" .. e.name, 0)
        end
        scan_foreign(dir .. "/" .. e.name, budget, dev, false)
      end
    end
  end
end

-- Full registrations from `git worktree list` (bare and stale entries included).
-- The first record is always the primary checkout (or the bare repo).
---@return table[]?, string?
local function registrations(cwd)
  local lines, err = git_lines(cwd, { "worktree", "list", "--porcelain" })
  if not lines then
    return nil, (err ~= nil and err ~= "") and err or "git worktree list failed"
  end
  local regs, cur = {}, nil
  for _, line in ipairs(lines) do
    if vim.startswith(line, "worktree ") then
      cur = { path = line:sub(#"worktree " + 1), bare = false, prunable = false }
      regs[#regs + 1] = cur
    elseif cur and line == "bare" then
      cur.bare = true
    elseif cur and vim.startswith(line, "branch ") then
      cur.branch = (line:sub(#"branch " + 1):gsub("^refs/heads/", ""))
    elseif cur and vim.startswith(line, "prunable") then
      cur.prunable = true
    end
  end
  return regs
end

-- Layout A: <root>/.git is a gitdir file pointing at the bare common dir.
local function is_layout_a(root, common)
  local st = uv.fs_stat(root .. "/.git")
  if not st or st.type ~= "file" then
    return false
  end
  local ok, lines = pcall(vim.fn.readfile, root .. "/.git", "", 1)
  local target = ok and type(lines[1]) == "string" and lines[1]:match("^gitdir:%s*(.-)%s*$") or nil
  if not target or target == "" then
    return false
  end
  if not vim.startswith(target, "/") then
    target = root .. "/" .. target
  end
  return norm(target) == common
end

-- Strict descendant test on normalized absolute paths.
local function inside(dir, p)
  return p ~= dir and vim.startswith(p, dir .. "/")
end

-- Destructive preconditions for an existing target (plain or registered).
-- The target must be strictly inside the repo area, sit on the same device as
-- its parent, and no ancestor below the area may be a foreign repo.
local function check_destructive(canon, leaf, area, common, registered)
  if not inside(area, canon) then
    error("existing directory is outside the repo area " .. area, 0)
  end
  local pst = lstat_strict(vim.fs.dirname(canon))
  if not pst or pst.dev ~= leaf.dev then
    error("target is a mount point (device differs from its parent)", 0)
  end
  local a = vim.fs.dirname(canon)
  while inside(area, a) do
    if a ~= common and is_git_repo_dir(a) then
      error("ancestor is a git repository: " .. a, 0)
    end
    a = vim.fs.dirname(a)
  end
  scan_foreign(canon, { n = 0 }, leaf.dev, registered)
end

-- Classify the create target. Raises a readable error for every refusal.
-- Returns { kind = "missing"|"empty"|"plain"|"registered", stale, canon, leaf }.
local function classify(abs, cwd)
  local leaf = walk_raw(abs)
  local canon = collapse(abs)
  if canon == "/" then
    error("refusing to use the filesystem root", 0)
  end
  if canon:find("/.git/", 1, true) or canon:match("/%.git$") then
    error("path contains a .git component", 0)
  end

  local regs, rerr = registrations(cwd)
  if not regs or #regs == 0 then
    error("cannot list worktrees: " .. tostring(rerr), 0)
  end
  local common = git_out(cwd, { "rev-parse", "--path-format=absolute", "--git-common-dir" })
  local absgit = git_out(cwd, { "rev-parse", "--path-format=absolute", "--absolute-git-dir" })
  local bare = common and git_out(cwd, { "--git-dir", common, "config", "--bool", "core.bare" })
  if not common or common == "" or not absgit or absgit == "" or not bare then
    error("cannot query git metadata", 0)
  end
  common, absgit = norm(common), norm(absgit)
  local is_bare = bare == "true"
  local home = vim.env.HOME
  if not home or home == "" then
    error("HOME is unset", 0)
  end
  home = norm(home)

  -- Primary: the first `worktree list` record (also with a separate git dir).
  local primary = (not is_bare and regs[1] and not regs[1].bare) and norm(regs[1].path) or nil

  -- Repo area: the only place existing directories may be replaced.
  local area
  if primary then
    area = vim.fs.dirname(primary)
  elseif is_bare then
    local root = vim.fs.dirname(common)
    area = is_layout_a(root, common) and norm(root) or common
  else
    error("cannot identify the primary checkout", 0)
  end
  if area == "/" or (area ~= home and vim.startswith(home, area .. "/")) then
    error("repo area is too broad: " .. area, 0)
  end

  -- Never contain home (covers '/'), the cwd, its work tree, the primary or Git metadata.
  -- (With a separate git dir, Git lists the gitdir as the primary record; the work tree is covered here.)
  local protected = { home, cwd, common, absgit }
  local top = git_out(cwd, { "rev-parse", "--show-toplevel" })
  if top then
    protected[#protected + 1] = top
  end
  if primary then
    protected[#protected + 1] = primary
  end
  for _, x in ipairs(protected) do
    if contains_path(canon, x) then
      error("target contains protected path " .. x, 0)
    end
  end

  local exact
  for _, r in ipairs(regs) do
    if norm(r.path) == canon then
      exact = r
    elseif not r.bare then
      if contains_path(canon, r.path) then
        error("target contains registered worktree " .. r.path, 0)
      end
      if contains_path(r.path, canon) then
        error("target is inside registered worktree " .. r.path, 0)
      end
    end
  end

  -- Git metadata: inside a non-bare .git is never allowed; inside a bare common
  -- dir only non-reserved children (e.g. feature/foo) are allowed.
  if canon ~= common and contains_path(common, canon) then
    if not is_bare then
      error("target is inside the git directory", 0)
    end
    local first = canon:sub(#common + 2):match("^[^/]+")
    if RESERVED[first] then
      error("target uses reserved git directory name " .. first, 0)
    end
  end

  if exact then
    if exact.bare then
      error("target is a bare repository", 0)
    end
    if leaf then
      check_destructive(canon, leaf, area, common, true)
    end
    -- Stale = registration with no directory at all. A prunable record whose
    -- directory still exists must be confirmed like any other worktree.
    return { kind = "registered", stale = leaf == nil, canon = canon, leaf = leaf }
  end
  if leaf == nil then
    return { kind = "missing", canon = canon }
  end
  if leaf.type ~= "directory" then
    error("target exists and is not a directory", 0)
  end
  if #dir_entries(canon) == 0 then
    return { kind = "empty", canon = canon, leaf = leaf }
  end
  check_destructive(canon, leaf, area, common, false)
  return { kind = "plain", canon = canon, leaf = leaf }
end

-- Everything the safety decision depends on; compared again after confirmation.
local function snapshot(abs, cwd, branch)
  if cwd_changed(cwd) then
    error("working directory changed", 0)
  end
  local leaf = walk_raw(abs)
  local regs, rerr = registrations(cwd)
  if not regs then
    error("cannot list worktrees: " .. tostring(rerr), 0)
  end
  local keys = {}
  for _, r in ipairs(regs) do
    keys[#keys + 1] = table.concat({ r.path, r.branch or "", tostring(r.bare), tostring(r.prunable) }, "\t")
  end
  table.sort(keys)
  return {
    cwd = norm(vim.fn.getcwd()),
    leaf = leaf and { dev = leaf.dev, ino = leaf.ino, type = leaf.type } or false,
    regs = table.concat(keys, "\n"),
    branch = git_out(cwd, { "rev-parse", "--verify", "--quiet", "refs/heads/" .. branch }) or false,
  }
end

-- Switch like the plugin: cd through nvim_cmd args (no manual escaping), clearjumps,
-- SWITCH hooks. Only the path is an argument; nothing is concatenated into a string.
local function switch_to(path)
  Hooks = Hooks or require("git-worktree.hooks")
  local prev = vim.fn.getcwd()
  local Config = require("git-worktree.config")
  -- nvim_cmd does not escape args (verified: '#' and '%' are expanded), so escape here.
  vim.cmd({ cmd = Config.change_directory_command, args = { vim.fn.fnameescape(path) } })
  if Config.clearjumps_on_change then
    vim.cmd("clearjumps")
  end
  Hooks.emit(Hooks.type.SWITCH, path, prev)
  vim.notify("Switched to " .. path, vim.log.levels.INFO)
end

-- Only one creation flow may run at a time. Released on success, cancel or error.
local creating = false

-- Create a worktree for `sel` at `input` (relative to cwd or absolute).
-- Callback-driven (no coroutine), so the deletion flow's busy guard is untouched.
---@param cwd string
---@param sel { branch: string, upstream: string? }
---@param input string
local function create_flow(cwd, sel, input)
  if creating then
    return vim.notify("A worktree creation is already in progress", vim.log.levels.WARN)
  end
  creating = true
  local function fail(msg)
    creating = false
    vim.notify(msg, vim.log.levels.ERROR)
  end
  local function guard(fn)
    return function(...)
      local ok, err = pcall(fn, ...)
      if not ok then
        fail("Worktree creation aborted: " .. tostring(err))
      end
    end
  end

  -- Final step: fresh local-presence decision, then git worktree add (no yields).
  local function add(cls)
    local branch = sel.branch
    local argv
    if git_out(cwd, { "rev-parse", "--verify", "--quiet", "refs/heads/" .. branch }) then
      argv = { "worktree", "add", cls.canon, branch }
    elseif sel.upstream then
      argv = { "worktree", "add", "-b", branch, "--track", cls.canon, sel.upstream }
    else
      argv = { "worktree", "add", "-b", branch, cls.canon }
    end
    local ok, err = git(cwd, argv)
    if not ok then
      return fail(("git worktree add failed for %s:\n%s"):format(cls.canon, err))
    end
    creating = false
    Hooks = Hooks or require("git-worktree.hooks")
    Hooks.emit(Hooks.type.CREATE, cls.canon, branch, sel.upstream)
    switch_to(cls.canon)
  end

  -- Clear the target (only for plain/registered, after confirmation), then add.
  local function clear_and_add(cls)
    if cls.kind == "plain" then
      if vim.fn.delete(cls.canon, "rf") ~= 0 then
        return fail("could not delete existing directory " .. cls.canon)
      end
      if lstat_strict(cls.canon) then
        return fail("directory still present after deletion; not creating " .. cls.canon)
      end
    elseif cls.kind == "registered" then
      if cls.stale and lstat_strict(cls.canon) then
        return fail("a directory appeared at " .. cls.canon .. "; not removing its registration")
      end
      local ok, err = git(cwd, { "worktree", "remove", "--force", cls.canon })
      if not ok then
        return fail(("git worktree remove --force failed for %s (branch kept):\n%s"):format(cls.canon, err))
      end
      if lstat_strict(cls.canon) then
        return fail("directory still present after git worktree remove; not creating " .. cls.canon)
      end
    end
    add(cls)
  end

  local ok, cls, snap = pcall(function()
    local abs = input:sub(1, 1) == "/" and input or (cwd .. "/" .. input)
    local c = classify(abs, cwd)
    local all = worktrees()
    if not all then
      error("cannot list worktrees", 0)
    end
    for _, wt in ipairs(all) do
      if wt.branch == sel.branch then
        error(("Branch '%s' is already checked out in %s"):format(sel.branch, wt.path), 0)
      end
    end
    return c, snapshot(c.canon, cwd, sel.branch)
  end)
  if not ok then
    return fail("Worktree creation refused: " .. tostring(cls))
  end

  local prompt
  if cls.kind == "plain" then
    prompt = ("Delete ALL contents of %s, including uncommitted and untracked files, then create the worktree?")
      :format(cls.canon)
  elseif cls.kind == "registered" and not cls.stale then
    prompt = ("Force-remove the registered worktree %s (uncommitted changes are lost; its branch is kept)?")
      :format(cls.canon)
  end
  if not prompt then
    return guard(clear_and_add)(cls)
  end

  vim.ui.select({ "No", "Yes" }, { prompt = prompt }, guard(function(choice)
    if choice ~= "Yes" then
      creating = false
      return vim.notify("Worktree creation cancelled; nothing changed", vim.log.levels.INFO)
    end
    -- Reclassify and compare everything the decision depended on before deleting.
    local again = classify(cls.canon, cwd)
    if again.kind ~= cls.kind or not vim.deep_equal(snapshot(cls.canon, cwd, sel.branch), snap) then
      error("target or Git state changed during confirmation; nothing removed", 0)
    end
    clear_and_add(again)
  end))
end

-- Ask for the worktree path (default from default_worktree_path), then create it.
---@param st table
---@param sel { branch: string, upstream: string? }
---@param cwd string
local function prompt_path_and_create(st, sel, cwd)
  if st.remote_shorts[sel.branch] then
    return vim.notify(
      ("'%s' is also a remote-tracking branch name; refusing to create an ambiguous worktree"):format(sel.branch),
      vim.log.levels.ERROR
    )
  end
  Snacks.input({ prompt = "Worktree path:", default = default_worktree_path(cwd, sel.branch) }, function(path)
    path = vim.trim(path or "")
    if path == "" then
      return
    end
    if cwd_changed(cwd) then
      return vim.notify("Working directory changed; retry <leader>gW from the original repository", vim.log.levels.ERROR)
    end
    local problem = path_problem(path)
    if problem then
      return vim.notify(("Worktree path '%s' %s"):format(path, problem), vim.log.levels.ERROR)
    end
    create_flow(cwd, sel, path)
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
        local rok, rerr = pcall(picker.find, picker, { refresh = true })
        if not rok then
          vim.notify("Could not refresh the branch list: " .. tostring(rerr), vim.log.levels.ERROR)
        end
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
  local probe, err = scan_branches(cwd) -- validates the repo before opening
  if not probe then
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
        -- Re-resolve against the fresh scan so a vanished ref is never recreated.
        local ref
        if item.kind == "local" then
          ref = fresh.locals[item.name]
        else
          ref = fresh.remote_shorts[item.short]
        end
        if not ref then
          return vim.notify(("'%s' no longer exists; reopen <leader>gW"):format(item.short or item.name), vim.log.levels.ERROR)
        end
        sel = resolve_entry(fresh, ref)
      elseif typed ~= "" then
        sel = resolve_typed(fresh, cwd, typed)
      end
      if sel then
        prompt_path_and_create(fresh, sel, cwd)
      end
    end,
  })
end

return M
