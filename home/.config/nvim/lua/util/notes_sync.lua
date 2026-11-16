-- Git sync for the Neorg notes repository.
--
-- Scope: only personal/**/*.norg and work/**/*.norg may be committed. Any other
-- change, staged content, conflict, or in-progress git operation stops the run.
-- Runs are serialized per session and guarded by a lock directory in the git dir.
-- Nothing is ever forced, reset, stashed, or auto-aborted.
--
-- Pipeline: validate (no network) -> stage/commit (offline OK) -> pull --rebase -> push.
-- A failed pull leaves the local commit in place; the next sync retries.

local M = {}

local uv = vim.uv

local COMMIT_MESSAGE = "__NOTES_SYNC_COMMIT_MESSAGE__" -- placeholder until the delegated message is wired in
local ALLOWED_STATUS = { ["??"] = true, [" M"] = true, [" D"] = true }
local IN_PROGRESS = { "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply", "index.lock" }
local REPO_ENV = { "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR" }
-- Step failure detail meaning "unsaved buffers: stop without pausing".
local DEFER = "defer"

local cfg = { root = nil, expected_remote = nil, debounce_ms = 5000, timeout_ms = 120000, ready = false }
local st = { busy = false, queued = false, paused = false, deferred = false, initial_done = false, timer = nil }

---@param msg string
---@param level? integer
local function notify(msg, level)
  vim.schedule(function()
    vim.notify("NotesSync: " .. msg, level or vim.log.levels.INFO)
  end)
end

---@param s? string
---@param n? integer
local function short(s, n)
  s = (vim.trim(s or ""):gsub("%c+", " "))
  n = n or 300
  if #s > n then
    s = s:sub(1, n) .. "..."
  end
  return s
end

-- Canonical absolute path. Existing paths resolve through symlinks; new files resolve
-- their nearest existing ancestor and append the rest. Aliases of the root compare equal.
---@param path? string
---@return string?
local function canonical(path)
  if not path or path == "" then
    return nil
  end
  local p, tail = vim.fs.normalize(path), {}
  while true do
    local real = uv.fs_realpath(p)
    if real then
      if #tail == 0 then
        return real
      end
      return real .. "/" .. table.concat(tail, "/")
    end
    local parent = vim.fs.dirname(p)
    if not parent or parent == p then
      return nil
    end
    table.insert(tail, 1, vim.fs.basename(p))
    p = parent
  end
end

-- True when a canonical path lies strictly under the notes root.
---@param canon? string
---@return boolean
local function under_root(canon)
  return canon ~= nil and canon:sub(1, #cfg.root + 1) == cfg.root .. "/"
end

---@param path? string
---@return boolean
local function in_scope(path)
  local canon = canonical(path)
  if not under_root(canon) then
    return false
  end
  local rel = canon:sub(#cfg.root + 2)
  return rel:match("^personal/.+%.norg$") ~= nil or rel:match("^work/.+%.norg$") ~= nil
end

-- Any loaded, modified buffer under the notes root (by canonical path) blocks the run.
---@return boolean
local function buffers_modified()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified then
      if under_root(canonical(vim.api.nvim_buf_get_name(b))) then
        return true
      end
    end
  end
  return false
end

-- Runs git with an argv list in the notes repo. Never prompts; never uses a shell.
-- Spawn failures (e.g. missing git) are reported through cb instead of thrown.
---@param args string[]
---@param cb fun(ok: boolean, stdout: string, stderr: string)
local function git(args, cb)
  local env = {
    GIT_TERMINAL_PROMPT = "0",
    -- Skip only the LocalAI prepare-commit-msg hook; other hooks stay active.
    SKIP_LLM_GITHOOK = "1",
    -- Batch mode fails instead of prompting. ~/.ssh/config still applies.
    GIT_SSH_COMMAND = vim.env.GIT_SSH_COMMAND or "ssh -o BatchMode=yes -o ConnectTimeout=20",
  }
  local ok, err = pcall(vim.system, vim.list_extend({ "git" }, args), {
    cwd = cfg.root,
    env = env,
    timeout = cfg.timeout_ms,
  }, function(r)
    vim.schedule(function()
      cb(r.code == 0, r.stdout or "", r.stderr or "")
    end)
  end)
  if not ok then
    vim.schedule(function()
      cb(false, "", "could not run git: " .. tostring(err))
    end)
  end
end

---@param out string
---@return string[]
local function lines(out)
  local res = {}
  for l in out:gmatch("[^\n]+") do
    res[#res + 1] = l
  end
  return res
end

-- Parses `git status --porcelain=v1 -z --untracked-files=all --no-renames` (NUL-safe).
---@return {xy: string, path: string}[]?, string?
local function parse_status(out)
  local entries, i = {}, 1
  while i <= #out do
    local nul = out:find("\0", i, true)
    if not nul then
      return nil, "malformed status output"
    end
    local rec = out:sub(i, nul - 1)
    i = nul + 1
    entries[#entries + 1] = { xy = rec:sub(1, 2), path = rec:sub(4) }
  end
  return entries
end

-- Rejects absolute/parent paths, non-norg files, and any symlink or non-directory ancestor.
-- Missing targets (deletions) are fine when their existing ancestors are real directories.
---@return boolean, string?
local function safe_rel_path(rel)
  if rel:sub(1, 1) == "/" or rel:find("\\", 1, true) then
    return false, "unsafe path"
  end
  for _, part in ipairs(vim.split(rel, "/", { plain = true })) do
    if part == "" or part == "." or part == ".." then
      return false, "unsafe path component"
    end
  end
  if not (rel:match("^personal/.+%.norg$") or rel:match("^work/.+%.norg$")) then
    return false, "path outside personal/ or work/ .norg files"
  end
  local parts = vim.split(rel, "/", { plain = true })
  local acc = cfg.root
  for idx, part in ipairs(parts) do
    acc = acc .. "/" .. part
    local stat = uv.fs_lstat(acc)
    if stat then
      if idx < #parts and stat.type ~= "directory" then
        return false, "ancestor is not a directory"
      end
      if idx == #parts and stat.type ~= "file" then
        return false, "target is not a regular file"
      end
    end
  end
  return true
end

---@return string[]?, string?
local function validate_entries(entries)
  local paths = {}
  for _, e in ipairs(entries) do
    if not ALLOWED_STATUS[e.xy] then
      return nil, "refusing: change state '" .. e.xy .. "' (staged, conflicted, or non-note change)"
    end
    local ok, why = safe_rel_path(e.path)
    if not ok then
      return nil, "refusing: " .. why
    end
    paths[#paths + 1] = e.path
  end
  return paths
end

-- Sorted copy used to compare path sets.
local function sorted(list)
  local c = vim.deepcopy(list)
  table.sort(c)
  return c
end

-- Ends a run in every case: releases the lock, clears busy, reports, reloads, drains queue.
---@param ctx table
---@param ok boolean
---@param step? string
---@param detail? string
local function finish(ctx, ok, step, detail)
  if ctx.lockdir then
    uv.fs_rmdir(ctx.lockdir)
    ctx.lockdir = nil
  end
  st.busy = false

  if ok then
    st.deferred = false
    notify(ctx.summary or "sync complete")
  elseif detail == DEFER then
    st.deferred = true
    notify("unsaved notes buffers; sync deferred until saved (no pause)", vim.log.levels.WARN)
  elseif ctx.lock_refused then
    notify(detail or "busy", vim.log.levels.WARN)
  else
    st.paused = true
    notify(
      ("sync failed at '%s': %s. Auto sync paused; fix the repo (see README) then run :NotesSync."):format(
        step or "?",
        short(detail)
      ),
      vim.log.levels.ERROR
    )
  end

  -- Reload only unmodified notes buffers; never force-reload.
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and not vim.bo[b].modified then
      if under_root(canonical(vim.api.nvim_buf_get_name(b))) then
        vim.api.nvim_buf_call(b, function()
          vim.cmd("silent! checktime")
        end)
      end
    end
  end

  if st.queued and not st.paused then
    st.queued = false
    M.run("auto")
  end
end

-- Runs steps in order. Each step is {name, fn(ctx, next)}; next(ok, detail) continues.
local function pipeline(steps, ctx, done)
  local i = 0
  local function next_step(ok, detail)
    if not ok then
      return done(false, steps[i].name, detail)
    end
    i = i + 1
    local step = steps[i]
    if not step then
      return done(true)
    end
    local called, err = pcall(step.fn, ctx, next_step)
    if not called then
      done(false, step.name, "internal error: " .. tostring(err))
    end
  end
  next_step(true)
end

-- One git query whose stdout must match `expect`.
local function expect_git(args, expect, msg)
  return function(_, next)
    git(args, function(ok, out)
      if not ok or vim.trim(out) ~= expect then
        return next(false, msg)
      end
      next(true)
    end)
  end
end

local function build_steps()
  return {
    {
      name = "repo",
      fn = function(ctx, next)
        git({ "rev-parse", "--show-toplevel", "--absolute-git-dir" }, function(ok, out, err)
          if not ok then
            return next(false, err)
          end
          local l = lines(out)
          if #l < 2 or uv.fs_realpath(l[1]) ~= cfg.root then
            return next(false, "not the notes repository root")
          end
          ctx.gitdir = l[2]
          local lockdir, lerr = uv.fs_mkdir(ctx.gitdir .. "/notes-sync.lock", 448)
          if not lockdir then
            ctx.lock_refused = true
            return next(false, "another NotesSync is running or a stale lock exists (" .. ctx.gitdir .. "/notes-sync.lock): " .. short(tostring(lerr), 120))
          end
          ctx.lockdir = ctx.gitdir .. "/notes-sync.lock"
          next(true)
        end)
      end,
    },
    -- Local-only checks (no network). Remote and upstream are validated from config.
    { name = "branch", fn = expect_git({ "symbolic-ref", "-q", "HEAD" }, "refs/heads/main", "HEAD is not refs/heads/main") },
    {
      name = "upstream",
      fn = function(ctx, next)
        expect_git({ "config", "--get", "branch.main.remote" }, "origin", "branch.main.remote is not origin")(ctx, function(ok, d)
          if not ok then
            return next(false, d)
          end
          expect_git({ "config", "--get", "branch.main.merge" }, "refs/heads/main", "branch.main.merge is not refs/heads/main")(ctx, function(ok2, d2)
            if not ok2 then
              return next(false, d2)
            end
            expect_git({ "rev-parse", "--symbolic-full-name", "main@{upstream}" }, "refs/remotes/origin/main", "main does not track origin/main")(ctx, next)
          end)
        end)
      end,
    },
    {
      name = "remote",
      fn = function(ctx, next)
        git({ "remote", "get-url", "--all", "origin" }, function(ok1, fetch_out, err1)
          if not ok1 then
            return next(false, err1)
          end
          git({ "remote", "get-url", "--push", "--all", "origin" }, function(ok2, push_out, err2)
            if not ok2 then
              return next(false, err2)
            end
            local f, p = lines(fetch_out), lines(push_out)
            if #f ~= 1 or f[1] ~= cfg.expected_remote then
              return next(false, "origin fetch URL differs from expected remote")
            end
            if #p ~= 1 or p[1] ~= cfg.expected_remote then
              return next(false, "origin push URL(s) differ from expected remote (pushurl set?)")
            end
            next(true)
          end)
        end)
      end,
    },
    {
      name = "in-progress",
      fn = function(_, next)
        local args = { "rev-parse" }
        for _, name in ipairs(IN_PROGRESS) do
          vim.list_extend(args, { "--git-path", name })
        end
        git(args, function(ok, out, err)
          if not ok then
            return next(false, err)
          end
          for _, p in ipairs(lines(out)) do
            local abs = p:sub(1, 1) == "/" and p or (cfg.root .. "/" .. p)
            if uv.fs_lstat(abs) then
              return next(false, "git operation in progress or index locked (" .. p .. "); resolve it first")
            end
          end
          next(true)
        end)
      end,
    },
    {
      name = "status",
      fn = function(ctx, next)
        git({ "status", "--porcelain=v1", "-z", "--untracked-files=all", "--no-renames" }, function(ok, out, err)
          if not ok then
            return next(false, err)
          end
          local entries, perr = parse_status(out)
          if not entries then
            return next(false, perr)
          end
          local paths, why = validate_entries(entries)
          if not paths then
            return next(false, why)
          end
          ctx.paths = paths
          next(true)
        end)
      end,
    },
    {
      -- Unsaved notes buffers defer the run before anything is staged or committed.
      name = "defer-check",
      fn = function(_, next)
        if buffers_modified() then
          return next(false, DEFER)
        end
        next(true)
      end,
    },
    {
      name = "stage",
      fn = function(ctx, next)
        if #ctx.paths == 0 then
          return next(true)
        end
        local args = { "--literal-pathspecs", "add", "--" }
        vim.list_extend(args, ctx.paths)
        git(args, function(ok, _, err)
          if not ok then
            return next(false, err)
          end
          git({ "diff", "--cached", "--name-only", "-z" }, function(ok2, out)
            if not ok2 then
              return next(false, "could not read staged files")
            end
            local staged = {}
            for item in out:gmatch("([^%z]+)") do
              staged[#staged + 1] = item
            end
            if vim.inspect(sorted(staged)) ~= vim.inspect(sorted(ctx.paths)) then
              return next(false, "staged set differs from validated note paths")
            end
            next(true)
          end)
        end)
      end,
    },
    {
      name = "commit",
      fn = function(ctx, next)
        if #ctx.paths == 0 then
          return next(true)
        end
        git({ "commit", "-m", COMMIT_MESSAGE }, function(ok, _, err)
          if not ok then
            return next(false, err)
          end
          ctx.summary = ("committed %d note change(s) locally"):format(#ctx.paths)
          next(true)
        end)
      end,
    },
    {
      -- Re-validate after async work; anything still changing defers the pull.
      name = "recheck",
      fn = function(_, next)
        if buffers_modified() then
          return next(false, DEFER)
        end
        git({ "status", "--porcelain=v1", "-z", "--untracked-files=all", "--no-renames" }, function(ok, out, err)
          if not ok then
            return next(false, err)
          end
          local entries, perr = parse_status(out)
          if not entries then
            return next(false, perr)
          end
          if #entries > 0 then
            local _, why = validate_entries(entries)
            if why then
              return next(false, why)
            end
            -- Valid note changes arrived mid-run: keep them local, pull next time.
            return next(false, DEFER)
          end
          next(true)
        end)
      end,
    },
    {
      name = "pull",
      fn = function(_, next)
        git({ "pull", "--rebase", "--no-autostash", "origin", "main" }, function(ok, _, err)
          if not ok then
            return next(false, err .. " (local commit kept; resolve with git status, rebase --continue or --abort, then :NotesSync)")
          end
          next(true)
        end)
      end,
    },
    {
      name = "push",
      fn = function(ctx, next)
        git({ "push", "origin", "HEAD:refs/heads/main" }, function(ok, _, err)
          if not ok then
            return next(false, err)
          end
          ctx.summary = ctx.summary and (ctx.summary .. ", pushed") or "synced"
          next(true)
        end)
      end,
    },
  }
end

-- Starts a sync. "auto" respects pause and deferral; "manual" clears pause.
---@param kind "auto"|"manual"
function M.run(kind)
  if not cfg.ready then
    return
  end
  -- TODO: replace COMMIT_MESSAGE with the delegated commit-message text before enabling sync.
  if COMMIT_MESSAGE == "__NOTES_SYNC_COMMIT_MESSAGE__" then
    notify("setup unfinished: commit message placeholder still set; sync disabled (no git run)", vim.log.levels.WARN)
    return
  end
  if st.busy then
    st.queued = true
    return
  end
  if kind == "auto" and st.paused then
    return
  end
  if kind == "manual" then
    st.paused = false
  end
  -- Inherited repo redirection would make git operate an external index or worktree.
  for _, var in ipairs(REPO_ENV) do
    if vim.env[var] and vim.env[var] ~= "" then
      st.paused = true
      notify(("refusing sync: %s is set in the environment. Unset it and run :NotesSync."):format(var), vim.log.levels.ERROR)
      return
    end
  end
  if buffers_modified() then
    if kind == "manual" then
      notify("save or discard unsaved notes buffers first (sync not started)", vim.log.levels.WARN)
    else
      st.deferred = true
    end
    return
  end

  st.busy = true
  local ctx = {}
  local ok, err = pcall(pipeline, build_steps(), ctx, function(done_ok, step, detail)
    finish(ctx, done_ok, step, detail)
  end)
  if not ok then
    -- Unexpected error before the pipeline ran: release everything and report.
    finish(ctx, false, "start", tostring(err))
  end
end

local function arm_timer()
  if not st.timer then
    st.timer = uv.new_timer()
  end
  st.timer:stop()
  st.timer:start(
    cfg.debounce_ms,
    0,
    vim.schedule_wrap(function()
      M.run("auto")
    end)
  )
end

---@class NotesSyncOpts
---@field root string absolute path of the notes repo
---@field expected_remote string ssh URL origin fetch and push must equal
---@field debounce_ms? integer
---@field timeout_ms? integer

---@param opts NotesSyncOpts
function M.setup(opts)
  opts = opts or {}
  assert(opts.root and opts.expected_remote, "notes_sync.setup: root and expected_remote are required")
  cfg.root = uv.fs_realpath(vim.fs.normalize(opts.root)) or vim.fs.normalize(opts.root)
  cfg.expected_remote = opts.expected_remote
  cfg.debounce_ms = opts.debounce_ms or cfg.debounce_ms
  cfg.timeout_ms = opts.timeout_ms or cfg.timeout_ms
  cfg.ready = true

  local group = vim.api.nvim_create_augroup("NotesSyncAuto", { clear = true })

  -- The first note of the session triggers one sync.
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = group,
    pattern = "*.norg",
    callback = function(ev)
      if not st.initial_done and in_scope(vim.api.nvim_buf_get_name(ev.buf)) then
        st.initial_done = true
        vim.schedule(function()
          M.run("auto")
        end)
      end
    end,
  })

  -- Saving a note (re)arms the debounce; a deferred run resumes on the next save.
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.norg",
    callback = function(ev)
      if in_scope(vim.api.nvim_buf_get_name(ev.buf)) then
        arm_timer()
      end
    end,
  })

  -- Warn about pending work; never start or kill git at exit.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if st.busy or st.deferred or (st.timer and st.timer:is_active()) then
        vim.notify("NotesSync: sync pending at exit. Saved changes persist; run :NotesSync next session.", vim.log.levels.WARN)
      end
    end,
  })

  vim.api.nvim_create_user_command("NotesSync", function()
    M.run("manual")
  end, { desc = "Sync the Neorg notes repository (commit, pull --rebase, push)" })
end

-- Exposed for fixture tests.
M._parse_status = parse_status
M._safe_rel_path = safe_rel_path

return M
