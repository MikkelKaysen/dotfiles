-- Custom build of the Neorg `norg` tree-sitter parser (C + C++ scanner), pinned to one
-- upstream commit. Replaces the native nvim-treesitter install for norg, which the
-- main-branch registry no longer provides. Linux only.
--
-- Trust: HTTPS to codeload.github.com at an immutable commit (the same upstream trust as
-- vim.pack). No checksum is pinned, so the first download is not independently authenticated.
--
-- Flow: lock -> fresh 0700 workspace -> curl -> tar -> file checks -> cc/c++ -> link to a
-- temp .so in the install dir -> validate in a child nvim -> rename over norg.so -> marker.
-- A failure never touches an existing norg.so or marker.

local M = {}

local uv = vim.uv

local REVISION = "aa1a1a7ded81a094cc3d5cb14bea6f34b86d8688" -- tree-sitter-norg tag v0.2.4
local URL = "https://codeload.github.com/nvim-neorg/tree-sitter-norg/tar.gz/" .. REVISION
local TIMEOUT = 300000 -- ms per subprocess

local building = false

local function site()
  return vim.fn.stdpath("data") .. "/site"
end

local function paths()
  local cache = vim.fn.stdpath("cache") .. "/norg-parser"
  return {
    cache = cache,
    lock = cache .. ".lock", -- cross-instance lock; a directory created atomically
    lib = site() .. "/parser/norg.so",
    marker = site() .. "/parser-info/norg.revision",
    parser_dir = site() .. "/parser",
    info_dir = site() .. "/parser-info",
  }
end

local function notify(msg, level)
  vim.schedule(function()
    vim.notify("norg parser: " .. msg, level or vim.log.levels.INFO)
  end)
end

---@return boolean
function M.is_current()
  local p = paths()
  if not uv.fs_stat(p.lib) then
    return false
  end
  local f = io.open(p.marker, "r")
  if not f then
    return false
  end
  local rev = vim.trim(f:read("*a") or "")
  f:close()
  return rev == REVISION
end

-- Runs argv (never a shell) with a timeout; cb(ok, message). Spawn errors are reported, not thrown.
local function sh(argv, opts, cb)
  local ok, err = pcall(vim.system, argv, {
    cwd = opts.cwd,
    timeout = TIMEOUT,
    text = true,
  }, function(r)
    vim.schedule(function()
      if r.code == 0 then
        return cb(true)
      end
      local tail = vim.trim(r.stderr or ""):sub(-400)
      cb(false, ("%s failed (exit %s): %s"):format(argv[1], tostring(r.code), tail))
    end)
  end)
  if not ok then
    vim.schedule(function()
      cb(false, ("could not run %s: %s"):format(argv[1], tostring(err)))
    end)
  end
end

-- True only for a regular file (lstat: symlinks are rejected, not followed).
local function regular_file(path)
  local st = uv.fs_lstat(path)
  return st ~= nil and st.type == "file"
end

-- Runs steps in sequence; step(ctx, nxt) calls nxt(ok, message).
local function run_steps(steps, ctx, done)
  local i = 0
  local function nxt(ok, msg)
    if not ok then
      return done(false, msg)
    end
    i = i + 1
    local step = steps[i]
    if not step then
      return done(true)
    end
    local called, err = pcall(step, ctx, nxt)
    if not called then
      done(false, "internal error: " .. tostring(err))
    end
  end
  nxt(true)
end

-- Child validation: load the candidate path explicitly and parse a tiny norg document.
local CHECK_SCRIPT = [[
local path = os.getenv("NORG_PARSER_CHECK")
local ok, res = pcall(vim.treesitter.language.add, "norg", { path = path })
if not ok or res ~= true then io.stderr:write("load failed: " .. tostring(res)); os.exit(1) end
local ok2, root = pcall(function()
  return vim.treesitter.get_string_parser("* Test\n", "norg"):parse()[1]:root()
end)
if not ok2 or not root then io.stderr:write("parse failed: " .. tostring(root)); os.exit(1) end
if root:type() ~= "document" or root:has_error() then
  io.stderr:write("bad tree: " .. root:type()); os.exit(1)
end
os.exit(0)
]]

local function build_steps(p, force)
  return {
    function(ctx, nxt)
      for _, tool in ipairs({ "curl", "tar", "cc", "c++" }) do
        if vim.fn.executable(tool) ~= 1 then
          return nxt(false, "missing required tool: " .. tool)
        end
      end
      if not force and M.is_current() then
        ctx.skip = true
      end
      nxt(true)
    end,
    function(ctx, nxt)
      if ctx.skip then
        return nxt(true)
      end
      -- Fresh per-run workspace, 0700. Collision is a failure (no reuse of old trees).
      pcall(vim.fn.mkdir, p.cache, "p", "0700")
      pcall(vim.fn.mkdir, p.parser_dir, "p")
      pcall(vim.fn.mkdir, p.info_dir, "p")
      ctx.ws = ("%s/build-%d-%d"):format(p.cache, vim.fn.getpid(), uv.hrtime())
      local ok, err = uv.fs_mkdir(ctx.ws, 448)
      if not ok then
        return nxt(false, "workspace collision: " .. tostring(err))
      end
      ctx.src = ctx.ws .. "/src"
      ok, err = uv.fs_mkdir(ctx.src, 448)
      if not ok then
        return nxt(false, "workspace src: " .. tostring(err))
      end
      nxt(true)
    end,
    function(ctx, nxt)
      if ctx.skip then
        return nxt(true)
      end
      sh({
        "curl", "--fail", "--location", "--silent", "--show-error",
        "--proto", "=https", "--proto-redir", "=https",
        "--connect-timeout", "20", "--max-time", "240",
        "-o", ctx.ws .. "/src.tar.gz", URL,
      }, {}, nxt)
    end,
    function(ctx, nxt)
      if ctx.skip then
        return nxt(true)
      end
      sh({
        "tar", "-xzf", ctx.ws .. "/src.tar.gz", "--strip-components=1",
        "--no-same-owner", "--no-same-permissions", "-C", ctx.src,
      }, {}, nxt)
    end,
    function(ctx, nxt)
      if ctx.skip then
        return nxt(true)
      end
      -- Sources must be plain files; tree_sitter headers must be a real directory.
      local tsdir = uv.fs_lstat(ctx.src .. "/src/tree_sitter")
      if not (regular_file(ctx.src .. "/src/parser.c") and regular_file(ctx.src .. "/src/scanner.cc")) then
        return nxt(false, "archive missing src/parser.c or src/scanner.cc (as regular files)")
      end
      if not (tsdir and tsdir.type == "directory") then
        return nxt(false, "archive src/tree_sitter is not a real directory")
      end
      nxt(true)
    end,
    function(ctx, nxt)
      if ctx.skip then
        return nxt(true)
      end
      sh({ "cc", "-c", "-O2", "-fPIC", "-std=c11", "-Isrc", "src/parser.c", "-o", ctx.ws .. "/parser.o" },
        { cwd = ctx.src }, nxt)
    end,
    function(ctx, nxt)
      if ctx.skip then
        return nxt(true)
      end
      sh({ "c++", "-c", "-O2", "-fPIC", "-std=c++17", "-Isrc", "src/scanner.cc", "-o", ctx.ws .. "/scanner.o" },
        { cwd = ctx.src }, nxt)
    end,
    function(ctx, nxt)
      if ctx.skip then
        return nxt(true)
      end
      -- Link into the install dir so the final rename stays on one filesystem.
      ctx.tmp_so = ("%s/.norg-%d-%d.so"):format(p.parser_dir, vim.fn.getpid(), uv.hrtime())
      sh({ "c++", "-shared", "-fPIC", "-o", ctx.tmp_so, ctx.ws .. "/parser.o", ctx.ws .. "/scanner.o" }, {}, nxt)
    end,
    function(ctx, nxt)
      if ctx.skip then
        return nxt(true)
      end
      local check = ctx.ws .. "/check.lua"
      local f = io.open(check, "w")
      if not f then
        return nxt(false, "could not write validation script")
      end
      f:write(CHECK_SCRIPT)
      f:close()
      local ok, err = pcall(vim.system, { vim.v.progpath, "--clean", "--headless", "-l", check }, {
        env = { NORG_PARSER_CHECK = ctx.tmp_so },
        timeout = 60000,
        text = true,
      }, function(r)
        vim.schedule(function()
          if r.code == 0 then
            return nxt(true)
          end
          nxt(false, "candidate parser failed validation: " .. vim.trim(r.stderr or ""):sub(-300))
        end)
      end)
      if not ok then
        nxt(false, "could not start validation: " .. tostring(err))
      end
    end,
    function(ctx, nxt)
      if ctx.skip then
        return nxt(true)
      end
      -- Atomic replace only after validation. Marker written via temp + rename.
      local ok, err = uv.fs_rename(ctx.tmp_so, p.lib)
      if not ok then
        return nxt(false, "install rename failed: " .. tostring(err))
      end
      ctx.tmp_so = nil
      local tmp_marker = p.marker .. ".tmp"
      local f = io.open(tmp_marker, "w")
      if not f then
        return nxt(false, "could not write revision marker")
      end
      f:write(REVISION .. "\n")
      f:close()
      ok, err = uv.fs_rename(tmp_marker, p.marker)
      if not ok then
        return nxt(false, "marker rename failed: " .. tostring(err))
      end
      nxt(true)
    end,
  }
end

---@param opts? { force?: boolean }
function M.build(opts)
  opts = opts or {}
  if building then
    return notify("a build is already running in this session")
  end
  if vim.fn.has("win32") == 1 or vim.fn.has("mac") == 1 then
    return notify("only Linux is supported by this builder", vim.log.levels.WARN)
  end

  local p = paths()
  pcall(vim.fn.mkdir, vim.fn.fnamemodify(p.cache, ":h"), "p")
  local lock_ok = uv.fs_mkdir(p.lock, 448)
  if not lock_ok then
    return notify(
      ("another build holds %s. If no build is running, remove that directory by hand and retry :NorgParserBuild"):format(p.lock),
      vim.log.levels.WARN
    )
  end

  building = true
  local ctx = {}
  local function finish(ok, msg)
    if ctx.tmp_so then
      uv.fs_unlink(ctx.tmp_so) -- our own temp file only; the installed norg.so is never touched
    end
    uv.fs_rmdir(p.lock)
    building = false
    if ok and ctx.skip then
      return
    end
    if ok then
      pcall(function()
        require("util.treesitter").get_installed(true)
      end)
      notify("parser built and validated. Restart Neovim if a previous norg parser was already loaded.")
    else
      notify("build failed: " .. tostring(msg) .. " (existing parser left unchanged; workspace kept at " .. tostring(ctx.ws) .. ")", vim.log.levels.ERROR)
    end
  end

  -- Build steps run on the main loop; the callbacks keep it non-blocking.
  vim.schedule(function()
    run_steps(build_steps(p, opts.force), ctx, finish)
  end)
end

---Runs at startup: builds only if missing or outdated. Silent when current.
function M.setup()
  vim.api.nvim_create_user_command("NorgParserBuild", function()
    M.build({ force = true })
  end, { desc = "Rebuild the custom norg tree-sitter parser (pinned revision)" })

  if not M.is_current() then
    vim.schedule(function()
      M.build({ force = false })
    end)
  end
end

return M
