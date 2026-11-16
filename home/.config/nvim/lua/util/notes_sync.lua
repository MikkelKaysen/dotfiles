-- Git sync for the Neorg notes repository.
--
-- Scope: only personal/**/*.norg and work/**/*.norg may be committed. Any other
-- change, staged content, conflict, or in-progress git operation stops the run.
-- Runs are serialized per session and guarded by a lock directory in the git dir.
-- Nothing is ever forced, reset, stashed, or auto-aborted.

local M = {}

local uv = vim.uv

local COMMIT_MESSAGE = "__NOTES_SYNC_COMMIT_MESSAGE__" -- placeholder until the commit-message delegate text is wired in
local ALLOWED_STATUS = { ["??"] = true, [" M"] = true, [" D"] = true }
local IN_PROGRESS = { "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply", "index.lock" }

local cfg = {
  root = nil, -- absolute path of the notes repository (real path)
  expected_remote = nil, -- ssh URL that origin fetch and push must equal
  debounce_ms = 5000,
  timeout_ms = 120000,
}

local st = {
  busy = false,
  queued = false,
  paused = false, -- set after a failure; auto runs stop until :NotesSync
  deferred = false, -- last run postponed (unsaved buffers, or files changed mid-run)
  initial_done = false,
  timer = nil,
  setup_done = false,
}

---@param msg string
---@param level? integer
local function notify(msg, level)
  vim.schedule(function()
    vim.notify("NotesSync: " .. msg, level or vim.log.levels.INFO)
  end)
end

---@param s string
---@param n? integer
local function short(s, n)
  s = vim.trim(s or ""):gsub("%c+", " ")
  n = n or 300
  if #s > n then
    s = s:sub(1, n) .. "..."
  end
  return s
end

---@param path string
local function in_scope_path(path)
  if not cfg.root or not path then
    return false
  end
  local prefix = cfg.root .. "/"
  if path:sub(1, #prefix) ~= prefix then
    return false
  end
  local rel = path:sub(#prefix + 1)
  return (rel:match("^personal/.+%.norg$") or rel:match("^work/.+%.norg$")) ~= nil
end

---@return boolean
local function notes_buffer_modified()
  local prefix = cfg.root .. "/"
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified then
      local name = vim.api.nvim_buf_get_name(b)
      if name:sub(1, #prefix) == prefix then
        return true
      end
    end
  end
  return false
end

-- Runs git with an argv list in the notes repo. Never prompts, never runs a shell.
---@param args string[]
---@param cb fun(ok: boolean, stdout: string, stderr: string)
local function git(args, cb)
  local argv = vim.list_extend({ "git" }, args)
  local env = {
    GIT_TERMINAL_PROMPT = "0",
    -- Skip only the LocalAI prepare-commit-msg hook; all other hooks stay active.
    SKIP_LLM_GITHOOK = "1",
    -- Batch mode: fail instead of prompting. Overrides core.sshCommand, but ~/.ssh/config still applies.
    GIT_SSH_COMMAND = vim.env.GIT_SSH_COMMAND or "ssh -o BatchMode=yes -o ConnectTimeout=20",
  }
  vim.system(argv, { cwd = cfg.root, env = env, timeout = cfg.timeout_ms }, function(r)
    vim.schedule(function()
      cb(r.code == 0, r.stdout or "", r.stderr or "")
    end)
  end)
end

-- Splits a NUL-terminated list (git -z output).
---@param out string
---@return string[]
local function split_nul(out)
  local items = {}
  for item in out:gmatch("([^%z]+)") do
    items[#items + 1] = item
  end
  return items
end

-- Parses `git status --porcelain=v1 -z --untracked-files=all --no-renames`.
---@param out string
---@return {xy: string, path: string}[]?, string?
local function parse_status(out)
  local entries = {}
  local i = 1
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

-- Rejects unsafe paths: absolute, parent refs, or any symlink/non-directory ancestor.
-- Missing paths (deletions) are fine as long as their existing ancestors are plain directories.
---@param rel string
---@return boolean, string?
local function safe_rel_path(rel)
  if rel:sub(1, 1) == "/" or rel:find("%.%.") or rel:find("\\", 1, true) then
    return false, "unsafe path"
  end
  if not (rel:match("^personal/.+%.norg$") or rel:match("^work/.+%.norg$")) then
    return false, "path outside personal/ or work/ .norg files"
  end
  local acc = cfg.root
  local parts = vim.split(rel, "/", { plain = true })
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

-- Validates the status entries. Returns the list of norg paths to stage.
---@param entries {xy: string, path: string}[]
---@return string[]?, string?
local function validate_entries(entries)
  local paths = {}
  for _, e in ipairs(entries) do
    if not ALLOWED_STATUS[e.xy] then
      return nil, "refusing: unexpected change state '" .. e.xy .. "' (staged, conflicted, or non-note change)"
    end
    local ok, why = safe_rel_path(e.path)
    if not ok then
      return nil, "refusing: " .. why
    end
    paths[#paths + 1] = e.path
  end
  return paths
end

-- Lock directory in the git dir. Stale locks are NOT removed automatically.
local function acquire_lock(gitdir)
  local dir = gitdir .. "/notes-sync.lock"
  local ok, err = uv.fs_mkdir(dir, 448)
  if not ok then
    return nil, "another NotesSync is running or a stale lock exists (" .. dir .. "): " .. short(tostring(err), 120)
  end
  return dir
end

-- Sequential async steps. Each step(ctx, next) calls next(ok, detail).
---@param steps {name: string, run: fun(ctx: table, next: fun(ok: boolean, detail?: string))}[]
---@param done fun(ok: boolean, failed?: string, detail?: string, ctx: table)
local function run_steps(steps, done)
  local ctx = {}
  local function go(i)
    local step = steps[i]
    if not step then
      return done(true, nil, nil, ctx)
    end
    step.run(ctx, function(ok, detail)
      if not ok then
        return done(false, step.name, detail, ctx)
      end
      go(i + 1)
    end)
  end
  go(1)
end

local function finish(ok, failed, detail, ctx)
  if ctx.lockdir then
    uv.fs_rmdir(ctx.lockdir)
  end
  st.busy = false

  if not ok then
    if ctx.lock_refused then
      notify(detail or "busy", vim.log.levels.WARN)
    else
      st.paused = true
      notify(
        ("sync failed at '%s': %s. Auto sync paused; fix the repo (see README) then run :NotesSync."):format(
          failed or "?",
          short(detail)
        ),
        vim.log.levels.ERROR
      )
    end
  elseif ctx.skipped then
    st.deferred = true
    notify(ctx.skipped .. " (saved changes stay local until the next sync)", vim.log.levels.WARN)
  else
    st.deferred = false
    notify(ctx.summary or "sync complete")
  end

  -- Reload only unmodified notes buffers, never force-reload.
  local prefix = cfg.root .. "/"
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b) or ""
    if name:sub(1, #prefix) == prefix and not vim.bo[b].modified then
      vim.api.nvim_buf_call(b, function()
        vim.cmd("silent! checktime")
      end)
    end
  end

  if st.queued and not st.paused then
    st.queued = false
    M.run("auto")
  end
end

local function build_steps()
  return {
    {
      name = "repo",
      run = function(ctx, next)
        git({ "rev-parse", "--show-toplevel", "--absolute-git-dir" }, function(ok, out, err)
          if not ok then
            return next(false, err)
          end
          local top, gitdir = out:match("^(.-)\n(.-)\n?$")
          if not top or uv.fs_realpath(vim.trim(top)) ~= cfg.root then
            return next(false, "not the notes repository root")
          end
          ctx.gitdir = vim.trim(gitdir)
          local lockdir, lerr = acquire_lock(ctx.gitdir)
          if not lockdir then
            ctx.lock_refused = true
            return next(false, lerr)
          end
          ctx.lockdir = lockdir
          next(true)
        end)
      end,
    },
    {
      name = "branch",
      run = function(ctx, next)
        git({ "symbolic-ref", "-q", "HEAD" }, function(ok, out)
          if not ok or vim.trim(out) ~= "refs/heads/main" then
            return next(false, "HEAD is not refs/heads/main")
          end
          if notes_buffer_modified() then
            ctx.skipped = "unsaved notes buffers, sync deferred"
            return next(true)
          end
          next(true)
        end)
      end,
    },
    {
      name = "remote",
      run = function(ctx, next)
        git({ "remote", "get-url", "--all", "origin" }, function(ok1, fetch_out, err1)
          if not ok1 then
            return next(false, err1)
          end
          git({ "remote", "get-url", "--push", "--all", "origin" }, function(ok2, push_out, err2)
            if not ok2 then
              return next(false, err2)
            end
            local fetch_urls, push_urls = split_nul(fetch_out:gsub("\n", "\0")), split_nul(push_out:gsub("\n", "\0"))
            if #fetch_urls ~= 1 or fetch_urls[1] ~= cfg.expected_remote then
              return next(false, "origin fetch URL differs from expected remote")
            end
            if #push_urls ~= 1 or push_urls[1] ~= cfg.expected_remote then
              return next(false, "origin push URL(s) differ from expected remote (pushurl set?)")
            end
            next(true)
          end)
        end)
      end,
    },
    {
      name = "in-progress",
      run = function(ctx, next)
        local args = { "rev-parse" }
        for _, name in ipairs(IN_PROGRESS) do
          vim.list_extend(args, { "--git-path", name })
        end
        git(args, function(ok, out, err)
          if not ok then
            return next(false, err)
          end
          local lines = vim.split(vim.trim(out), "\n", { plain = true })
          for _, p in ipairs(lines) do
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
      name = "fetch",
      run = function(ctx, next)
        git({ "fetch", "--no-tags", "origin", "main" }, function(ok, _, err)
          if not ok then
            return next(false, err)
          end
          git({ "rev-parse", "--verify", "-q", "refs/remotes/origin/main" }, function(ok2)
            if not ok2 then
              return next(false, "origin/main does not exist; bootstrap the repo first (see README)")
            end
            next(true)
          end)
        end)
      end,
    },
    {
      name = "status",
      run = function(ctx, next)
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
      name = "stage",
      run = function(ctx, next)
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
            local staged = split_nul(out)
            table.sort(staged)
            local want = vim.deepcopy(ctx.paths)
            table.sort(want)
            if vim.inspect(staged) ~= vim.inspect(want) then
              return next(false, "staged set differs from validated note paths")
            end
            next(true)
          end)
        end)
      end,
    },
    {
      name = "commit",
      run = function(ctx, next)
        if #ctx.paths == 0 then
          return next(true)
        end
        git({ "commit", "-m", COMMIT_MESSAGE }, function(ok, _, err)
          if not ok then
            return next(false, err)
          end
          ctx.summary = ("committed %d note change(s)"):format(#ctx.paths)
          next(true)
        end)
      end,
    },
    {
      name = "recheck",
      run = function(ctx, next)
        if ctx.skipped then
          return next(true)
        end
        if notes_buffer_modified() then
          ctx.skipped = "notes changed during sync, pull deferred"
          return next(true)
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
            ctx.skipped = "notes changed during sync, pull deferred"
          end
          next(true)
        end)
      end,
    },
    {
      name = "pull",
      run = function(ctx, next)
        if ctx.skipped then
          return next(true)
        end
        git({ "pull", "--rebase", "--no-autostash", "origin", "main" }, function(ok, _, err)
          if not ok then
            return next(false, err .. " (resolve with git status; rebase --continue or --abort; then :NotesSync)")
          end
          next(true)
        end)
      end,
    },
    {
      name = "push",
      run = function(ctx, next)
        if ctx.skipped then
          return next(true)
        end
        git({ "push", "origin", "HEAD:refs/heads/main" }, function(ok, _, err)
          if not ok then
            return next(false, err)
          end
          if not ctx.summary then
            ctx.summary = "sync complete"
          end
          next(true)
        end)
      end,
    },
  }
end

-- Starts a sync. "auto" respects pause/deferral; "manual" clears pause.
---@param kind "auto"|"manual"
function M.run(kind)
  if not cfg.setup_done then
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
  if notes_buffer_modified() then
    if kind == "manual" then
      notify("save or discard unsaved notes buffers first (sync not started)", vim.log.levels.WARN)
    else
      st.deferred = true
    end
    return
  end
  st.busy = true
  run_steps(build_steps(), function(ok, failed, detail, ctx)
    finish(ok, failed, detail, ctx)
  end)
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
---@field expected_remote string ssh URL origin must use
---@field debounce_ms? integer
---@field timeout_ms? integer

---@param opts NotesSyncOpts
function M.setup(opts)
  opts = opts or {}
  assert(opts.root and opts.expected_remote, "notes_sync.setup: root and expected_remote are required")
  cfg.debounce_ms = opts.debounce_ms or cfg.debounce_ms
  cfg.timeout_ms = opts.timeout_ms or cfg.timeout_ms
  cfg.expected_remote = opts.expected_remote
  cfg.root = uv.fs_realpath(vim.fs.normalize(opts.root)) or vim.fs.normalize(opts.root)
  cfg.setup_done = true

  local group = vim.api.nvim_create_augroup("NotesSyncAuto", { clear = true })

  -- First note of the session (after the initial BufRead) triggers one sync.
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = group,
    pattern = "*.norg",
    callback = function(ev)
      if st.initial_done then
        return
      end
      if in_scope_path(vim.api.nvim_buf_get_name(ev.buf)) then
        st.initial_done = true
        vim.schedule(function()
          M.run("auto")
        end)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.norg",
    callback = function(ev)
      if in_scope_path(vim.api.nvim_buf_get_name(ev.buf)) then
        arm_timer()
      end
    end,
  })

  -- Warn about pending work; never start or kill git at exit.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      local pending = st.busy or (st.timer and st.timer:is_active()) or st.deferred
      if pending then
        vim.notify(
          "NotesSync: sync pending at exit. Saved changes persist; run :NotesSync next session.",
          vim.log.levels.WARN
        )
      end
    end,
  })

  vim.api.nvim_create_user_command("NotesSync", function()
    M.run("manual")
  end, { desc = "Sync the Neorg notes repository (commit, pull --rebase, push)" })
end

-- test hook: expose pure helpers for focused fixture tests
M._parse_status = parse_status
M._safe_rel_path = safe_rel_path

return M
